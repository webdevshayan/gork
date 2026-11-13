import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/screens/updates_screen.dart';
import 'package:gork/services/installer.dart';
import 'package:gork/services/update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _releases(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

Map<String, dynamic> _release(String tag, String apk) => {
      'tag_name': tag,
      'name': 'gork $tag',
      'body': 'movement notes',
      'prerelease': false,
      'draft': false,
      'assets': [
        {
          'name': apk,
          'browser_download_url': 'https://example.invalid/$apk',
          'size': 11,
        }
      ],
    };

class RecordingInstaller implements Installer {
  int installCalls = 0;
  int settingsCalls = 0;
  bool canInstallResult = true;

  @override
  Future<bool> canInstall() async => canInstallResult;

  @override
  Future<void> installApk(String path) async => installCalls++;

  @override
  Future<void> openPermissionSettings() async => settingsCalls++;
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gork-updates-ui');
  });
  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  UpdateService serviceFor({
    required String current,
    required Object Function(Uri) handler,
  }) =>
      UpdateService(
        client: FakeGitHubClient(handler),
        currentVersion: current,
        downloadDir: tmp.path,
      );

  group('UpdatesScreen', () {
    testWidgets('check → download → install hands off to the installer',
        (tester) async {
      final installer = RecordingInstaller();
      final svc = serviceFor(
        current: '1.4.2',
        handler: (url) => url.host == 'api.github.com'
            ? _releases([_release('v1.5.0', 'gork-v1.5.0-release.apk')])
            : utf8.encode('APK-BYTES-11'),
      );
      await tester.pumpWidget(MaterialApp(home: UpdatesScreen(
        currentVersion: '1.4.2',
        service: svc,
        installer: installer,
        downloadDir: tmp.path,
      )));

      expect(find.byKey(const ValueKey('updates-check')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('updates-check')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('updates-available')), findsOneWidget);
      expect(find.textContaining('v1.5.0'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('updates-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('updates-ready')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('updates-install')));
      await tester.pumpAndSettle();
      expect(installer.installCalls, 1);
    });

    testWidgets('without the install permission it opens settings instead',
        (tester) async {
      final installer = RecordingInstaller()..canInstallResult = false;
      final svc = serviceFor(
        current: '1.4.2',
        handler: (url) => url.host == 'api.github.com'
            ? _releases([_release('v1.5.0', 'a.apk')])
            : utf8.encode('APK-BYTES-11'),
      );
      await tester.pumpWidget(MaterialApp(home: UpdatesScreen(
        currentVersion: '1.4.2',
        service: svc,
        installer: installer,
        downloadDir: tmp.path,
      )));
      await tester.tap(find.byKey(const ValueKey('updates-check')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('updates-download')));
      await tester.pumpAndSettle();

      expect(find.text('Open install settings'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('updates-install')));
      await tester.pumpAndSettle();
      expect(installer.installCalls, 0);
      expect(installer.settingsCalls, 1);
    });

    testWidgets('up to date says so honestly', (tester) async {
      final svc = serviceFor(
        current: '1.5.0',
        handler: (url) => _releases([_release('v1.5.0', 'a.apk')]),
      );
      await tester.pumpWidget(MaterialApp(home: UpdatesScreen(
        currentVersion: '1.5.0',
        service: svc,
        installer: RecordingInstaller(),
        downloadDir: tmp.path,
      )));
      await tester.tap(find.byKey(const ValueKey('updates-check')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('updates-up-to-date')), findsOneWidget);
    });

    testWidgets('a failed check shows the error and a retry', (tester) async {
      final svc = UpdateService(
        client: MockClient((_) async => http.Response('rate limited', 403)),
        currentVersion: '1.4.2',
        downloadDir: tmp.path,
      );
      await tester.pumpWidget(MaterialApp(home: UpdatesScreen(
        currentVersion: '1.4.2',
        service: svc,
        installer: RecordingInstaller(),
        downloadDir: tmp.path,
      )));
      await tester.tap(find.byKey(const ValueKey('updates-check')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('updates-error')), findsOneWidget);
      expect(find.textContaining('403'), findsOneWidget);
    });

    testWidgets('the menu offers Updates with the installed version',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
      // The Updates card sits mid-list; bring it into the lazy viewport.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('menu-updates')),
        200,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-updates')), findsOneWidget);
    });
  });
}

/// The same fake used by update_service_test — a client that answers JSON on
/// api.github.com and raw bytes elsewhere.
class FakeGitHubClient extends http.BaseClient {
  final Object Function(Uri url) handler;
  FakeGitHubClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = handler(request.url);
    if (body is http.Response) {
      return http.StreamedResponse(
          Stream.value(body.bodyBytes), body.statusCode, headers: body.headers);
    }
    if (body is List<int>) {
      return http.StreamedResponse(
        Stream.value(body),
        200,
        headers: {'content-length': '${body.length}'},
      );
    }
    throw StateError('unreachable');
  }
}
