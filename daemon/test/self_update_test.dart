import 'dart:io';

import 'package:test/test.dart';

import 'package:gork_daemon/autostart.dart';
import 'package:gork_daemon/daemon_control.dart';
import 'package:gork_daemon/self_update.dart';

/// `gork daemon update` against REAL git repositories in a temp dir:
///
///   origin.git      a bare "upstream"
///   work/           a clone that pushes NEW commits (the upgrade)
///   install-root/   the managed install clone the updater must sync
///
/// The test proves the full upgrade contract: new source lands, `dart pub
/// get` runs, the launcher wrapper is rewritten (old wrappers without
/// GORK_SRC_DIR heal), restart happens through the injected hook, /health
/// is consulted before AND after — and the user state (config.env,
/// tasks.json) survives byte-for-byte.
void main() {
  late Directory tmp;
  late String originRepo;
  late String workRepo;
  late String installRoot;
  late String stateDir;
  late String bindir;
  late String configBefore;
  late String tasksBefore;

  void sh(String exec, List<String> args, {String? cwd}) {
    final r = Process.runSync(exec, args,
        workingDirectory: cwd,
        environment: {
          ...Platform.environment,
          'GIT_AUTHOR_NAME': 'gork test',
          'GIT_AUTHOR_EMAIL': 'test@gork',
          'GIT_COMMITTER_NAME': 'gork test',
          'GIT_COMMITTER_EMAIL': 'test@gork',
        });
    if (r.exitCode != 0) {
      fail('${exec} ${args.join(" ")} failed: '
          '${r.stdout}${r.stderr}');
    }
  }

  void git(List<String> args, {String? cwd}) => sh('git', args, cwd: cwd);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gork-selfupdate-test');
    originRepo = '${tmp.path}/origin.git';
    workRepo = '${tmp.path}/work';
    installRoot = '${tmp.path}/install-root';
    stateDir = '${tmp.path}/state';
    bindir = '${tmp.path}/bin';
    Directory(bindir).createSync();
    Directory(stateDir).createSync();

    // v1 upstream + install clone at v1.
    git(['init', '--bare', '--initial-branch=main', originRepo]);
    git(['clone', originRepo, workRepo]);
    Directory('${workRepo}/daemon/bin').createSync(recursive: true);
    File('${workRepo}/daemon/pubspec.yaml').writeAsStringSync(
        'name: gork_daemon\nenvironment:\n  sdk: ^3.0.0\n');
    File('${workRepo}/daemon/bin/gork_daemon.dart')
        .writeAsStringSync('// v1 entrypoint\n');
    File('${workRepo}/daemon/VERSION').writeAsStringSync('v1\n');
    git(['add', '-A'], cwd: workRepo);
    git(['commit', '-m', 'v1'], cwd: workRepo);
    git(['push', 'origin', 'main'], cwd: workRepo);
    git(['clone', '--depth', '1', originRepo, installRoot]);

    // The launcher wrapper AS AN OLD INSTALLER wrote it: no GORK_SRC_DIR,
    // and pointing at the source through the same variable it had then.
    File('$bindir/gork').writeAsStringSync('''
#!/usr/bin/env bash
# gork CLI wrapper (ctl install)
export GORK_HOME="$stateDir"
exec dart run "$installRoot/daemon/bin/gork_cli.dart" "\$@"
''');

    // User state an update must NEVER touch.
    configBefore = 'GORK_PORT="8787"\nGORK_SECRET="hunter2"\n'
        'GORK_API_KEY="sk-do-not-lose"\n';
    File('$stateDir/config.env').writeAsStringSync(configBefore);
    tasksBefore = '[{"id":"t1","title":"keep me"}]\n';
    File('$stateDir/tasks.json').writeAsStringSync(tasksBefore);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  DaemonControl control() => DaemonControl(env: {
        'HOME': tmp.path,
        'GORK_HOME': stateDir,
        'GORK_SRC_DIR': '$installRoot/daemon',
      });

  /// Never touch real boot hooks in tests — apply() is SelfUpdate's to
  /// call, and its RESULT lines are all the update needs to print.
  Autostart noHooks() => _StubAutostart();

  test('update syncs source, deps, wrapper, hooks and restarts healthy',
      () async {
    // The upgrade lands upstream AFTER the install clone exists.
    Directory('${workRepo}/daemon/lib').createSync();
    File('${workRepo}/daemon/lib/new_feature.dart')
        .writeAsStringSync('// brand new in v2\n');
    File('${workRepo}/daemon/VERSION').writeAsStringSync('v2\n');
    git(['add', '-A'], cwd: workRepo);
    git(['commit', '-m', 'v2'], cwd: workRepo);
    git(['push', 'origin', 'main'], cwd: workRepo);

    final out = <String>[];
    var restarts = 0;
    bool? wasRunningSeen;
    final versions = ['0.1.0', '0.2.0']; // before -> after
    final updater = SelfUpdate(
      control: control(),
      autostart: noHooks(),
      out: out.add,
      pathDirs: [bindir],
      runningVersion: () async => versions.removeAt(0),
      restartDaemon: ({required bool wasRunning}) async {
        restarts++;
        wasRunningSeen = wasRunning;
        return true;
      },
    );

    expect(await updater.run(), isTrue, reason: out.join('\n'));
    expect(restarts, 1);
    expect(wasRunningSeen, isTrue,
        reason: 'the daemon answered /health before the update');

    // New source really landed in the MANAGED clone.
    expect(
        File('$installRoot/daemon/lib/new_feature.dart').existsSync(), isTrue);
    expect(File('$installRoot/daemon/VERSION').readAsStringSync(), 'v2\n');
    // dart pub get really ran (a package_config exists in the fake daemon).
    expect(
        File('$installRoot/daemon/.dart_tool/package_config.json').existsSync(),
        isTrue);

    // The wrapper was rewritten to the SAME source, now WITH GORK_SRC_DIR —
    // old installs heal without the user noticing.
    final wrapper = File('$bindir/gork').readAsStringSync();
    expect(wrapper, contains('export GORK_SRC_DIR="$installRoot/daemon"'));
    expect(wrapper, contains('gork_cli.dart'));

    // Nothing the user configured was touched.
    expect(File('$stateDir/config.env').readAsStringSync(), configBefore);
    expect(File('$stateDir/tasks.json').readAsStringSync(), tasksBefore);

    final printed = out.join('\n');
    expect(printed, contains('0.1.0 -> 0.2.0'));
    expect(printed, contains('kept'));
  });

  test('re-running an up-to-date install is a safe no-op that still '
      'restarts', () async {
    final out = <String>[];
    var restarts = 0;
    final updater = SelfUpdate(
      control: control(),
      autostart: noHooks(),
      out: out.add,
      pathDirs: [bindir],
      runningVersion: () async => '0.2.0',
      restartDaemon: ({required bool wasRunning}) async {
        restarts++;
        return true;
      },
    );
    expect(await updater.run(), isTrue, reason: out.join('\n'));
    expect(restarts, 1);
    expect(out.join('\n'), contains('0.2.0 -> 0.2.0'));
    expect(File('$bindir/gork').readAsStringSync(), contains('GORK_SRC_DIR'));
  });

  test('a broken source tree (no git) fails loudly and touches nothing',
      () async {
    // A valid-looking daemon dir that is NOT a git checkout — the sync must
    // refuse instead of half-updating.
    final orphan = '${tmp.path}/orphan-daemon';
    Directory('$orphan/bin').createSync(recursive: true);
    File('$orphan/bin/gork_daemon.dart').writeAsStringSync('// stale\n');
    final ctl = DaemonControl(env: {
      'HOME': tmp.path,
      'GORK_HOME': stateDir,
      'GORK_SRC_DIR': orphan,
    });
    final out = <String>[];
    var restarts = 0;
    final updater = SelfUpdate(
      control: ctl,
      autostart: noHooks(),
      out: out.add,
      pathDirs: [bindir],
      restartDaemon: ({required bool wasRunning}) async {
        restarts++;
        return true;
      },
    );
    expect(await updater.run(), isFalse);
    expect(restarts, 0, reason: 'a failed sync must never restart');
    expect(out.join('\n'), contains('could not sync'));
    expect(out.join('\n'), contains('re-run the gork installer'));
  });
}

class _StubAutostart extends Autostart {
  _StubAutostart()
      : super(env: {'HOME': '/nonexistent-gork-selfupdate-test'});

  @override
  List<String> apply({bool Function(String path, String content)? writeFile}) =>
      ['boot script: (stub — tests never touch real hooks)'];
}
