// Movement 36 — the release pipeline is the only way an APK ships.
//
// Regression being guarded: kAppVersion is only real when the build gets
// --dart-define=GORK_VERSION. No script in the repo did that, so every
// release so far was built by hand — and a build without the define reports
// kAppVersion='dev', against which the updater never offers any release
// (parseVersion('dev') is empty → compareVersions returns 0 → "up to
// date"). Movement 35's slim build then sat unreleased on a machine nobody
// re-ran. This pins a single pipeline: version read from pubspec, define
// passed to flutter build, size gate run before anything ships.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gork/services/update_service.dart';

String readRepo(String path) => File(path).readAsStringSync();

void main() {
  group('release pipeline script', () {
    late String script;

    setUpAll(() {
      script = readRepo('scripts/release_apk.sh');
    });

    test('exists as bash with strict mode', () {
      expect(script, contains('#!/usr/bin/env bash'));
      expect(script, contains('set -euo pipefail'));
    });

    test('reads the version from pubspec.yaml — one source of truth', () {
      expect(script, contains('pubspec.yaml'));
    });

    test('passes the version to the build as GORK_VERSION', () {
      expect(script, contains('--dart-define=GORK_VERSION='));
    });

    test('runs the slim-release size gate before declaring success', () {
      expect(script, contains('check_release_apk.sh'));
    });

    test('dry run prints the exact plan without building', () async {
      final res =
          await Process.run('bash', ['scripts/release_apk.sh', '--dry-run']);
      expect(res.exitCode, 0, reason: res.stderr);
      expect(res.stdout, contains('flutter build apk --release'));
      expect(res.stdout, matches(RegExp(r'GORK_VERSION=\d+\.\d+\.\d+')));
      expect(res.stdout, contains('check_release_apk.sh'));
    });

    test('dry-run version matches pubspec.yaml exactly', () async {
      final pubspec = readRepo('pubspec.yaml');
      final RegExpMatch? m = RegExp(r'^version: (\d+\.\d+\.\d+)\+(\d+)$',
              multiLine: true)
          .firstMatch(pubspec);
      expect(m, isNotNull,
          reason: 'pubspec must declare version: X.Y.Z+N on its own line');
      final res =
          await Process.run('bash', ['scripts/release_apk.sh', '--dry-run']);
      expect(res.exitCode, 0, reason: res.stderr);
      expect(res.stdout, contains('version: ${m!.group(1)}+${m.group(2)}'));
    });

    test('builds the established slim shape: arm64-only, split-per-abi', () {
      // The release shape since Movement 30 (BUILD-ENV: 19-35 MB artifacts):
      // fat multi-ABI APKs are dead weight on the user's phone. One target,
      // one split — and no blanket debug-platform flags (the guard test
      // forbids those in gradle.properties for the same reason).
      expect(script, contains('--split-per-abi'));
      expect(script, contains('--target-platform android-arm64'));
    });

    test('gates the arm64 split artifact, not the fat APK', () {
      expect(script, contains('app-arm64-v8a-release.apk'));
      expect(script, isNot(contains('gate: scripts/check_release_apk.sh '
          'build/app/outputs/flutter-apk/app-release.apk')));
    });
  });

  group('unversioned builds never self-update', () {
    // The reason the pipeline exists: without GORK_VERSION the app reports
    // 'dev', and the updater must not mistake that for a real version —
    // 'dev' parses to nothing, so no release can ever look newer. These
    // tests pin that honest behavior instead of a silent false "up to date".
    test("parseVersion('dev') is empty", () {
      expect(UpdateService.parseVersion('dev'), isEmpty);
    });

    test("a 'dev' build is never told a release is newer (either direction)",
        () {
      expect(UpdateService.compareVersions('v1.6.0', 'dev'), 0);
      expect(UpdateService.compareVersions('dev', 'v1.6.0'), 0);
    });

    test("the 'v' prefix never confuses the comparison", () {
      expect(UpdateService.compareVersions('v1.6.0', '1.6.0'), 0);
      expect(UpdateService.compareVersions('v1.7.0', '1.6.0'), 1);
    });
  });
}
