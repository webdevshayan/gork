import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:gork_daemon/scheduler.dart';

/// gork companion daemon.
///
/// Runs on the user's own VPS. Holds the schedule, calls the LLM on due
/// tasks, and pushes results to the phone via ntfy (no account needed).
/// The phone app connects over REST.
const int kDefaultPort = 8787;

TaskStore newTaskStore() => FileTaskStore('tasks.json');

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

Router buildRouter(Daemon daemon) {
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
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
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

  return router;
}

Future<void> main(List<String> args) async {
  final port =
      int.tryParse(Platform.environment['GORK_PORT'] ?? '') ?? kDefaultPort;

  final llm = EnvLlmCaller();
  final topic = Platform.environment['NTFY_TOPIC'];
  final notifier =
      topic == null || topic.isEmpty ? const NoopNotifier() : NtfyNotifier(topic);

  final daemon = Daemon(newTaskStore(), llm, notifier);
  final router = buildRouter(daemon);

  // 24/7 loop: check the schedule every minute.
  Timer.periodic(const Duration(minutes: 1), (_) async {
    try {
      await daemon.runDueTasks();
    } catch (e) {
      stdout.writeln('runDueTasks error: $e');
    }
  });

  final server = await shelf_io.serve(router, InternetAddress.anyIPv4, port);
  stdout.writeln(
      'gork daemon listening on http://${server.address.host}:${server.port}');
  stdout.writeln('LLM: ${llm.describe()} | ntfy: ${topic ?? 'disabled'}');
}
