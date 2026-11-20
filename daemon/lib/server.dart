import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;

import 'package:gork_daemon/browser_agent.dart';
import 'package:gork_daemon/cli_support.dart';
import 'package:gork_daemon/google_auth.dart';
import 'package:gork_daemon/job_store.dart';
import 'package:gork_daemon/scheduler.dart';

/// gork companion daemon.
///
/// Runs on the user's own VPS. Holds the schedule, calls the LLM on due
/// tasks, and pushes results to the phone via ntfy (no account needed).
/// The phone app connects over REST.
const int kDefaultPort = 8787;

/// The daemon's own version, reported by /health. The phone app shows it
/// (Cloud Computer) and uses a refusal from an OLD daemon to point the user
/// at `gork daemon update`. Bump when the daemon gains endpoints or fixes.
const String kDaemonVersion = '0.6.0';

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
/// [vaultDir] wires up GET /v1/vault (the sealed vault's labels). [jobStore]
/// wires up the never-losable chat jobs (POST /v1/messages & friends).
Handler buildHandler(
  Daemon daemon, {
  String? secret,
  ConfigStore? config,
  Map<String, String>? configOverlay,
  AgentBrowser? browser,
  String? vaultDir,
  JobStore? jobStore,
  SeenStore? seenStore,
  GoogleAuth? google,
}) =>
    const Pipeline()
        .addMiddleware(requireSecret(secret))
        .addHandler(buildRouter(daemon,
            config: config,
            configOverlay: configOverlay,
            browser: browser,
            vaultDir: vaultDir,
            jobStore: jobStore,
            seenStore: seenStore,
            google: google));

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
    String? vaultDir,
    JobStore? jobStore,
    SeenStore? seenStore,
    GoogleAuth? google}) {
  final router = Router();

  router.get('/health', (Request request) async {
    return _json({
      'status': 'ok',
      'service': 'gork-daemon',
      'version': kDaemonVersion,
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

  // Movement 69 — Skills live here as markdown: the app pushes every skill
  // it teaches or harvests from the agent; the agent reads them back from
  // $GORK_HOME/skills so it can FOLLOW its own learned how-tos.
  router.post('/skills', (Request request) async {
    final raw = await request.readAsString();
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return _json({'error': 'body must be JSON'}, 400);
    }
    final id = body['id']?.toString() ?? '';
    final title = body['title']?.toString() ?? '';
    final markdown = body['markdown']?.toString() ?? '';
    if (id.isEmpty || markdown.isEmpty) {
      return _json({'error': 'id and markdown are required'}, 400);
    }
    final home = Platform.environment['GORK_HOME'] ??
        '${Platform.environment['HOME'] ?? '.'}/.gork';
    final dir = Directory('$home/skills');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final safe = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final f = File('${dir.path}/$safe.md');
    await f.writeAsString(
        markdown.startsWith('# ') ? markdown : '# $title\n\n$markdown',
        flush: true);
    return _json({'saved': f.path});
  });

  router.get('/skills', (Request request) async {
    final home = Platform.environment['GORK_HOME'] ??
        '${Platform.environment['HOME'] ?? '.'}/.gork';
    final dir = Directory('$home/skills');
    final skills = <Map<String, String>>[];
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.md')) continue;
        skills.add({
          'id': f.path.split('/').last.replaceAll('.md', ''),
          'markdown': f.readAsStringSync(),
        });
      }
    }
    return _json({'skills': skills});
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

  // Movement 61 — the Google Cloud Console credentials.json travels to the
  // VPS exactly ONCE (the phone's Google screen POSTs it here). Sealed into
  // the vault like any other entry: 0600 file, values never read back —
  // the status endpoint answers with a boolean only. The phone validates
  // the JSON structure before uploading; the daemon re-checks the shape.
  router.post('/v1/credentials/google', (Request request) async {
    if (vaultDir == null) {
      return _json({'error': 'vault not wired in this daemon'}, 500);
    }
    final raw = await request.readAsString();
    final Map<String, dynamic> body;
    try {
      body = raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return _json({'error': 'body must be JSON'}, 400);
    }
    final clientJson = body['client_json'];
    final isOAuthClient =
        clientJson is Map && (clientJson['installed'] != null || clientJson['web'] != null);
    final isServiceAccount =
        clientJson is Map && clientJson['private_key'] != null && clientJson['client_email'] != null;
    if (!isOAuthClient && !isServiceAccount) {
      return _json({
        'error': 'client_json must be an OAuth client ("installed"/"web") '
            'or a service-account JSON',
      }, 400);
    }
    await writeVaultSecret(
        vaultDir, 'google_credentials', jsonEncode(clientJson));
    return _json({'stored': true, 'sealed': true}, 201);
  });

  router.get('/v1/credentials/google/status', (Request request) async {
    if (vaultDir == null) {
      return _json({'error': 'vault not wired in this daemon'}, 500);
    }
    return _json({
      'has_client_json':
          readVault(vaultDir).containsKey('google_credentials'),
    });
  });

  // Movement 62 — NEVER-LOSABLE CHAT. The phone's outbox hands a message
  // here; the job is persisted to $GORK_HOME/jobs.json FIRST, then processed
  // through the LLM. The phone can die mid-flight — the work completes on
  // the VPS, the reply is stored, and a notification with the first lines
  // goes out via ntfy. The client pulls everything back when it returns.
  //   POST /v1/messages                        {conversation_id, text} -> {id}
  //   GET  /v1/jobs/<id>                       -> {status, result:{reply}}
  //   GET  /v1/conversations/<id>/messages     -> user/assistant pairs
  //
  // Jobs run SEQUENTIALLY through a chain: a personal VPS serves one user,
  // the LLM prefers not to be hammered, and concurrent read-modify-write
  // on jobs.json would race. Acceptance (201) is still instant — the
  // message is durable the moment the phone gets its id.
  Future<void> jobChain = Future.value();

  /// Movement 65 — the chat persona. The reply must feel like a person who
  /// just read the whole thread on their phone: it SEES everything the user
  /// sent (including the messages typed while the previous reply was still
  /// being written — they arrive as one batch, each line a separate text)
  /// and answers once, naturally. History comes from [conversationHistory].
  const String chatSystemPrompt =
      "You are gork, the user's personal assistant on their own VPS — and "
      'you come across like a real person reading messages on your phone: '
      'warm, direct, brief. Never announce that you are an AI and never '
      'narrate mechanics. Markdown is fine (short lists, code, tables). '
      'When one message from the user contains several lines, those are '
      'separate texts they typed in quick succession — often while your '
      'previous reply was still being written. Read them all together and '
      'answer once, the way a person would after reading the whole thread: '
      'react to what changed between the lines instead of answering each '
      'line in isolation, and if something they added makes an earlier '
      'question moot, say so and answer the latest version.';

  /// The conversation so far for [job]: every earlier job in the same
  /// conversation, oldest first — the user's text, and for completed jobs
  /// the assistant's reply. Failed jobs contribute only their user text
  /// (the exception string is never spoken as if it were the assistant's
  /// words). Capped at the last 40 turns to bound the request size.
  List<({String role, String content})> conversationHistory(
      JobStore store, AgentJob job) {
    final turns = <({String role, String content})>[];
    final prior = store
        .all()
        .where((j) =>
            j.conversationId == job.conversationId &&
            j.id != job.id &&
            j.createdAt <= job.createdAt)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final j in prior) {
      if (j.text.trim().isNotEmpty) {
        turns.add((role: 'user', content: j.text));
      }
      final reply = j.reply;
      if (j.status == 'done' && reply != null && reply.trim().isNotEmpty) {
        turns.add((role: 'assistant', content: reply));
      }
    }
    return turns.length <= 40 ? turns : turns.sublist(turns.length - 40);
  }

  /// Movement 67 — push the completion notification ONLY if the user has
  /// not already read the reply. The phone's poll (?seen=1, every 2 s
  /// while the chat is open) lands within a second or two of the reply
  /// being stored — but the ntfy push would race it out the door, so the
  /// decision is deferred: re-check the read marker for a few seconds,
  /// and push at the deadline only if no acknowledgment arrived.
  Future<void> _notifyUnlessRead(AgentJob job, String body,
      {required String title, required int finishedAtMs}) async {
    // No read-marker store wired (bare daemon, old deployments): push
    // immediately — the suppressor simply does not exist there.
    if (seenStore == null) {
      await daemon.notifier.notify(title, body);
      return;
    }
    // Bounded by iterations, not by the clock: tests pin daemon.clock(),
    // and a frozen clock would spin an isAfter() loop forever. ~6 s of
    // 700 ms waits; the marker is re-checked between every wait.
    const checks = 9;
    for (var i = 0; i < checks; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (seenStore!.hasSeen(job.conversationId, job.id, finishedAtMs)) {
        return; // read while we waited — no push
      }
    }
    await daemon.notifier.notify(title, body);
  }

  // Movement 67 — THE AGENT'S HANDS. Until now a chat job was ONE
  // completion call: the model could only talk about the box, never touch
  // it ("I have no tools, no filesystem, no shell" — screenshots
  // 2026-11-19). runAgentTurn wraps the LLM in a function-calling loop:
  // the model may call tools (shell, files, fetch, the agent browser,
  // scheduling) up to [kMaxToolRounds] times before the final answer.
  // A provider that refuses `tools` (plain text-only endpoints) falls
  // back to the old single-call behavior — chat keeps working everywhere.

  /// Tool rounds per turn — a safety cap, not a target.
  const int kMaxToolRounds = 8;

  const String chatToolsNote =
      '\n\nYou have TOOLS on your own VPS and you should USE them when a '
      'request needs hands: shell (run any command), read_file / '
      'write_file / list_dir (the filesystem), fetch_url (get a web page '
      'or API), browser (drive a real headless Chromium: navigate, click, '
      'type, read the page, screenshot), create_task (schedule a recurring '
      'job). Call a tool, read the result, then continue; when the work is '
      'done, answer briefly in your own voice. Do not claim you lack '
      'tools — try them.';

  /// The OpenAI function-calling schema for the agent's tools.
  final List<Map<String, dynamic>> agentToolSchemas = <Map<String, dynamic>>[
        {
          'type': 'function',
          'function': {
            'name': 'shell',
            'description':
                'Run a bash command on the VPS and get stdout/stderr. '
                '30 s timeout, output capped.',
            'parameters': {
              'type': 'object',
              'properties': {
                'command': {'type': 'string'},
              },
              'required': ['command'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'read_file',
            'description': 'Read a text file. Optional offset/limit lines.',
            'parameters': {
              'type': 'object',
              'properties': {
                'path': {'type': 'string'},
                'offset': {'type': 'integer'},
                'limit': {'type': 'integer'},
              },
              'required': ['path'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'write_file',
            'description':
                'Write (or overwrite) a text file; parent directories are '
                'created. Use for scripts, notes, drafts.',
            'parameters': {
              'type': 'object',
              'properties': {
                'path': {'type': 'string'},
                'content': {'type': 'string'},
              },
              'required': ['path', 'content'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'list_dir',
            'description': 'List a directory with sizes.',
            'parameters': {
              'type': 'object',
              'properties': {
                'path': {'type': 'string'},
              },
              'required': ['path'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'fetch_url',
            'description':
                'GET a URL from the VPS and return status + body text '
                '(capped). For APIs and static pages; JS sites need browser.',
            'parameters': {
              'type': 'object',
              'properties': {
                'url': {'type': 'string'},
              },
              'required': ['url'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'browser',
            'description':
                'Drive the persistent headless browser: action = navigate '
                '(url) | click (selector) | type (selector, text) | read '
                '(selector?) | scroll (delta) | screenshot | back. Session '
                '"agent" is yours; cookies persist.',
            'parameters': {
              'type': 'object',
              'properties': {
                'action': {'type': 'string'},
                'url': {'type': 'string'},
                'selector': {'type': 'string'},
                'text': {'type': 'string'},
                'delta': {'type': 'number'},
              },
              'required': ['action'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'create_task',
            'description':
                'Schedule a recurring task (runs every repeatMinutes, '
                'prompt goes to the LLM).',
            'parameters': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string'},
                'prompt': {'type': 'string'},
                'repeatMinutes': {'type': 'integer'},
              },
              'required': ['title', 'prompt'],
            },
          },
        },
      ];

  /// Execute one tool call. Every failure becomes a STRING result — the
  /// loop must always be able to continue.
  Future<String> runAgentTool(String name, Map<String, dynamic> args) async {
    String _clip(String s, [int n = 8000]) =>
        s.length <= n ? s : '${s.substring(0, n)}\n…(truncated)';
    try {
      switch (name) {
        case 'shell':
          final cmd = args['command']?.toString() ?? '';
          if (cmd.trim().isEmpty) return 'error: command is required';
          // Process.run has no timeout parameter — wrap the future. A
          // timed-out process may linger; acceptable on the user's own
          // box, and 124 mirrors the shell's timeout convention.
          final r = await Process.run('bash', ['-c', cmd]).timeout(
              const Duration(seconds: 30),
              onTimeout: () => ProcessResult(
                  -1, 124, '', 'timed out after 30 s'));
          return _clip(
              'exit=${r.exitCode}\nstdout:\n${r.stdout}\nstderr:\n${r.stderr}');
        case 'read_file':
          final f = File(args['path']!.toString());
          if (!f.existsSync()) return 'error: no such file';
          final lines = f.readAsLinesSync();
          final offset =
              args.containsKey('offset') ? (args['offset'] as num).toInt() : 0;
          final limit =
              args.containsKey('limit') ? (args['limit'] as num).toInt() : 400;
          return _clip(lines
              .skip(offset)
              .take(limit)
              .map((l) => l)
              .join('\n'));
        case 'write_file':
          final f = File(args['path']!.toString());
          await f.parent.create(recursive: true);
          await f.writeAsString(args['content']?.toString() ?? '');
          return 'written ${f.path} (${args['content']?.toString().length ?? 0} bytes)';
        case 'list_dir':
          final dir = Directory(args['path']?.toString() ?? '.');
          if (!dir.existsSync()) return 'error: no such directory';
          final entries = dir.listSync()
            ..sort((a, b) => a.path.compareTo(b.path));
          return _clip([
            for (final e in entries.take(200))
              '${FileSystemEntity.isDirectorySync(e.path) ? "d" : "-"} '
                  '${e.runtimeType.toString().substring(0, 1)} '
                  '${e.path.split("/").last}',
          ].join('\n'));
        case 'fetch_url':
          final url_ = args['url']?.toString() ?? '';
          if (Uri.tryParse(url_)?.scheme.startsWith('http') != true) {
            return 'error: a valid http(s) url is required';
          }
          final client = http.Client();
          try {
            final res = await client
                .get(Uri.parse(url_))
                .timeout(const Duration(seconds: 20));
            return _clip('status=${res.statusCode}\n'
                'content-type: ${res.headers['content-type']}\n\n'
                '${res.body}');
          } finally {
            client.close();
          }
        case 'browser':
          if (browser == null) {
            return 'error: the agent browser is not wired in this daemon';
          }
          final action = args['action']?.toString() ?? '';
          final opArgs = <String, dynamic>{};
          for (final k in ['url', 'selector', 'text', 'delta']) {
            if (args[k] != null) opArgs[k] = args[k];
          }
          final r = await browser.op('agent', action, opArgs);
          return _clip(jsonEncode(r));
        case 'create_task':
          final title = args['title']?.toString() ?? 'Untitled';
          final prompt = args['prompt']?.toString() ?? '';
          if (prompt.trim().isEmpty) return 'error: prompt is required';
          final repeat =
              args.containsKey('repeatMinutes') &&
                  (args['repeatMinutes'] as num).toInt() > 0
              ? (args['repeatMinutes'] as num).toInt()
              : 60;
          await daemon.tasks.save(Task(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: title,
            prompt: prompt,
            repeatMinutes: repeat,
            enabled: true,
          ));
          return 'task "$title" scheduled every $repeat minutes';
        default:
          return 'error: unknown tool $name';
      }
    } catch (e) {
      return 'error: $e';
    }
  }

  /// One full agent turn: loop [chatSystemPrompt + tools note, history,
  /// user text] through the model, executing tool calls until the model
  /// answers in plain text or the round cap is hit. Returns the final text.
  Future<String> runAgentTurn(AgentJob job) async {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '$chatSystemPrompt$chatToolsNote',
      },
      for (final turn in conversationHistory(jobStore!, job))
        {'role': turn.role, 'content': turn.content},
      {'role': 'user', 'content': job.text},
    ];
    Map<String, dynamic>? lastToolRound;
    for (var round = 0; round < kMaxToolRounds; round++) {
      final turn = await daemon.llm.chat(messages, tools: agentToolSchemas);
      if (turn.toolCalls.isEmpty) {
        return turn.content ?? '';
      }
      lastToolRound = turn.raw;
      // Feed the assistant's tool_calls back, then every result.
      messages.add(lastToolRound);
      for (final call in turn.toolCalls) {
        Map<String, dynamic> args = {};
        try {
          final decoded = jsonDecode(call.argsJson);
          if (decoded is Map<String, dynamic>) args = decoded;
        } catch (_) {
          // malformed args — the tool will answer with a usable error
        }
        final result = await runAgentTool(call.name, args);
        stdout.writeln('agent tool ${call.name} -> '
            '${result.length} chars');
        messages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': result,
        });
      }
    }
    // Round cap: one last plain call so the user still gets words.
    final finalTurn =
        await daemon.llm.chat(messages..add({
          'role': 'user',
          'content': '(Stop using tools now — summarize what you found and '
              'answer.)',
        }));
    return finalTurn.content ?? '';
  }

  void processJob(AgentJob job) {
    jobChain = jobChain.then((_) async {
      try {
        await jobStore!.save(job.copyWith(status: 'running'));
        final reply = await runAgentTurn(job);
        await jobStore.save(job.copyWith(
            status: 'done', reply: reply, finishedAt: daemon.clock().millisecondsSinceEpoch));
        await _notifyUnlessRead(job, jobNotificationPreview(reply),
            title: 'gork — response ready',
            finishedAtMs: daemon.clock().millisecondsSinceEpoch);
      } catch (e) {
        try {
          await jobStore!.save(job.copyWith(
              status: 'error',
              reply: e.toString(),
              finishedAt: daemon.clock().millisecondsSinceEpoch));
          await _notifyUnlessRead(
              job,
              e.toString().length <= 220
                  ? e.toString()
                  : e.toString().substring(0, 220),
              title: 'gork — the request failed',
              finishedAtMs: daemon.clock().millisecondsSinceEpoch);
        } catch (_) {
          // state-dir trouble must not crash the request handler
        }
      }
    });
  }

  router.post('/v1/messages', (Request request) async {
    if (jobStore == null) {
      return _json({'error': 'jobs not wired in this daemon'}, 500);
    }
    final raw = await request.readAsString();
    final Map<String, dynamic> body;
    try {
      body = raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return _json({'error': 'body must be JSON'}, 400);
    }
    final conversationId = body['conversation_id']?.toString() ?? '';
    final text = body['text']?.toString() ?? '';
    if (conversationId.isEmpty || text.trim().isEmpty) {
      return _json({'error': 'conversation_id and text are required'}, 400);
    }
    final job = AgentJob(
      id: 'job-${DateTime.now().microsecondsSinceEpoch}'
          '-${(DateTime.now().microsecondsSinceEpoch % 9176).toRadixString(36)}',
      conversationId: conversationId,
      text: text,
      status: 'queued',
      createdAt: daemon.clock().millisecondsSinceEpoch,
    );
    // Persist BEFORE answering 201: accepted means durable.
    await jobStore.save(job);
    processJob(job);
    return _json({'id': job.id, 'status': job.status}, 201);
  });

  router.get('/v1/jobs/<id>', (Request request, String id) async {
    if (jobStore == null) {
      return _json({'error': 'jobs not wired in this daemon'}, 500);
    }
    final match = jobStore.all().where((j) => j.id == id).toList();
    if (match.isEmpty) {
      return _json({'error': 'no such job'}, 404);
    }
    final job = match.first;
    // Movement 67 — the phone acknowledging a job poll (?seen=1) means
    // whatever comes back is being displayed right now; record the read
    // marker so the completion push can skip already-read replies.
    if (request.url.queryParameters['seen'] == '1' && seenStore != null) {
      seenStore!.markSeen(job.conversationId,
          daemon.clock().millisecondsSinceEpoch,
          jobId: job.id);
    }
    return _json({
      'id': job.id,
      'conversation_id': job.conversationId,
      'status': job.status,
      'created_at': job.createdAt,
      if (job.reply != null) 'result': {'reply': job.reply},
    });
  });

  router.get('/v1/conversations/<id>/messages',
      (Request request, String id) async {
    if (jobStore == null) {
      return _json({'error': 'jobs not wired in this daemon'}, 500);
    }
    // Movement 67 — the chat screen's catch-up pull with ?seen=1: the
    // user is LOOKING at this thread right now; everything already in it
    // counts as read for the notification suppressor.
    if (request.url.queryParameters['seen'] == '1' && seenStore != null) {
      seenStore!.markSeen(id, daemon.clock().millisecondsSinceEpoch);
    }
    final jobs = jobStore
        .all()
        .where((j) => j.conversationId == id)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final messages = <Map<String, dynamic>>[];
    for (final job in jobs) {
      messages.add({'role': 'user', 'content': job.text});
      // A queued/running job contributes the user side only — the reply
      // lands here the moment it exists (never a placeholder).
      if (job.reply != null) {
        messages.add({'role': 'assistant', 'content': job.reply});
      }
    }
    return _json({'messages': messages});
  });

  // Movement 62 — GOOGLE LOGIN ON THE USER'S SERVER. The credentials.json
  // the user uploaded is the OAuth client; these routes drive the consent
  // flow with it. Tokens are sealed in the vault and never leave the box —
  // the phone sees email, name and which tools connected, nothing else.
  //   POST /v1/google/consent/start  {redirect_uri} -> {url}
  //   POST /v1/google/exchange       {code, redirect_uri} -> {email,name,tools}
  //   GET  /v1/google/accounts       -> {accounts: [...]}  (labels only)
  //   POST /v1/google/revoke         {email} -> {removed: true|false}
  router.post('/v1/google/consent/start', (Request request) async {
    if (google == null) {
      return _json({'error': 'google auth not wired in this daemon'}, 500);
    }
    final raw = await request.readAsString();
    Map<String, dynamic> body;
    try {
      body = raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return _json({'error': 'body must be JSON'}, 400);
    }
    final redirectUri = body['redirect_uri']?.toString() ?? '';
    if (redirectUri.isEmpty) {
      return _json({'error': 'redirect_uri is required'}, 400);
    }
    try {
      return _json({'url': google.consentUrl(redirectUri)});
    } on StateError catch (e) {
      return _json({'error': e.message}, 400);
    }
  });

  router.post('/v1/google/exchange', (Request request) async {
    if (google == null) {
      return _json({'error': 'google auth not wired in this daemon'}, 500);
    }
    final raw = await request.readAsString();
    Map<String, dynamic> body;
    try {
      body = raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return _json({'error': 'body must be JSON'}, 400);
    }
    final code = body['code']?.toString() ?? '';
    final redirectUri = body['redirect_uri']?.toString() ?? '';
    if (code.isEmpty || redirectUri.isEmpty) {
      return _json({'error': 'code and redirect_uri are required'}, 400);
    }
    try {
      final account = await google.exchange(code, redirectUri);
      return _json(account, 201);
    } catch (e) {
      return _json({
        'error': e is StateError ? e.message : e.toString()
      }, 400);
    }
  });

  router.get('/v1/google/accounts', (Request request) async {
    if (google == null) {
      return _json({'error': 'google auth not wired in this daemon'}, 500);
    }
    return _json({'accounts': google.accounts()});
  });

  router.post('/v1/google/revoke', (Request request) async {
    if (google == null) {
      return _json({'error': 'google auth not wired in this daemon'}, 500);
    }
    final raw = await request.readAsString();
    Map<String, dynamic> body;
    try {
      body = raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return _json({'error': 'body must be JSON'}, 400);
    }
    final email = body['email']?.toString() ?? '';
    if (email.isEmpty) {
      return _json({'error': 'email is required'}, 400);
    }
    return _json({'removed': await google.remove(email)});
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
      vaultDir: stateDirPath(),
      jobStore: FileJobStore('${stateDirPath()}/jobs.json'),
      seenStore: SeenStore('${stateDirPath()}/seen.json'),
      google: GoogleAuth(vaultDir: stateDirPath()));

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
