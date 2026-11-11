import 'package:gork/providers/providers.dart';

import 'chat_service.dart';
import 'llm_client.dart';
import 'tasks_store.dart';

/// Runs scheduled tasks: every tick, all due tasks execute their prompt via
/// chat() and notify the result. While the app is dead, the companion daemon
/// (deployed later on the user's VPS) takes over — that is the 24/7 story.
class Scheduler {
  final TasksStore _tasks;
  final ChatService _chat;
  final Future<void> Function(String title, String body)? onNotify;

  Scheduler(this._tasks, {required ChatService chat, this.onNotify})
      : _chat = chat;

  List<ScheduledTask> dueTasks(DateTime now) {
    final all = _tasks.all();
    return [for (final t in all) if (isTaskDue(t, now)) t];
  }

  /// Execute one task now. Returns null on success, error text otherwise.
  Future<String?> runTask(ScheduledTask task, DateTime now) async {
    String resultText;
    try {
      final reply = await _chat.chat(
        providerId: await _firstProviderWithKey(),
        messages: [
          const ChatMessage(
              'system', 'You are gork, running a scheduled task. Be brief.'),
          ChatMessage('user', task.prompt),
        ],
        maxTokens: 300,
      );
      resultText = reply.content;
    } catch (e) {
      resultText = 'Task failed: $e';
      await _tasks.save(task.copyWith(lastRun: now.millisecondsSinceEpoch));
      return resultText;
    }

    await _tasks.save(task.copyWith(lastRun: now.millisecondsSinceEpoch));
    await onNotify?.call('gork: ${task.title}', _truncate(resultText));
    return null;
  }

  /// Run everything that is due. Returns how many tasks ran.
  Future<int> tick(DateTime now) async {
    final due = dueTasks(now);
    for (final task in due) {
      await runTask(task, now);
    }
    return due.length;
  }

  Future<String> _firstProviderWithKey() async {
    for (final p in kProviders) {
      if (await _chat.hasKey(p.id)) return p.id;
    }
    throw const LlmException(
        'No provider key saved. Add one in Providers first.');
  }

  String _truncate(String text) =>
      text.length <= 300 ? text : '${text.substring(0, 300)}…';
}
