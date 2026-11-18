import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'autostart.dart';
import 'daemon_control.dart';
import 'self_update.dart';

/// gork CLI plumbing — configuration without ever opening a file, plus an
/// HTTP client for the running daemon. Everything here is pure enough to
/// test: no stdout writes, no exit() calls (runCli owns those).
class ConfigStore {
  ConfigStore(this.path);

  final String path;

  Map<String, String> read() {
    final file = File(path);
    if (!file.existsSync()) return {};
    final values = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final key = trimmed.substring(0, eq).trim();
      var value = trimmed.substring(eq + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      values[key] = value;
    }
    return values;
  }

  /// Upserts `KEY="value"` — comments and other lines are preserved, no
  /// duplicate keys, no manual file editing.
  Future<void> set(String key, String value) async {
    final file = File(path);
    final lines = file.existsSync()
        ? file.readAsLinesSync()
        : <String>[
            '# gork daemon configuration — manage it with: gork config set ...'
          ];
    final quoted = '$key="${_escape(value)}"';
    var replaced = false;
    final next = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      final eq = trimmed.indexOf('=');
      final existingKey = (eq > 0 && !trimmed.startsWith('#'))
          ? trimmed.substring(0, eq).trim()
          : null;
      if (existingKey == key) {
        if (!replaced) {
          next.add(quoted);
          replaced = true;
        }
        continue;
      }
      next.add(line);
    }
    if (!replaced) next.add(quoted);
    await File(path).create(recursive: true);
    await File(path).writeAsString('${next.join('\n')}\n');
    try {
      await Process.run('chmod', <String>['600', path]);
    } catch (_) {}
  }

  String? get(String key) => read()[key];

  Map<String, String> list() => read();

  Future<void> ensureSecret() async {
    if (get('GORK_SECRET')?.isNotEmpty ?? false) return;
    await set('GORK_SECRET', _randomSecret());
  }

  String _randomSecret() {
    final rnd = Random.secure();
    return List.generate(24, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String _escape(String value) => value.replaceAll('"', r'\"');
}

/// Where the daemon's config.env lives, honouring GORK_HOME.
String configPath({Map<String, String>? env}) {
  final e = env ?? Platform.environment;
  final home = e['GORK_HOME'] ?? '';
  if (home.isNotEmpty) {
    return home.endsWith('/') ? '${home}config.env' : '$home/config.env';
  }
  final userHome = e['HOME'] ?? '.';
  return '$userHome/.gork-daemon/config.env';
}

/// Where the daemon's mutable state lives (vault.json, the agent-browser
/// profile) — GORK_HOME, else ~/.gork-daemon. Same derivation as
/// DaemonControl.stateDir; lives here so the HTTP server can wire the vault
/// route without dragging the whole controller in.
String stateDirPath({Map<String, String>? env}) {
  final e = env ?? Platform.environment;
  final home = e['GORK_HOME'] ?? '';
  if (home.isNotEmpty) return home;
  return '${e['HOME'] ?? '.'}/.gork-daemon';
}

class LlmPreset {
  const LlmPreset(this.id, this.label, this.baseUrl, this.model);

  final String id;
  final String label;
  final String baseUrl;
  final String model;
}

/// Real, OpenAI-compatible endpoints. The key stays in the local config.
const List<LlmPreset> kLlmPresets = [
  LlmPreset('openai', 'OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini'),
  LlmPreset('openrouter', 'OpenRouter', 'https://openrouter.ai/api/v1',
      'openrouter/auto'),
  LlmPreset(
      'gemini',
      'Google Gemini (OpenAI shim)',
      'https://generativelanguage.googleapis.com/v1beta/openai',
      'gemini-2.0-flash'),
  LlmPreset('groq', 'Groq', 'https://api.groq.com/openai/v1',
      'llama-3.3-70b-versatile'),
  LlmPreset('ollama', 'Ollama (local)', 'http://127.0.0.1:11434/v1',
      'llama3.2'),
];

LlmPreset? llmPreset(String id) {
  for (final preset in kLlmPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// Thrown on any non-2xx daemon response — the CLI surfaces it, never hides it.
class DaemonApiError implements Exception {
  DaemonApiError(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'daemon returned $statusCode: $body';
}

class DaemonClient {
  DaemonClient({
    required this.baseUrl,
    this.secret = '',
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String baseUrl;
  final String secret;
  final http.Client _http;

  Map<String, String> get _headers => {
        if (secret.isNotEmpty) 'x-gork-secret': secret,
        'content-type': 'application/json',
      };

  Future<Map<String, dynamic>> health() async {
    final response = await _http.get(
      Uri.parse('$baseUrl/health'),
      headers: _headers,
    );
    return _ok(response);
  }

  Future<List<Map<String, dynamic>>> tasksList() async {
    final response = await _http.get(
      Uri.parse('$baseUrl/tasks'),
      headers: _headers,
    );
    final body = await _ok(response);
    return [
      for (final t in (body['tasks'] as List? ?? []))
        (t as Map).cast<String, dynamic>()
    ];
  }

  Future<Map<String, dynamic>> tasksAdd({
    required String title,
    required String prompt,
    int repeatMinutes = 60,
  }) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/tasks'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'prompt': prompt,
        'repeatMinutes': repeatMinutes,
      }),
    );
    return _ok(response);
  }

  Future<Map<String, dynamic>> tasksRemove(String id) async {
    final response = await _http.delete(
      Uri.parse('$baseUrl/tasks/$id'),
      headers: _headers,
    );
    return _ok(response);
  }

  Future<Map<String, dynamic>> tasksRun() async {
    final response = await _http.post(
      Uri.parse('$baseUrl/run'),
      headers: _headers,
    );
    return _ok(response);
  }

  Future<Map<String, dynamic>> browserStatus() async {
    final response = await _http.get(
      Uri.parse('$baseUrl/v1/browser/status'),
      headers: _headers,
    );
    return _ok(response);
  }

  /// One agent-browser op (navigate / click / type / read / ...).
  Future<Map<String, dynamic>> browserOp(
    String action, {
    String session = 'default',
    Map<String, dynamic> args = const {},
  }) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/v1/browser/op'),
      headers: _headers,
      body: jsonEncode({'session': session, 'action': action, ...args}),
    );
    return _ok(response);
  }

  /// One human line: daemon state + task count.
  Future<String> statusLine() async {
    final state = await health();
    var tasks = <Map<String, dynamic>>[];
    try {
      tasks = await tasksList();
    } on DaemonApiError {
      // Gated but healthy daemon — still report liveness.
    }
    final status = state['status'];
    final time = state['time'];
    return 'daemon: $status | tasks: ${tasks.length} | ${time ?? ''}';
  }

  Future<Map<String, dynamic>> _ok(http.Response response) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DaemonApiError(response.statusCode, response.body);
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      return {};
    }
  }
}

/// Tests a live LLM call with the configured key — proves the credentials
/// and endpoint work without leaving the terminal.
Future<String> llmTest(ConfigStore config, {http.Client? client}) async {
  final values = config.read();
  final apiKey = values['GORK_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    throw StateError('no GORK_API_KEY configured — run: gork config set GORK_API_KEY sk-...');
  }
  final baseUrl = values['GORK_BASE_URL'] ?? 'https://api.openai.com/v1';
  final model = values['GORK_MODEL'] ?? 'gpt-4o-mini';
  final http.Response response;
  try {
    response = await (client ?? http.Client())
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': 5,
            'messages': [
              {'role': 'user', 'content': 'Reply with the single word: pong'}
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));
  } catch (e) {
    throw StateError('LLM unreachable at $baseUrl: $e');
  }
  if (response.statusCode != 200) {
    throw StateError('LLM returned ${response.statusCode}: ${response.body}');
  }
  return 'ok ($model @ $baseUrl)';
}

/// The whole command surface. Returns a process exit code; prints via `out`.
Future<int> runCli(
  List<String> args, {
  required ConfigStore config,
  DaemonClient? client,
  void Function(String line) out = print,
  DaemonControl? control,
  Autostart? autostart,
  Future<String> Function()? readLine,
  Future<bool> Function()? selfUpdateRun,
}) async {
  final defaultClient = client ??
      DaemonClient(
        baseUrl:
            'http://127.0.0.1:${config.read()['GORK_PORT'] ?? '8787'}',
        secret: config.read()['GORK_SECRET'] ?? '',
      );

  Future<int> requireDaemon(Future<int> Function() action) async {
    try {
      return await action();
    } on DaemonApiError catch (e) {
      out('error: $e');
      out('hint: is the daemon running?  gork daemon start   (then: gork status)');
      return 1;
    } catch (e) {
      out('error: $e');
      out('hint: is the daemon running?  gork daemon start   (then: gork status)');
      return 1;
    }
  }

  if (args.isEmpty) {
    out(_usage);
    return 1;
  }

  switch (args.first) {
    case 'config':
      final sub = args.elementAtOrNull(1);
      switch (sub) {
        case 'set':
          if (args.length < 4) {
            out('usage: gork config set KEY VALUE');
            return 1;
          }
          await config.set(args[2], args.sublist(3).join(' '));
          out('${args[2]}=${config.get(args[2])}');
          return 0;
        case 'get':
          if (args.length < 3) {
            out('usage: gork config get KEY');
            return 1;
          }
          final value = config.get(args[2]);
          out(value == null ? '(not set)' : value);
          return value == null ? 1 : 0;
        case 'list':
          final values = config.list();
          if (values.isEmpty) {
            out('(empty — run: gork llm set openai && gork config set GORK_API_KEY sk-...)');
            return 0;
          }
          for (final entry in values.entries) {
            final masked =
                entry.key.contains('KEY') || entry.key.contains('SECRET')
                    ? '${entry.value.substring(0, min(6, entry.value.length))}...'
                    : entry.value;
            out('${entry.key}=$masked');
          }
          return 0;
        default:
          out('usage: gork config set KEY VALUE | get KEY | list');
          return 1;
      }

    case 'llm':
      final sub = args.elementAtOrNull(1);
      switch (sub) {
        case 'providers':
          for (final preset in kLlmPresets) {
            out('${preset.id.padRight(12)} ${preset.label}  (${preset.baseUrl}, ${preset.model})');
          }
          out('pick one:    gork llm set <id>');
          return 0;
        case 'set':
          final preset = llmPreset(args.elementAtOrNull(2) ?? '');
          if (preset == null) {
            out('unknown provider "${args.elementAtOrNull(2)}". known:');
            for (final p in kLlmPresets) {
              out('  ${p.id}');
            }
            out('or set manually: gork config set GORK_BASE_URL ... && gork config set GORK_MODEL ...');
            return 1;
          }
          await config.set('GORK_BASE_URL', preset.baseUrl);
          await config.set('GORK_MODEL', preset.model);
          out('llm: ${preset.id} (${preset.baseUrl}, model ${preset.model})');
          out('now: gork config set GORK_API_KEY <your-key>   then: gork llm test');
          return 0;
        case 'test':
          try {
            final result = await llmTest(config);
            out('llm test: $result');
            return 0;
          } catch (e) {
            out('llm test FAILED: $e');
            return 1;
          }
        default:
          out('usage: gork llm providers | set <id> | test');
          return 1;
      }

    case 'tasks':
      return requireDaemon(() async {
        final sub = args.elementAtOrNull(1);
        switch (sub) {
          case 'add':
            if (args.length < 4) {
              out('usage: gork tasks add "Title" "prompt" [repeatMinutes]');
              return 1;
            }
            final repeat =
                args.length > 4 ? int.tryParse(args[4]) ?? 60 : 60;
            final saved = await defaultClient.tasksAdd(
              title: args[2],
              prompt: args[3],
              repeatMinutes: repeat,
            );
            out('saved: ${(saved['saved'] as Map)['id']} (${args[2]}, every $repeat min)');
            return 0;
          case 'list' || null:
            final tasks = await defaultClient.tasksList();
            if (tasks.isEmpty) {
              out('(no tasks — add one: gork tasks add "Title" "prompt" 60)');
              return 0;
            }
            for (final t in tasks) {
              out('${t['id']}  every ${t['repeatMinutes']}min  ${t['title']}');
            }
            return 0;
          case 'remove':
            final id = args.elementAtOrNull(2);
            if (id == null) {
              out('usage: gork tasks remove <id>   (list ids with: gork tasks list)');
              return 1;
            }
            final removed = await defaultClient.tasksRemove(id);
            out('removed: ${removed['deleted']}');
            return 0;
          case 'run':
            final ran = await defaultClient.tasksRun();
            out('ran ${ran['ran']} due task(s)');
            return 0;
          default:
            out('usage: gork tasks add|list|remove|run');
            return 1;
        }
      });

    case 'update':
    case 'upgrade': {
      // Movement 61 — the whole install comes up to date with ONE command:
      // source, deps, launcher wrappers and boot hooks, then the daemon
      // restarts and /health must answer. config.env (LLM keys, secret),
      // tasks and the vault all live outside the source tree — nothing is
      // ever lost, no key re-entry.
      final run = selfUpdateRun ?? SelfUpdate(control: control, out: out).run;
      final ok = await run();
      return ok ? 0 : 1;
    }

    case 'daemon':
    case 'start':
    case 'stop':
    case 'restart':
    case 'logs': {
      // Lifecycle lives in THIS command: `gork daemon start` and the
      // `gork start` shorthand both land here. One CLI, everything.
      final ctl = control ?? DaemonControl();
      final String sub;
      final bool quiet;
      if (args.first == 'daemon') {
        sub = args.elementAtOrNull(1) ?? 'status';
        quiet = args.contains('--quiet');
      } else {
        sub = args.first;
        quiet = args.contains('--quiet');
      }
      switch (sub) {
        case 'start':
          final ok = await ctl.start(quiet: quiet, out: out);
          return ok ? 0 : 1;
        case 'stop':
          await ctl.stop(out: quiet ? (_) {} : out);
          return 0;
        case 'restart':
          final ok = await ctl.restart(quiet: quiet, out: out);
          return ok ? 0 : 1;
        case 'status':
          out(await ctl.statusLine());
          return 0;
        case 'health':
          out(await ctl.isHealthy() ? 'healthy' : 'unhealthy');
          return await ctl.isHealthy() ? 0 : 1;
        case 'logs':
          final n = args.where((a) => int.tryParse(a) != null).toList();
          out(ctl.logs(n.isEmpty ? 40 : int.parse(n.last)));
          return 0;
        case 'update': {
          // `gork daemon update` == `gork update` — one path, same code.
          final run =
              selfUpdateRun ?? SelfUpdate(control: ctl, out: out).run;
          final ok = await run();
          return ok ? 0 : 1;
        }
        default:
          out('usage: gork daemon start|stop|restart|status|health|logs|update [n]');
          return 1;
      }
    }

    case 'autostart': {
      // Boot-time auto-start hooks: Termux:Boot, shell profiles,
      // /etc/profile.d, cron @reboot. Idempotent — safe to re-run.
      final auto = autostart ?? Autostart();
      out('installing auto-start hooks (idempotent):');
      for (final line in auto.apply()) {
        out('  $line');
      }
      out('the daemon now starts when Termux / the distro starts.');
      return 0;
    }

    case 'browser':
      return requireDaemon(() async {
        final sub = args.elementAtOrNull(1) ?? 'status';
        switch (sub) {
          case 'status':
            final status = await defaultClient.browserStatus();
            for (final entry in status.entries) {
              out('${entry.key}: ${jsonEncode(entry.value)}');
            }
            return 0;
          case 'open':
            final url = args.elementAtOrNull(2);
            if (url == null) {
              out('usage: gork browser open <url> [session]');
              return 1;
            }
            final result = await defaultClient.browserOp('navigate',
                session: args.elementAtOrNull(3) ?? 'default',
                args: {'url': url});
            out(jsonEncode(result));
            return (result['ok'] as bool? ?? false) ? 0 : 1;
          case 'read':
            final result = await defaultClient.browserOp('read',
                session: args.elementAtOrNull(3) ?? 'default',
                args: {'selector': args.elementAtOrNull(2) ?? ''});
            out(result['text'] ?? jsonEncode(result));
            return (result['ok'] as bool? ?? false) ? 0 : 1;
          case 'close':
            final result = await defaultClient.browserOp('close',
                session: args.elementAtOrNull(2) ?? 'default');
            out(jsonEncode(result));
            return 0;
          default:
            out('usage: gork browser status | open <url> | read [selector] '
                '| close');
            return 1;
        }
      });

    case 'vault': {
      final sub = args.elementAtOrNull(1);
      final ctl = control ?? DaemonControl();
      final dir = ctl.stateDir;
      switch (sub) {
        case 'set':
          final label = args.elementAtOrNull(2);
          if (label == null || readLine == null) {
            out('usage: gork vault set <label>   (value comes from stdin — '
                'it must never land in shell history or argv)');
            return 1;
          }
          final value = (await readLine()).trim();
          if (value.isEmpty) {
            out('error: empty value');
            return 1;
          }
          return vaultSet(dir, label, value, out);
        case 'list' || null:
          return vaultList(dir, out);
        case 'rm':
          final label = args.elementAtOrNull(2);
          if (label == null) {
            out('usage: gork vault rm <label>');
            return 1;
          }
          return vaultRemove(dir, label, out);
        default:
          out('usage: gork vault set <label> | list | rm <label>');
          return 1;
      }
    }

    case 'status':
      return requireDaemon(() async {
        out(await defaultClient.statusLine());
        return 0;
      });

    case 'secret':
      final secret = config.get('GORK_SECRET') ?? '';
      if (secret.isEmpty) {
        out('(no secret set — the daemon accepts unauthenticated local access)');
        return 1;
      }
      out(secret);
      out('^ paste this into the app: Cloud Computer -> AgentVPS -> secret');
      return 0;

    default:
      out(_usage);
      return 1;
  }
}

const String _usage = '''usage: gork <command>
  update                                  bring the whole install up to date
                                          (also: gork daemon update) — source,
                                          deps, wrappers, hooks, restart;
                                          config, tasks and vault are kept
  daemon start|stop|restart|status|logs   the daemon lifecycle (also: gork start)
  autostart                               install boot hooks (Termux:Boot, shell
                                          profiles, profile.d, cron @reboot)
  config set KEY VALUE | get KEY | list   configure without opening files
  llm providers | set <id> | test         pick + verify an LLM endpoint
  tasks add "T" "prompt" [min]            schedule AI tasks
  tasks list | remove <id> | run          manage tasks on the daemon
  browser status|open <url>|read|close    drive the agent browser from the shell
  vault set <label> | list | rm <label>   sealed secrets the browser can fill
  status                                  daemon liveness + task count
  secret                                  show the pairing secret for the app''';
