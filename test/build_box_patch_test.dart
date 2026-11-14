// build-box — the included flutter_tools gradle build must resolve via Aliyun.
//
// Regression being guarded: the app's own settings.gradle.kts puts the Aliyun
// mirrors before mavenCentral because repo.maven.apache.org 429s this network
// (Movement 30). But gradle resolves the Kotlin build tools
// (kotlin-build-tools-impl) inside the INCLUDED build
// $FLUTTER_ROOT/packages/flutter_tools/gradle — included builds do not
// inherit the app's repositories, and upstream flutter ships that file with
// google() + mavenCentral() only. The result: assembleRelease dies in 15
// seconds with a 429 before compiling anything (this exact failure blocked
// the v1.6.0 release build).
//
// The flutter SDK file can't be versioned in this repo — it regenerates with
// every toolchain install — so the repair lives in an idempotent patch
// script that every build-box rebuild runs once, documented in BUILD-ENV.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String readRepo(String path) => File(path).readAsStringSync();

void main() {
  group('build-box flutter_tools repository patch', () {
    late String script;

    setUpAll(() {
      script = readRepo('scripts/patch_flutter_tools_repos.sh');
    });

    test('exists as bash with strict mode', () {
      expect(script, contains('#!/usr/bin/env bash'));
      expect(script, contains('set -euo pipefail'));
    });

    test('targets the included flutter_tools gradle settings file', () {
      expect(script, contains('flutter_tools/gradle/settings.gradle.kts'));
    });

    test('inserts the Aliyun mirror that serves kotlin-build-tools-impl',
        () {
      expect(script, contains('maven.aliyun.com'));
    });

    test('patches pluginManagement too — the plugin classpath resolves '
        'independent of dependencyResolutionManagement', () {
      // Regression: the v1.6.1 build (gradle cache wiped) died resolving
      // kotlin-stdlib:2.2.21 for the flutter-plugin-loader's classpath —
      // plugin resolution reads the settings' pluginManagement repositories,
      // which upstream flutter does not declare at all, so gradle falls
      // back to mavenCentral and 429s. Aliyun must cover BOTH blocks.
      expect(script, contains('pluginManagement'));
    });

    test('is idempotent — never double-patches on a rebuild', () {
      // A grep guard must run before any edit; otherwise a second toolchain
      // pass adds a second mirror block and gradle resolves duplicates.
      expect(script, contains('grep'));
    });

    test('honors FLUTTER_ROOT over a hard-coded SDK path', () {
      expect(script, contains('FLUTTER_ROOT'));
    });

    test('the repair is documented in BUILD-ENV for the next rebuild', () {
      final env = readRepo('docs/BUILD-ENV.md');
      expect(env, contains('patch_flutter_tools_repos.sh'));
    });
  });

  group('release lint stays off on the 4 GB build box', () {
    test('checkReleaseBuilds is disabled — lint-vital OOMs in metaspace', () {
      // Regression: the v1.6.0 build compiled every source and then died in
      // :image_picker_android:lintVitalAnalyzeRelease with
      // OutOfMemoryError: Metaspace — lint-vital loads the whole plugin
      // UAST world into the capped 1 GB gradle JVM (see gradle.properties:
      // -Xmx1024m is a build-box necessity). The app's quality gates are
      // the flutter test suite and the release size gate, not lint.
      final gradle = readRepo('android/app/build.gradle.kts');
      expect(gradle, contains('checkReleaseBuilds = false'));
    });
  });

  group('toolchain rebuild receipts are on paper', () {
    // 2026-11-14: the sandbox was recycled and the toolchain rebuilt from
    // zero. Three repairs were rediscovered the hard way — each one cost a
    // failed release build. They must be documented, because "files too
    // large are not put back": the next rebuild starts from nothing.
    final env = readRepo('docs/BUILD-ENV.md');

    test('the JDK repair is documented — the sandbox ships JRE-only Java', () {
      // Without javac gradle dies with "does not provide the required
      // capabilities: [JAVA_COMPILER]" after five minutes of work.
      expect(env, contains('jdk21-root'));
      expect(env, contains('javac'));
    });

    test('the llvm-19 deb extraction is documented', () {
      // GNU binutils on this box cannot strip the arm64 engine; the strip
      // shims run over a locally extracted llvm-19 (no root apt available).
      expect(env, contains('llvm19-root'));
    });

    test('the NDK stub recipe is documented — AGP must never auto-download', () {
      // A missing NDK revision dir makes gradle try to fetch a full NDK
      // (multi-GB) or fail; the stub satisfies the version check and hosts
      // the strip shims.
      expect(env, contains('28.2.13676358'));
      expect(env, contains('source.properties'));
    });
  });
}
