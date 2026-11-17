import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'cli_support.dart';
import 'browser_agent.dart';

/// The daemon lifecycle, natively in Dart — the ONE `gork` command owns it:
///
///   gork daemon start | stop | restart | status | logs | health
///
/// Same contract as the old gork-daemonctl bash script: the pidfile lives at
/// $GORK_HOME/gork-daemon.pid, the log at $GORK_HOME/gork-daemon.log, and
/// `start` only reports success after /health answers. `start --quiet`
/// prints nothing — that is what the boot hooks call.
class DaemonControl {
  DaemonControl({Map<String, String>? env, http.Client? client})
      : _env = env ?? Platform.environment,
        _http = client ?? http.Client();

  final Map<String, String> _env;
  final http.Client _http;

  String get home => _env['HOME'] ?? '/';
  String get stateDir {
    final gorkHome = _env['GORK_HOME'] ?? '';
    return gorkHome.isNotEmpty ? gorkHome : '$home/.gork-daemon';
  }

  String get pidfile => '$stateDir/gork-daemon.pid';
  String get logfile => '$stateDir/gork-daemon.log';
  int get port => int.tryParse(_env['GORK_PORT'] ?? '') ??
      int.tryParse(config().get('GORK_PORT') ?? '') ??
      8787;
  Uri get healthUrl => Uri.parse('http://127.0.0.1:$port/health');
  int get healthTimeoutSec =>
      int.tryParse(_env['GORK_HEALTH_TIMEOUT'] ?? '') ?? 20;

  ConfigStore config() => ConfigStore(configPath(env: _env));

  /// PID of a live daemon, or null.
  int? runningPid() {
    final file = File(pidfile);
    if (!file.existsSync()) return null;
    final pid = int.tryParse(file.readAsStringSync().trim());
    if (pid == null) return null;
    try {
      final result = Process.runSync('kill', <String>['-0', '$pid']);
      return result.exitCode == 0 ? pid : null;
    } catch (_) {
      return null;
    }
  }

  /// True when /health answers (liveness is the only truth).
  Future<bool> isHealthy() async {
    try {
      final response = await _http
          .get(healthUrl)
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Launches the daemon detached (survives this process), logs to the
  /// logfile, waits for /health. Idempotent: an already-healthy daemon is a
  /// fast no-op. `quiet` prints nothing (boot hooks).
  Future<bool> start({bool quiet = false, void Function(String) out = print}) async {
    if (await isHealthy()) {
      if (!quiet) out('daemon already running (pid ${runningPid() ?? '?'})');
      return true;
    }
    final src = _sourceDir();
    if (src == null) {
      if (!quiet) {
        out('error: daemon source not found — re-run the gork installer');
      }
      return false;
    }
    final env = _childEnv();
    Directory(stateDir).createSync(recursive: true);
    final shell = Process.runSync('which', <String>['dart']);
    final dartBin = shell.exitCode == 0
        ? (shell.stdout as String).trim()
        : 'dart';
    // exec + redirect: the shell process IS the daemon (same pid), logs land
    // in the logfile, and detached mode means we can exit right after.
    final process = await Process.start(
      '/bin/sh',
      <String>[
        '-c',
        'exec "$dartBin" run bin/gork_daemon.dart >> "$logfile" 2>&1'
      ],
      environment: env,
      workingDirectory: src,
      mode: ProcessStartMode.detached,
    );
    File(pidfile).writeAsStringSync('${process.pid}');
    final deadline = DateTime.now().add(Duration(seconds: healthTimeoutSec));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (await isHealthy()) {
        if (!quiet) {
          out('daemon started (pid ${process.pid}) — $healthUrl');
        }
        return true;
      }
    }
    if (!quiet) {
      out('daemon did NOT answer /health in ${healthTimeoutSec}s '
          '— logs: gork daemon logs');
    }
    return false;
  }

  /// Stops the daemon AND the agent browser (its profile lives under the
  /// state dir, so the pattern is precise).
  Future<bool> stop({void Function(String) out = print}) async {
    var stopped = false;
    final pid = runningPid();
    if (pid != null) {
      Process.runSync('kill', <String>['$pid']);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (runningPid() == null) break;
      }
      final stillAlive = runningPid();
      if (stillAlive != null) {
        Process.runSync('kill', <String>['-9', '$stillAlive']);
      }
      stopped = true;
      out('daemon stopped (pid $pid)');
    } else {
      out('daemon not running');
    }
    final browser = Process.runSync(
        'pkill', <String>['-f', 'user-data-dir=$stateDir/browser-profile']);
    if (browser.exitCode == 0) out('agent browser stopped');
    if (File(pidfile).existsSync()) File(pidfile).deleteSync();
    return stopped;
  }

  Future<bool> restart({bool quiet = false, void Function(String) out = print}) async {
    await stop(out: quiet ? (_) {} : out);
    return start(quiet: quiet, out: out);
  }

  Future<String> statusLine() async {
    final pid = runningPid();
    final healthy = await isHealthy();
    final state = healthy
        ? 'up'
        : pid != null
            ? 'starting/degraded (pid $pid, /health not answering)'
            : 'down';
    return 'daemon: $state | state dir: $stateDir | port: $port';
  }

  String logs([int lines = 40]) {
    final file = File(logfile);
    if (!file.existsSync()) return '(no log yet at $logfile)';
    final all = file.readAsLinesSync();
    return all.length <= lines
        ? all.join('\n')
        : all.sublist(all.length - lines).join('\n');
  }

  Map<String, String> _childEnv() {
    final env = <String, String>{..._env, 'GORK_HOME': stateDir};
    // config.env wins over the caller's shell (it is the daemon's config).
    for (final entry in config().read().entries) {
      env[entry.key] = entry.value;
    }
    env['GORK_HOME'] = stateDir; // never overridden by config
    return env;
  }

  String? _sourceDir() {
    final fromConfig = config().read()['GORK_SRC_DIR'];
    final candidates = [
      _env['GORK_SRC_DIR'] ?? '',
      fromConfig ?? '',
    ].where((c) => c.isNotEmpty).toList();
    for (final dir in [
      ...candidates,
      '$home/.gork/daemon', // Termux default install root
      '/opt/gork/daemon',
      // A daemon/ directory above the CURRENT directory (dev checkouts).
      Directory.current.path.endsWith('/daemon')
          ? Directory.current.path
          : '${Directory.current.path}/daemon',
    ]) {
      if (dir.isEmpty) continue;
      final d = Directory('$dir/bin/gork_daemon.dart');
      if (d.existsSync()) return dir;
    }
    return null;
  }
}

/// Shared with the CLI: the browser-facing vault ops (value from stdin,
/// never argv — shell history must never see a secret).
Future<int> vaultSet(String stateDir, String label, String value,
    void Function(String) out) async {
  try {
    await writeVaultSecret(stateDir, label, value);
    out('vault: stored "$label" (${value.length} chars) — the browser can '
        'fill it with action fill_secret. It is never echoed back.');
    return 0;
  } catch (e) {
    out('error: $e');
    return 1;
  }
}

int vaultList(String stateDir, void Function(String) out) {
  final labels = readVault(stateDir).keys.toList();
  if (labels.isEmpty) {
    out('(vault empty — add: gork vault set <label>  then type the value)');
    return 0;
  }
  out('labels: ${labels.join(", ")}   (values never shown)');
  return 0;
}

int vaultRemove(String stateDir, String label, void Function(String) out) {
  try {
    final removed = deleteVaultSecretSync(stateDir, label);
    out(removed ? 'vault: removed "$label"' : 'vault: no such label "$label"');
    return removed ? 0 : 1;
  } catch (e) {
    out('error: $e');
    return 1;
  }
}
