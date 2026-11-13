import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Latest-release check against this app's GitHub repository.
///
/// Talked to the public REST API without a token — gork is open source and
/// its releases are public, so updates work before any account is connected.
class UpdateService {
  static const String repo = 'webdevshayan/gork';

  final http.Client client;
  final String currentVersion;
  final bool includePrereleases;
  final String downloadDir;

  UpdateService({
    required this.client,
    required this.currentVersion,
    this.includePrereleases = false,
    this.downloadDir = '/tmp',
  });

  /// 'v1.4.2' → [1, 4, 2]. Unparsable strings give an empty list, which
  /// compareVersions treats as "unknown, assume older".
  static List<int> parseVersion(String v) {
    final cleaned = v.trim().replaceFirst(RegExp('^v', caseSensitive: false), '');
    if (cleaned.isEmpty) return <int>[];
    final parts = <int>[];
    for (final piece in cleaned.split(RegExp(r'[.+-]'))) {
      final n = int.tryParse(piece);
      if (n == null) return parts; // '4-beta' → take what parsed cleanly
      parts.add(n);
    }
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }

  /// -1, 0 or 1 — like compareTo on the numeric parts.
  static int compareVersions(String a, String b) {
    final va = parseVersion(a);
    final vb = parseVersion(b);
    if (va.isEmpty || vb.isEmpty) return 0;
    for (var i = 0; i < 3; i++) {
      if (va[i] != vb[i]) return va[i] < vb[i] ? -1 : 1;
    }
    return 0;
  }

  /// Ask GitHub for the newest installable release.
  /// Never throws — a network problem is a status, not a crash.
  Future<UpdateCheck> check() async {
    try {
      final uri = Uri.parse('https://api.github.com/repos/$repo/releases')
          .replace(queryParameters: {'per_page': '10'});
      final res = await client.get(uri, headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'gork-app',
      });
      if (res.statusCode != 200) {
        return UpdateCheck.unknown(
            'GitHub answered HTTP ${res.statusCode} — try again later');
      }
      final List data = jsonDecodeList(res.body);
      // Scan every candidate and keep the highest version — don't trust the
      // API's ordering, just prefer the newest installable release.
      ReleaseInfo? best;
      for (final raw in data) {
        final release = raw as Map<String, dynamic>;
        if (release['draft'] == true) continue;
        if (release['prerelease'] == true && !includePrereleases) continue;
        final candidate = _fromRelease(release);
        if (candidate == null) continue;
        if (best == null || compareVersions(candidate.tag, best.tag) > 0) {
          best = candidate;
        }
      }
      if (best == null) {
        return UpdateCheck.unknown(
            'No release with an APK asset was found in $repo');
      }
      final cmp = compareVersions(best.tag, currentVersion);
      if (currentVersion.trim().isEmpty || cmp > 0) {
        return UpdateCheck.available(best);
      }
      return UpdateCheck.upToDate(best);
    } catch (e) {
      return UpdateCheck.unknown(e.toString());
    }
  }

  ReleaseInfo? _fromRelease(Map<String, dynamic> release) {
    final assets = (release['assets'] as List?) ?? const [];
    Map<String, dynamic>? apk;
    // Prefer the arm64 artifact the build ships, fall back to any APK.
    for (final a in assets) {
      final asset = a as Map<String, dynamic>;
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk') && name.contains('arm64')) {
        apk = asset;
        break;
      }
    }
    apk ??= assets.cast<Map<String, dynamic>>().firstWhere(
          (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
          orElse: () => <String, dynamic>{},
        );
    if (apk.isEmpty) return null;
    return ReleaseInfo(
      tag: release['tag_name'] as String? ?? '',
      name: release['name'] as String? ?? release['tag_name'] as String? ?? '',
      notes: release['body'] as String? ?? '',
      apkUrl: apk['browser_download_url'] as String? ?? '',
      apkName: apk['name'] as String? ?? 'gork.apk',
      apkSize: (apk['size'] as num?)?.toInt() ?? 0,
      prerelease: release['prerelease'] == true,
    );
  }

  /// Stream the APK into [downloadDir]. Verifies the byte count against the
  /// declared asset size — a truncated download is an error, not a success.
  Future<File> downloadApk(
    ReleaseInfo release, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final res = await client.send(
        http.Request('GET', Uri.parse(release.apkUrl))..followRedirects = true,
      );
      if (res.statusCode != 200) {
        throw UpdateException(
            'download failed: HTTP ${res.statusCode} for ${release.apkName}');
      }
      final dir = Directory(downloadDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File(
          '${dir.path}/${release.apkName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}');
      if (file.existsSync()) file.deleteSync();
      final sink = file.openSync(mode: FileMode.write);
      var received = 0;
      try {
        await for (final chunk in res.stream) {
          sink.writeFromSync(chunk);
          received += chunk.length;
          onProgress?.call(received, release.apkSize);
        }
      } finally {
        sink.closeSync();
      }
      if (received == 0) {
        throw UpdateException(
            'download came back empty — nothing to install');
      }
      if (release.apkSize > 0 && received < release.apkSize) {
        throw UpdateException(
            'download incomplete: $received of ${release.apkSize} bytes');
      }
      return file;
    } on UpdateException {
      rethrow;
    } catch (e) {
      throw UpdateException(e.toString());
    }
  }
}

/// One installable GitHub release.
class ReleaseInfo {
  final String tag;
  final String name;
  final String notes;
  final String apkUrl;
  final String apkName;
  final int apkSize;
  final bool prerelease;

  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.notes,
    required this.apkUrl,
    required this.apkName,
    required this.apkSize,
    required this.prerelease,
  });
}

enum UpdateStatus { upToDate, available, unknown }

/// The result of [UpdateService.check] — status plus what it knows.
class UpdateCheck {
  final UpdateStatus status;
  final ReleaseInfo? latest;
  final String? error;

  const UpdateCheck._(this.status, {this.latest, this.error});

  const UpdateCheck.available(ReleaseInfo release)
      : status = UpdateStatus.available,
        latest = release,
        error = null;

  const UpdateCheck.upToDate(ReleaseInfo release)
      : status = UpdateStatus.upToDate,
        latest = release,
        error = null;

  const UpdateCheck.unknown(this.error)
      : status = UpdateStatus.unknown,
        latest = null;

  /// Release notes of the checked release (empty when nothing was checked).
  String get notes => latest?.notes ?? '';
}

class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

dynamic jsonDecodeList(String body) {
  final parsed = const JsonDecoder().convert(body);
  if (parsed is List) return parsed;
  throw FormatException('expected a JSON array, got ${parsed.runtimeType}');
}
