// Movement 35 — slim release guards.
//
// Regression under test: gork v1.5.0 shipped a 180 MB APK because the
// release build packaged the unstripped Flutter engine (libflutter.so =
// 169 MB of debug symbols) instead of the normal ~11 MB stripped engine.
// The engine artifact on download.flutter.io ships unstripped upstream;
// AGP's strip step is what slims it. The v1.5.0 build disabled that strip
// (keepDebugSymbols blanket) to avoid the NDK. These tests pin the
// guardrails that make a bloated release impossible to ship unnoticed:
//
//   1. The release size gate script exists, checks the real failure
//      (libflutter.so size), and fails non-zero with a loud message.
//   2. The Android build config strips native libs again (no blanket) and
//      keeps the NDK-free-ish path honest (engine repo declared once).
//   3. The in-app updater surfaces a "bloated build" warning instead of
//      silently installing a suspiciously huge APK.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/updates_screen.dart';
import 'package:gork/services/installer.dart';
import 'package:gork/services/update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String repoRoot = '.';

String readRepo(String path) => File('$repoRoot/$path').readAsStringSync();

class RecordingInstaller implements Installer {
  @override
  Future<bool> canInstall() async => true;

  @override
  Future<void> installApk(String path) async {}

  @override
  Future<void> openPermissionSettings() async {}
}

void main() {
  group('release size gate script', () {
    late String script;

    setUpAll(() {
      script = readRepo('scripts/check_release_apk.sh');
    });

    test('exists and is executable by convention (bash, set -euo pipefail)', () {
      expect(script, contains('#!/usr/bin/env bash'));
      expect(script, contains('set -euo pipefail'));
    });

    test('guards the real regression: per-library size check on libflutter.so',
        () {
      expect(script, contains('libflutter.so'));
    });

    test('stripped engine threshold is sane (~11-13 MB stripped, 169 MB bug)',
        () {
      final RegExpMatch? m =
          RegExp(r'LIBFLUTTER_MAX_BYTES=(\d+)').firstMatch(script);
      expect(m, isNotNull,
          reason: 'script must expose LIBFLUTTER_MAX_BYTES as the threshold');
      final int bytes = int.parse(m!.group(1)!);
      // 16 MiB allows the stripped engine plus headroom, and is an order of
      // magnitude below the 169 MB debug engine that shipped in v1.5.0.
      expect(bytes, greaterThan(12 * 1024 * 1024));
      expect(bytes, lessThanOrEqualTo(16 * 1024 * 1024));
    });

    test('guards the whole APK size too', () {
      final RegExpMatch? m =
          RegExp(r'APK_MAX_BYTES=(\d+)').firstMatch(script);
      expect(m, isNotNull);
      final int bytes = int.parse(m!.group(1)!);
      // Historical stripped builds: 19-35 MB. 120 MiB is generous headroom
      // while still catching a debug-engine regression at 180+ MB.
      expect(bytes, greaterThan(40 * 1024 * 1024));
      expect(bytes, lessThanOrEqualTo(120 * 1024 * 1024));
    });

    test('verifies the APK is a real zip before judging sizes', () {
      expect(script, contains('unzip'));
    });

    test('fails loudly and non-zero when a gate trips', () {
      expect(script, contains('BLOATED RELEASE BLOCKED'));
      expect(script, contains('exit 1'));
    });
  });

  group('android build config honesty', () {
    test('release build strips native libs — no keepDebugSymbols blanket', () {
      // v1.5.0 shipped a 169 MB libflutter.so because the packaging block
      // kept debug symbols for every .so, which told AGP to skip the strip
      // step and made the build "NDK-free". The engine artifact on
      // download.flutter.io is unstripped upstream — the strip step IS the
      // thing that slims it to ~11 MB. It must never be blanket-disabled.
      final String gradle = readRepo('android/app/build.gradle.kts');
      expect(gradle, isNot(contains('keepDebugSymbols')));
    });

    test('flutter engine maven repo is declared exactly once', () {
      final RegExp re = RegExp('download\\.flutter\\.io');
      expect(re.allMatches(readRepo('android/settings.gradle.kts')).length, 1);
    });

    test('the engine repo reaches PROJECT resolution — allprojects too', () {
      // Gradle's default RepositoriesMode.PREFER_PROJECT means the root
      // allprojects repositories REPLACE the settings list for :app
      // resolution. Without download.flutter.io there, io.flutter engine
      // artifacts fall through to Maven Central and die on its 429s
      // (this killed the v1.7.0 build attempt #1).
      final gradle = readRepo('android/build.gradle.kts');
      expect(gradle, contains('download.flutter.io'));
      // Aliyun still comes before mavenCentral in the same block.
      final all = gradle.indexOf('allprojects');
      expect(gradle.indexOf('aliyun', all), greaterThan(all));
      expect(gradle.indexOf('mavenCentral', all),
          greaterThan(gradle.indexOf('aliyun', all)));
    });

    test('no build flag forces a debug/unstripped engine artifact', () {
      final String props = readRepo('android/gradle.properties');
      expect(props, isNot(contains('flutter.buildMode=debug')));
      expect(props, isNot(contains('-Ptarget-platform=android-arm64,android-arm64-debug')));
    });
  });

  group('in-app updater flags a bloated release', () {
    ReleaseInfo info(int bytes) => ReleaseInfo(
          tag: 'v1.5.0',
          name: 'gork v1.5.0',
          notes: '',
          apkUrl: 'https://example.invalid/x.apk',
          apkName: 'x.apk',
          apkSize: bytes,
          prerelease: false,
        );

    test('v1.5.0 real size (180121943 bytes — unstripped engine) is bloated',
        () {
      expect(info(180121943).bloatedBuild, isTrue);
    });

    test('normal stripped release (v1.4.2 = 19366150 bytes) is not', () {
      expect(info(19366150).bloatedBuild, isFalse);
    });

    testWidgets('Updates screen warns when the latest release is bloated',
        (tester) async {
      final releases = <Map<String, dynamic>>[
        {
          'tag_name': 'v1.5.0',
          'name': 'gork v1.5.0',
          'body': 'notes',
          'prerelease': false,
          'draft': false,
          'assets': [
            {
              'name': 'gork-v1.5.0-release.apk',
              'browser_download_url': 'https://example.invalid/x.apk',
              'size': 180121943,
            }
          ],
        }
      ];
      final svc = UpdateService(
        client: MockClient((_) async => http.Response(
              jsonEncode(releases),
              200,
              headers: {'content-type': 'application/json'},
            )),
        currentVersion: '1.4.2',
      );
      await tester.pumpWidget(MaterialApp(
        home: UpdatesScreen(
          currentVersion: '1.4.2',
          service: svc,
          installer: RecordingInstaller(),
          downloadDir: '/tmp/gork-updates-gate-test',
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('updates-check')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('updates-bloated-warning')), findsOneWidget);
      expect(find.textContaining('180.1 MB'), findsOneWidget);
    });
  });
}
