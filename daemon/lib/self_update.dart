import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'autostart.dart';
import 'daemon_control.dart';

/// `gork daemon update` — brings an existing install fully up to date in
/// one command, WITHOUT touching anything the user configured:
///
///   source    git fetch + hard reset to origin's default branch (gork/ is
///             a managed install dir created by the installer — nothing in
///             it is hand-edited, so a hard reset cannot lose work)
///   deps      dart pub get in the daemon dir
///   wrapper   every `gork` launcher found in PATH (plus the deprecated
///             gork-daemonctl shim) is rewritten to point at the current
///             source — old wrappers that predate GORK_SRC_DIR heal here
///   hooks     boot auto-start hooks re-applied (idempotent)
///   daemon    restarted through whichever backend runs it (systemd unit,
///             termux-services, or the CLI's own lifecycle), then /health
///             MUST answer — otherwise the update reports failure
///
/// config.env, tasks.json, vault.json and the browser profile all live in
/// the state dir ($GORK_HOME), OUTSIDE the source tree — an update can
/// never lose API keys, tasks or sealed secrets, and never asks the user
/// to re-enter them.
class SelfUpdate {
  SelfUpdate({
    DaemonControl? control,
    http.Client? client,
    Autostart? autostart,
    void Function(String) out = print,
    Future<bool> Function({required bool wasRunning})? restartDaemon,
    Future<String?> Function()? runningVersion,
    List<String>? pathDirs,
  })  : _control = control,
        _client = client ?? http.Client(),
        _autostart = autostart,
        _out = out,
        _restartDaemon = restartDaemon,
        _runningVersion = runningVersion,
        _pathDirs = pathDirs;

  final DaemonControl? _control;
  final http.Client _client;
  final Autostart? _autostart;
  final void Function(String) _out;
  final Future<bool> Function({required bool wasRunning})? _restartDaemon;
  final Future<String?> Function()? _runningVersion;
  final List<String>? _pathDirs;

  /// Returns true when the daemon is (back) up and /health answered.
  Future<bool> run() async {
    final ctl = _control ?? DaemonControl();
    final (src, probed) = ctl.findSourceDir();
    if (src == null) {
      _out('error: daemon source not found (probed: ${probed.join(", ")}) '
          '— re-run the gork installer (it re-clones)');
      return false;
    }
    // src is <root>/daemon — the repo root is one level above it.
    final root = Directory(src).parent.path;
    final before = await _version();

    _out('source : syncing $root to origin ...');
    if (!_syncSource(root)) return false;

    _out('deps   : dart pub get ...');
    if (!_pubGet(src)) return false;

    _out('hooks  : boot auto-start re-applied (idempotent)');
    try {
      for (final line in (_autostart ?? Autostart()).apply()) {
        _out('   $line');
      }
    } catch (e) {
      _out('   autostart hooks skipped: $e');
    }
    for (final wrapper in _refreshWrappers(src)) {
      _out('wrapper: $wrapper');
    }

    final restarted =
        await (_restartDaemon ?? _defaultRestart)(wasRunning: before != null);
    if (!restarted) {
      _out('update finished but the daemon is NOT answering /health —');
      _out('check: gork daemon logs   (config.env, tasks and vault were '
          'NOT touched, so fixing and restarting is safe)');
      return false;
    }
    final after = await _version();
    _out('daemon updated: ${before ?? 'unknown'} -> ${after ?? 'unknown'} '
        '— /health ok');
    _out('kept   : config.env (LLM key, secret), tasks, vault, browser '
        'profile — nothing was reset, no key re-entry needed');
    return true;
  }

  // -- source ------------------------------------------------------------------
  bool _syncSource(String root) {
    var branch = 'main';
    try {
      final ls = Process.runSync(
          'git', <String>['-C', root, 'ls-remote', '--symref', 'origin', 'HEAD']);
      if (ls.exitCode == 0) {
        final m = RegExp(r'ref: refs/heads/(\S+)\tHEAD')
            .firstMatch(ls.stdout as String);
        final name = m?.group(1);
        if (name != null && name.isNotEmpty) branch = name;
      }
    } catch (_) {
      // no git or no network to resolve the default branch — try main.
    }
    bool git(List<String> args) {
      try {
        final r = Process.runSync('git', <String>['-C', root, ...args]);
        return r.exitCode == 0;
      } catch (_) {
        return false;
      }
    }

    if (!git(<String>['fetch', '--depth', '1', 'origin', branch]) ||
        !git(<String>['reset', '--hard', 'FETCH_HEAD'])) {
      _out('error: could not sync $root to origin/$branch — '
          're-run the gork installer (it falls back to a fresh re-clone)');
      return false;
    }
    git(<String>['clean', '-xfd']);
    final entry = '$root/daemon/bin/gork_daemon.dart';
    if (!File(entry).existsSync()) {
      _out('error: $entry is missing even after the sync — '
          're-run the gork installer (it falls back to a fresh re-clone)');
      return false;
    }
    return true;
  }

  bool _pubGet(String src) {
    try {
      final r = Process.runSync('dart', <String>['pub', 'get'],
          workingDirectory: src);
      if (r.exitCode == 0) return true;
      _out('error: dart pub get failed:\n'
          '${(r.stdout as String).trim()}\n${(r.stderr as String).trim()}');
      return false;
    } catch (e) {
      _out('error: dart is not runnable — install the Dart SDK first ($e)');
      return false;
    }
  }

  // -- wrappers ----------------------------------------------------------------
  /// Rewrites every `gork` launcher found in PATH (and the deprecated
  /// gork-daemonctl shim beside it) to point at the current source. Only
  /// files that reference gork_cli.dart are touched — a same-named script
  /// that is not ours is left alone.
  List<String> _refreshWrappers(String src) {
    final dirs = _pathDirs ?? _pathFromEnv();
    final ctl = _control ?? DaemonControl();
    final home = ctl.stateDir;
    final rewritten = <String>[];
    final body = '''
#!/usr/bin/env bash
# gork CLI wrapper (refreshed by: gork daemon update)
export GORK_HOME="$home"
export GORK_SRC_DIR="$src"
exec dart run "$src/bin/gork_cli.dart" "\$@"
''';
    for (final dir in dirs) {
      final gork = File('$dir/gork');
      if (!gork.existsSync()) continue;
      String content;
      try {
        content = gork.readAsStringSync();
      } catch (_) {
        continue;
      }
      if (!content.contains('gork_cli.dart')) continue;
      try {
        gork.writeAsStringSync(body);
        Process.runSync('chmod', <String>['0755', gork.path]);
        rewritten.add(gork.path);
      } catch (_) {
        _out('   could not rewrite ${gork.path} (read-only?) — skipped');
        continue;
      }
      final shim = File('$dir/gork-daemonctl');
      if (shim.existsSync()) {
        try {
          shim.writeAsStringSync(
              '#!/usr/bin/env bash\n'
              '# deprecated shim — use: gork daemon <cmd>\n'
              'exec "${gork.path}" daemon "\$@"\n');
          Process.runSync('chmod', <String>['0755', shim.path]);
          rewritten.add(shim.path);
        } catch (_) {
          // shim is optional; a failure to rewrite it is not fatal
        }
      }
    }
    if (rewritten.isEmpty) {
      _out('   no gork launcher found in PATH (dev checkout — fine)');
    }
    return rewritten;
  }

  List<String> _pathFromEnv() =>
      (Platform.environment['PATH'] ?? '').split(':').where((d) {
        return d.isNotEmpty && d != '.';
      }).toList();

  // -- restart -----------------------------------------------------------------
  Future<bool> _defaultRestart({required bool wasRunning}) async {
    final ctl = _control ?? DaemonControl();
    // 1. systemd owns the lifecycle where the unit is installed (works even
    //    when the unit is currently stopped — restart == start for systemd).
    if (_systemdUnitInstalled()) {
      final isRoot = _idIsRoot();
      final r = Process.runSync(isRoot ? 'systemctl' : 'sudo',
          <String>[if (!isRoot) '-n', 'restart', 'gork-daemon']);
      if (r.exitCode != 0) {
        _out('systemctl restart failed: '
            '${((r.stderr as String?) ?? '').trim()}');
        _out('run it by hand: sudo systemctl restart gork-daemon');
        return false;
      }
      return _waitHealthy(ctl);
    }
    // 2. termux-services
    final prefix = Platform.environment['PREFIX'] ?? '';
    if (prefix.isNotEmpty &&
        Directory('$prefix/var/service/gork-daemon').existsSync()) {
      final r = Process.runSync('sv', <String>['restart', 'gork-daemon']);
      if (r.exitCode != 0) {
        _out('sv restart failed: ${((r.stderr as String?) ?? '').trim()}');
        return false;
      }
      return _waitHealthy(ctl);
    }
    // 3. No init system: the CLI's own lifecycle (stop + start, then the
    //    start gate waits for /health itself).
    return ctl.restart();
  }

  bool _systemdUnitInstalled() {
    try {
      return Process.runSync('systemctl', <String>['cat', 'gork-daemon'])
              .exitCode ==
          0;
    } catch (_) {
      return false;
    }
  }

  bool _idIsRoot() {
    try {
      return (Process.runSync('id', <String>['-u']).stdout as String).trim() ==
          '0';
    } catch (_) {
      return false;
    }
  }

  Future<bool> _waitHealthy(DaemonControl ctl, [int seconds = 30]) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(deadline)) {
      if (await ctl.isHealthy()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  // -- version -----------------------------------------------------------------
  Future<String?> _version() async {
    final override = _runningVersion;
    if (override != null) return override();
    final ctl = _control ?? DaemonControl();
    try {
      final res =
          await _client.get(ctl.healthUrl).timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final v = data is Map ? data['version'] : null;
      return v is String && v.isNotEmpty ? v : null;
    } catch (_) {
      // Old daemons (pre-0.2.0) do not report a version — that is fine, the
      // update still runs; the final line shows the version that came up.
      return null;
    }
  }
}
