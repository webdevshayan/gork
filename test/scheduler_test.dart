import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/services/chat_service.dart';
import 'package:gork/services/llm_client.dart';
import 'package:gork/services/scheduler.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/tasks_store.dart';

Scheduler _makeScheduler(TasksStore tasks, List<String> notifications) {
  final store = InMemorySecureStore()..write('apikey.openai', 'sk-test');
  final fakeHttp = MockClient((request) async {
    return http.Response(
      jsonEncode({
        'choices': [
          {'message': {'content': 'task result text'}}
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  final chat = ChatService(vault: KeyVault(store), client: LlmClient(client: fakeHttp));
  return Scheduler(tasks,
      chat: chat,
      onNotify: (title, body) async => notifications.add('$title|$body'));
}

void main() {
  test('tick runs only due tasks and notifies', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tasks = TasksStore(prefs);

    final now = DateTime.fromMillisecondsSinceEpoch(1000000);

    const due = ScheduledTask(
        id: 'due1', title: 'Morning news', prompt: 'give me news', repeatMinutes: 60, enabled: true, createdAt: 0);
    final notDue = ScheduledTask(
        id: 'notdue',
        title: 'Slow one',
        prompt: 'p',
        repeatMinutes: 60,
        enabled: true,
        createdAt: 0,
        lastRun: now.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch);
    const disabled = ScheduledTask(
        id: 'disabled', title: 'Off', prompt: 'p', repeatMinutes: 60, enabled: false, createdAt: 0);

    await tasks.save(due);
    await tasks.save(notDue);
    await tasks.save(disabled);

    final notifications = <String>[];
    final scheduler = _makeScheduler(tasks, notifications);

    final ran = await scheduler.tick(now);
    expect(ran, 1);
    expect(notifications.length, 1);
    expect(notifications.first, contains('Morning news'));
    expect(notifications.first, contains('task result text'));

    final updated = tasks.all().firstWhere((t) => t.id == 'due1');
    expect(updated.lastRun, now.millisecondsSinceEpoch);
    expect(scheduler.dueTasks(now), isEmpty);
  });

  test('runTask reports provider errors instead of throwing', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tasks = TasksStore(prefs);
    await tasks.save(const ScheduledTask(
        id: 't', title: 'X', prompt: 'p', repeatMinutes: 60, enabled: true, createdAt: 0));

    // No key saved anywhere -> chat throws; scheduler must catch.
    final scheduler = Scheduler(tasks,
        chat: ChatService(vault: KeyVault(InMemorySecureStore())),
        onNotify: (_, __) async {});
    final error = await scheduler.runTask(
        tasks.all().first, DateTime.fromMillisecondsSinceEpoch(1000000));
    expect(error, isNotNull);
    expect(error, contains('Task failed'));
    // lastRun still recorded so we do not hot-loop on failures.
    expect(tasks.all().first.lastRun, isNotNull);
  });
}
