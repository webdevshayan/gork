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
}
