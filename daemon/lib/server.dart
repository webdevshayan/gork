import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:gork_daemon/browser_agent.dart';
import 'package:gork_daemon/cli_support.dart';
import 'package:gork_daemon/scheduler.dart';

/// gork companion daemon.
///
/// Runs on the user's own VPS. Holds the schedule, calls the LLM on due
/// tasks, and pushes results to the phone via ntfy (no account needed).
/// The phone app connects over REST.
const int kDefaultPort = 8787;

/// Where task state lives.
///
/// `GORK_HOME` (if set) points at the daemon's state directory — set by the
/// systemd unit, the Termux service, or gork-daemonctl — so tasks.json
/// survives no matter which directory the daemon was started from.
String taskStorePath({Map<String, String>? env}) {
  final e = env ?? Platform.environment;
  final home = e['GORK_HOME'] ?? '';
  if (home.isEmpty) return 'tasks.json';
  return home.endsWith('/') ? '${home}tasks.json' : '$home/tasks.json';
}

TaskStore newTaskStore() => FileTaskStore(taskStorePath());

class Daemon {
  final TaskStore tasks;
  final LlmCaller llm;
  final Notifier notifier;
  final Clock clock;

  Daemon(this.tasks, this.llm, this.notifier, {Clock? clock})
      : clock = clock ?? systemClock;

  Future<int> runDueTasks() async {
    final now = clock();
    final due = dueTasks(tasks.all(), now);
    var ran = 0;
    for (final task in due) {
      String result;
      try {
        result = await llm.call(task.prompt);
      } catch (e) {
        result = 'Task failed: $e';
        await tasks.markRan(task.id, now);
        continue;
      }
      await tasks.markRan(task.id, now);
      await notifier.notify('gork: ${task.title}', result);
      ran++;
    }
    return ran;
  }
}

Response _json(Map<String, dynamic> data, [int status = 200]) => Response(
      status,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );

/// Optional shared-secret gate. When GORK_SECRET is set, every request must
/// carry the same value in the X-Gork-Secret header.
Middleware requireSecret(String? secret) {
  return (inner) => (Request request) async {
        if (secret == null || secret.isEmpty) return inner(request);
        // Liveness stays open: installers, uptime monitors and `curl` checks
        // must be able to verify the daemon without holding the secret.
        if (request.url.path == 'health') return inner(request);
        final bearer = (request.headers['authorization'] ?? '')
            .replaceFirst(RegExp(r'^[Bb]earer '), '').trim();
        if (request.headers['x-gork-secret'] == secret ||
            bearer == secret) {
          return inner(request);
        }
        return Response(401,
            body: jsonEncode({'error': 'bad or missing X-Gork-Secret'}),
            headers: {'content-type': 'application/json'});
      };
}

/// The full HTTP handler: router wrapped in the secret gate. [config] and
/// [configOverlay] wire up POST /config (the app's Sync-to-daemon action).
/// [vaultDir] wires up GET /v1/vault (the sealed vault's labels).
Handler buildHandler(
  Daemon daemon, {
  String? secret,
  ConfigStore? config,
  Map<String, String>? configOverlay,
  AgentBrowser? browser,
  String? vaultDir,
}) =>
    const Pipeline()
        .addMiddleware(requireSecret(secret))
        .addHandler(buildRouter(daemon,
            config: config,
            configOverlay: configOverlay,
            browser: browser,
            vaultDir: vaultDir));

/// Keys the phone may write through POST /config. GORK_PORT is allowed (it
/// only takes effect on restart) and GORK_CONNECTOR_* come from the
/// connectors map.
const Set<String> kConfigurableKeys = {
  'GORK_API_KEY',
  'GORK_BASE_URL',
  'GORK_MODEL',
  'NTFY_TOPIC',
  'GORK_PORT',
};

Router buildRouter(Daemon daemon,
    {ConfigStore? config,
    Map<String, String>? configOverlay,
    AgentBrowser? browser,
    String? vaultDir}) {
  final router = Router();

  router.get('/health', (Request request) async {
    return _json({
      'status': 'ok',
      'service': 'gork-daemon',
      'time': daemon.clock().toIso8601String(),
    });
  });

  router.get('/tasks', (Request request) async {
    return _json({
      'tasks': [for (final t in daemon.tasks.all()) t.toJson()],
    });
  });

  router.post('/tasks', (Request request) async {
    final raw = await request.readAsString();
    final Map<String, dynamic> body;
    try {
      body =
          raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return _json({'error': 'body must be JSON'}, 400);
    }
    final id = (body['id'] as String?) ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final task = Task(
      id: id,
      title: body['title'] as String? ?? 'Untitled',
      prompt: body['prompt'] as String? ?? '',
      repeatMinutes: (body['repeatMinutes'] as num?)?.toInt() ?? 60,
      enabled: body['enabled'] as bool? ?? true,
      lastRun: body['lastRun'] as int?,
    );
    if (task.prompt.isEmpty) {
      return _json({'error': 'prompt is required'}, 400);
    }
    await daemon.tasks.save(task);
    return _json({'saved': task.toJson()}, 201);
  });

  router.delete('/tasks/<id>', (Request request, String id) async {
    await daemon.tasks.delete(id);
    return _json({'deleted': id});
  });

  router.post('/run', (Request request) async {
    final ran = await daemon.runDueTasks();
    return _json({'ran': ran});
  });

  // The phone's "Sync to daemon" action: write provider keys, model, ntfy
  // topic and connector tokens into config.env, apply the LLM config live,
  // and report honestly what changed.
  router.post('/config', (Request request) async {
    if (config == null || configOverlay == null) {
      return _json({'error': 'config store not wired in this daemon'}, 500);
    }
    final raw = await request.readAsString();
    final Map<String, dynamic> body;
    try {
      body =
          raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return _json({'error': 'body must be JSON'}, 400);
    }

    final saved = <String>[];
    final needsRestart = <String>[];
    final incoming = body['config'] as Map<String, dynamic>? ?? {};
    for (final entry in incoming.entries) {
      if (!kConfigurableKeys.contains(entry.key)) continue;
      final value = entry.value?.toString() ?? '';
      if (value.isEmpty) continue;
      await config.set(entry.key, value);
      configOverlay[entry.key] = value;
      saved.add(entry.key);
      if (entry.key == 'GORK_PORT') needsRestart.add('GORK_PORT');
    }

    final connectors = body['connectors'] as Map<String, dynamic>? ?? {};
    for (final entry in connectors.entries) {
      final key = 'GORK_CONNECTOR_${entry.key.toString().toUpperCase()}';
      final value = entry.value?.toString() ?? '';
      if (value.isEmpty) continue;
      await config.set(key, value);
      configOverlay[key] = value;
      saved.add(key);
    }

    return _json({
      'saved': saved,
      'needsRestart': needsRestart,
      'llm': configOverlay['GORK_API_KEY'] == null ||
              configOverlay['GORK_API_KEY']!.isEmpty
          ? 'not configured'
          : 'live',
    });
  });

  // Read the daemon's config back. Secrets never leave the box: the API key
  // is redacted, connector tokens are listed by id only.
  router.get('/config', (Request request) async {
    if (config == null || configOverlay == null) {
      return _json({'error': 'config store not wired in this daemon'}, 500);
    }
    final values = config.read();
    final visible = <String, dynamic>{};
    for (final entry in values.entries) {
      if (entry.key == 'GORK_API_KEY' || entry.key.startsWith('GORK_CONNECTOR_')) {
        continue;
      }
      visible[entry.key] = entry.value;
    }
    final connectors = <String, String>{
      for (final entry in values.entries)
        if (entry.key.startsWith('GORK_CONNECTOR_'))
          entry.key.substring('GORK_CONNECTOR_'.length).toLowerCase(): 'connected',
    };
    return _json({
      'config': visible,
      'connectors': connectors,
      'apiKeyConfigured':
          (values['GORK_API_KEY'] ?? '').isNotEmpty,
    });
  });

  // The sealed vault's LABELS for the phone's Security screen. Values never
  // leave the box: this endpoint answers with names only — a value has
  // exactly one way out, fill_secret, straight into the page's active input.
  router.get('/v1/vault', (Request request) async {
    if (vaultDir == null) {
      return _json({'error': 'vault not wired in this daemon'}, 500);
    }
    final labels = readVault(vaultDir).keys.toList()..sort();
    return _json({
      'entries': [for (final label in labels) {'label': label}],
      'count': labels.length,
    });
  });

  // Movement 58 — the agent browser: PRIVATE (dedicated 0700 profile,
  // vault values never echoed), PERSISTENT (cookies survive restarts),
  // LIGHTWEIGHT (one headless Chromium over raw CDP, spawned lazily).
  // The phone's BrowserService speaks exactly this protocol:
  //   POST /v1/browser/op  {session, action, url/selector/text/label}
  if (browser != null) {
    router.get('/v1/browser/status', (Request request) async {
      return _json(browser.status());
    });
    router.post('/v1/browser/op', (Request request) async {
      final raw = await request.readAsString();
      final Map<String, dynamic> body;
      try {
        body = raw.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(raw) as Map<String, dynamic>;
      } on FormatException {
        return _json({'ok': false, 'error': 'body must be JSON'}, 400);
      }
      final session = body['session']?.toString() ?? 'default';
      final action = body['action']?.toString() ?? '';
      final args = (body['args'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{
            for (final e in body.entries)
              if (e.key != 'session' && e.key != 'action') e.key: e.value,
          };
      return _json(await browser.op(session, action, args));
    });
  }

  return router;
}

Future<void> main(List<String> args) async {
  final port =
      int.tryParse(Platform.environment['GORK_PORT'] ?? '') ?? kDefaultPort;

  // Live config overlay: POST /config (the phone's Sync action) writes here,
  // so new LLM credentials apply without a daemon restart.
  final overlay = <String, String>{};
  final config = ConfigStore(configPath());

  final llm = EnvLlmCaller(null, overlay);
  final topic = Platform.environment['NTFY_TOPIC'];
  final notifier =
      topic == null || topic.isEmpty ? const NoopNotifier() : NtfyNotifier(topic);

  final daemon = Daemon(newTaskStore(), llm, notifier);
  final browser = AgentBrowser();
  final secret = Platform.environment['GORK_SECRET'];
  final handler = buildHandler(daemon,
      secret: secret,
      config: config,
      configOverlay: overlay,
      browser: browser,
      vaultDir: stateDirPath());

  // The agent browser must not outlive the daemon: SIGTERM (gork daemon
  // stop / systemd) closes it, then exits.
  ProcessSignal.sigterm.watch().listen((_) async {
    await browser.shutdown();
    exit(0);
  });
  ProcessSignal.sigint.watch().listen((_) async {
    await browser.shutdown();
    exit(0);
  });

  // 24/7 loop: check the schedule every minute.
  Timer.periodic(const Duration(minutes: 1), (_) async {
    try {
      await daemon.runDueTasks();
    } catch (e) {
      stdout.writeln('runDueTasks error: $e');
    }
  });

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
      'gork daemon listening on http://${server.address.host}:${server.port}');
  stdout.writeln(
      'LLM: ${llm.describe()} | ntfy: ${topic ?? 'disabled'} | secret: ${secret == null || secret.isEmpty ? 'off' : 'on'}');
  stdout.writeln(
      'agent browser: ${browser.status()['binary']} | profile: ${browser.profileDir}');
}
