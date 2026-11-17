import 'dart:io';

import 'package:test/test.dart';

import 'package:gork_daemon/autostart.dart';

void main() {
  late Directory home;
  late Directory prefix;
  late Map<String, String> env;

  setUp(() {
    home = Directory.systemTemp.createTempSync('gork-autostart-home');
    prefix = Directory.systemTemp.createTempSync('gork-autostart-prefix');
    Directory('${prefix.path}/bin').createSync();
    env = {'HOME': home.path, 'PREFIX': prefix.path};
  });

  tearDown(() {
    home.deleteSync(recursive: true);
    prefix.deleteSync(recursive: true);
  });

  Autostart makeAutostart() => Autostart(env: env, probe: '/x/bin/gork');

  group('boot-time auto-start (Movement 58)', () {
    test('Termux:Boot script installed — dir created even without the app',
        () {
      final report = makeAutostart().apply();
      final boot = File('${home.path}/.termux/boot/gork-daemon.sh');
      expect(boot.existsSync(), isTrue,
          reason: 'installing Termux:Boot later must find our script');
      final content = boot.readAsStringSync();
      expect(content, contains('gork daemon start --quiet'));
      expect(content, contains('termux-wake-lock'),
          reason: 'Termux kills backgrounded daemons without a wake lock');
      expect(report.join('\n'), contains('boot script'));
    });

    test('boot script works without a Termux prefix (plain distro)', () {
      env = {'HOME': home.path}; // no PREFIX
      final boot = File('${home.path}/.termux/boot/gork-daemon.sh');
      makeAutostart().apply();
      expect(boot.existsSync(), isTrue);
      expect(boot.readAsStringSync(), isNot(contains('termux-wake-lock')));
      expect(boot.readAsStringSync(), startsWith('#!/bin/sh'));
    });

    test('profile hooks land in .bashrc and .profile', () {
      final report = makeAutostart().apply();
      for (final rc in ['${home.path}/.bashrc', '${home.path}/.profile']) {
        final content = File(rc).readAsStringSync();
        expect(content, contains('# >>> gork autostart >>>'));
        expect(content, contains('gork daemon start --quiet'));
      }
      expect(report.join('\n'), contains('profile hook'));
    });

    test('profile hooks are IDEMPOTENT — re-runs never duplicate', () {
      final auto = makeAutostart();
      auto.apply();
      final before = File('${home.path}/.bashrc').readAsStringSync();
      final report = auto.apply();
      final after = File('${home.path}/.bashrc').readAsStringSync();
      expect(after, before,
          reason: 'the sentinel comment guards against double installs');
      expect(report.join('\n'), contains('already present'));
    });

    test('existing profile content is preserved', () {
      File('${home.path}/.bashrc').writeAsStringSync('export EDITOR=vim\n');
      makeAutostart().apply();
      final content = File('${home.path}/.bashrc').readAsStringSync();
      expect(content, contains('export EDITOR=vim'));
      expect(content, contains('gork daemon start'));
    });

    test('the hook line is backgrounded and silenced (shells open fast)',
        () {
      final hook = makeAutostart().profileHook();
      expect(hook, contains('--quiet'));
      expect(hook, contains('>/dev/null 2>&1'));
    });

    test('apply() honors an injected writer (testability)', () {
      final written = <String, String>{};
      final report = makeAutostart().apply(writeFile: (path, content) {
        written[path] = content;
        return true;
      });
      expect(written.keys,
          contains('${home.path}/.termux/boot/gork-daemon.sh'));
      expect(report.join('\n'), contains('profile.d hook: skipped'));
    });

    test('content matches between boot script and hook generations', () {
      final auto = makeAutostart();
      // Both surfaces must call the SAME entry point — one command, one
      // behavior, whichever layer fires first.
      expect(auto.bootScript(), contains('gork daemon start --quiet'));
      expect(auto.profileHook(), contains('gork daemon start --quiet'));
    });
  });
}
