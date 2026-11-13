import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gork/services/update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int code = 200]) => http.Response(
      jsonEncode(body),
      code,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _release({
  required String tag,
  required String apkName,
  bool prerelease = false,
  bool draft = false,
  String? notes,
  int size = 42 << 20,
}) =>
    {
      'tag_name': tag,
      'name': 'gork $tag',
      'body': notes ?? 'notes for $tag',
      'prerelease': prerelease,
      'draft': draft,
      'published_at': '2026-11-01T00:00:00Z',
      'assets': [
        {
          'name': apkName,
          'browser_download_url': 'https://example.invalid/$apkName',
          'size': size,
          'content_type': 'application/vnd.android.package-archive',
        },
        {
          'name': 'source.zip',
          'browser_download_url': 'https://example.invalid/source.zip',
          'size': 1024,
          'content_type': 'application/zip',
        },
      ],
    };

// A client that answers JSON on the API and bytes on the download host.
class FakeGitHub extends http.BaseClient {
  final Object Function(Uri url) handler;
  FakeGitHub(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final dynamic body = handler(request.url);
    if (body is http.Response) {
      return http.StreamedResponse(
        http.ByteStream.fromBytes(Uint8List.fromList(body.bodyBytes)),
        body.statusCode,
        headers: body.headers,
      );
    }
    if (body is List<int>) {
      return http.StreamedResponse(
        http.ByteStream.fromBytes(Uint8List.fromList(body)),
        200,
        headers: {'content-length': '${body.length}'},
      );
    }
    throw StateError('unreachable');
  }
}

void main() {
  group('version parsing', () {
    test('strips the v prefix and reads three numbers', () {
      expect(UpdateService.parseVersion('v1.4.2'), [1, 4, 2]);
      expect(UpdateService.parseVersion('1.4.2'), [1, 4, 2]);
      expect(UpdateService.parseVersion('v2.0.0'), [2, 0, 0]);
    });

    test('missing parts become zero, garbage becomes empty', () {
      expect(UpdateService.parseVersion('v1.4'), [1, 4, 0]);
      expect(UpdateService.parseVersion('garbage'), <int>[]);
      expect(UpdateService.parseVersion(''), <int>[]);
    });

    test('numeric compare handles multi-digit parts', () {
      expect(UpdateService.compareVersions('v1.10.0', 'v1.9.9'), 1);
      expect(UpdateService.compareVersions('v1.4.2', 'v1.4.2'), 0);
      expect(UpdateService.compareVersions('v1.4.1', 'v1.4.2'), -1);
      expect(UpdateService.compareVersions('v2.0.0', 'v1.9.9'), 1);
    });
  });

  group('check()', () {
    test('finds the newest release with an APK and reports available',
        () async {
      final svc = UpdateService(
        client: FakeGitHub((url) => _json([
              // older, first in list: must be skipped
              _release(tag: 'v1.4.2', apkName: 'gork-v1.4.2-release.apk'),
              _release(tag: 'v1.5.0', apkName: 'gork-v1.5.0-release.apk'),
            ])),
        currentVersion: '1.4.2',
      );
      final check = await svc.check();
      expect(check.status, UpdateStatus.available);
      expect(check.latest!.tag, 'v1.5.0');
      expect(check.latest!.apkUrl, 'https://example.invalid/gork-v1.5.0-release.apk');
      expect(check.notes, 'notes for v1.5.0');
    });

    test('reports upToDate when current matches the newest', () async {
      final svc = UpdateService(
        client: FakeGitHub((url) => _json([
              _release(tag: 'v1.4.2', apkName: 'gork-v1.4.2-release.apk'),
            ])),
        currentVersion: '1.4.2',
      );
      expect((await svc.check()).status, UpdateStatus.upToDate);
    });

    test('skips prereleases unless asked', () async {
      Future<UpdateCheck> run(bool include) async {
        final svc = UpdateService(
          client: FakeGitHub((url) => _json([
                _release(tag: 'v1.6.0-rc1', apkName: 'rc.apk', prerelease: true),
                _release(tag: 'v1.4.2', apkName: 'stable.apk'),
              ])),
          currentVersion: '1.4.2',
          includePrereleases: include,
        );
        return svc.check();
      }

      expect((await run(false)).latest!.tag, 'v1.4.2');
      expect((await run(true)).latest!.tag, 'v1.6.0-rc1');
    });

    test('skips releases that carry no APK asset', () async {
      final svc = UpdateService(
        client: FakeGitHub((url) => _json([
              {
                'tag_name': 'v2.0.0',
                'name': 'no binaries',
                'body': 'oops',
                'prerelease': false,
                'draft': false,
                'assets': [
                  {
                    'name': 'source.zip',
                    'browser_download_url': 'https://example.invalid/src.zip',
                    'size': 1,
                  }
                ],
              },
              _release(tag: 'v1.4.2', apkName: 'gork.apk'),
            ])),
        currentVersion: '1.4.2',
      );
      final check = await svc.check();
      expect(check.latest!.tag, 'v1.4.2');
    });

    test('prefers the arm64 APK over other APK assets', () async {
      final svc = UpdateService(
        client: FakeGitHub((url) => _json([
              {
                'tag_name': 'v1.5.0',
                'name': 'n',
                'body': 'b',
                'prerelease': false,
                'draft': false,
                'assets': [
                  {
                    'name': 'gork-v1.5.0-arm64.apk',
                    'browser_download_url': 'https://example.invalid/arm64.apk',
                    'size': 9,
                  },
                  {
                    'name': 'gork-v1.5.0-universal.apk',
                    'browser_download_url': 'https://example.invalid/uni.apk',
                    'size': 9,
                  },
                ],
              }
            ])),
        currentVersion: '1.4.2',
      );
      expect((await svc.check()).latest!.apkUrl,
          'https://example.invalid/arm64.apk');
    });

    test('an unknown current version still offers the update honestly',
        () async {
      final svc = UpdateService(
        client: FakeGitHub((url) =>
            _json([_release(tag: 'v1.5.0', apkName: 'a.apk')])),
        currentVersion: '',
      );
      expect((await svc.check()).status, UpdateStatus.available);
    });

    test('network failure is reported, never thrown', () async {
      final svc = UpdateService(
        client: MockClient((_) async => http.Response('rate limited', 403)),
        currentVersion: '1.4.2',
      );
      final check = await svc.check();
      expect(check.status, UpdateStatus.unknown);
      expect(check.error, contains('403'));
    });

    test('a transport exception lands in status unknown with the message',
        () async {
      final svc = UpdateService(
        client: MockClient((_) async => throw const SocketException('no net')),
        currentVersion: '1.4.2',
      );
      final check = await svc.check();
      expect(check.status, UpdateStatus.unknown);
      expect(check.error, isNotEmpty);
    });

    test('request hits the public releases endpoint without a token',
        () async {
      Uri? seen;
      final svc = UpdateService(
        client: FakeGitHub((url) {
          seen = url;
          return _json(<dynamic>[]);
        }),
        currentVersion: '1.4.2',
      );
      final check = await svc.check();
      expect(seen!.host, 'api.github.com');
      expect(seen!.path, '/repos/webdevshayan/gork/releases');
      expect(seen!.queryParameters['per_page'], '10');
      // public repo — no Authorization header needed
      expect(check.status, UpdateStatus.unknown); // empty release list
      expect(check.error, isNotEmpty);
    });
  });

  group('downloadApk()', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('gork-update-test');
    });
    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    ReleaseInfo release() => ReleaseInfo(
          tag: 'v1.5.0',
          name: 'gork v1.5.0',
          notes: 'n',
          apkUrl: 'https://example.invalid/gork.apk',
          apkName: 'gork.apk',
          apkSize: 5,
          prerelease: false,
        );

    test('writes the bytes and reports progress', () async {
      final svc = UpdateService(
        client: FakeGitHub((url) => [1, 2, 3, 4, 5]),
        currentVersion: '1.5.0',
        downloadDir: tmp.path,
      );
      final progress = <List<int>>[];
      final f = await svc.downloadApk(release(),
          onProgress: (done, total) => progress.add([done, total]));
      expect(f.lengthSync(), 5);
      expect(f.readAsBytesSync(), [1, 2, 3, 4, 5]);
      expect(progress.last, [5, 5]);
      expect(f.path, contains('gork.apk'));
    });

    test('a truncated download fails loudly', () async {
      final svc = UpdateService(
        client: FakeGitHub((url) => [1, 2, 3]), // declared size is 5
        currentVersion: '1.5.0',
        downloadDir: tmp.path,
      );
      await expectLater(
        svc.downloadApk(release()),
        throwsA(isA<UpdateException>()),
      );
    });

    test('an empty body fails loudly', () async {
      final svc = UpdateService(
        client: FakeGitHub((url) => <int>[]),
        currentVersion: '1.5.0',
        downloadDir: tmp.path,
      );
      await expectLater(
        svc.downloadApk(release()),
        throwsA(isA<UpdateException>()),
      );
    });

    test('http failure fails loudly', () async {
      final svc = UpdateService(
        client: MockClient((_) async => http.Response('nope', 404)),
        currentVersion: '1.5.0',
        downloadDir: tmp.path,
      );
      await expectLater(
        svc.downloadApk(release()),
        throwsA(isA<UpdateException>()),
      );
    });
  });
}
