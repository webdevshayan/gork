import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/services/tasks_store.dart';

void main() {
  Future<TasksStore> make() async {
    SharedPreferences.setMockInitialValues({});
    return TasksStore(await SharedPreferences.getInstance());
  }

  test('isTaskDue: never run -> due; disabled -> not due', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000000);

    final never = ScheduledTask(
        id: '1', title: 'T', prompt: 'p', repeatMinutes: 60, enabled: true, createdAt: 0);
    expect(isTaskDue(never, now), isTrue);

    final disabled = ScheduledTask(
        id: '2', title: 'T', prompt: 'p', repeatMinutes: 60, enabled: false, createdAt: 0);
    expect(isTaskDue(disabled, now), isFalse);
  });

  test('isTaskDue: boundary at exactly repeatMinutes', () {
    final base = DateTime.fromMillisecondsSinceEpoch(1000000);
    final ran = ScheduledTask(
      id: '3',
      title: 'T',
      prompt: 'p',
      repeatMinutes: 30,
      enabled: true,
      createdAt: 0,
      lastRun: base.millisecondsSinceEpoch,
    );

    final after29 = base.add(const Duration(minutes: 29));
    final after30 = base.add(const Duration(minutes: 30));
    expect(isTaskDue(ran, after29), isFalse);
    expect(isTaskDue(ran, after30), isTrue);
  });

  test('store save/all/delete round-trip', () async {
    final store = await make();
    expect(store.all(), isEmpty);

    await store.save(const ScheduledTask(
        id: 'a', title: 'News', prompt: 'summarize', repeatMinutes: 60, enabled: true, createdAt: 1));
    await store.save(const ScheduledTask(
        id: 'b', title: 'Backup', prompt: 'check', repeatMinutes: 1440, enabled: false, createdAt: 2));

    expect(store.all().length, 2);

    final a = store.all().firstWhere((t) => t.id == 'a');
    await store.save(a.copyWith(lastRun: 123456));
    final updated = store.all().firstWhere((t) => t.id == 'a');
    expect(updated.lastRun, 123456);
    expect(updated.enabled, isTrue);

    await store.delete('a');
    expect(store.all().map((t) => t.id), ['b']);
  });
}
