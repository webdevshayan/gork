import 'dart:io';

import 'package:gork_daemon/scheduler.dart';
import 'package:test/test.dart';

void main() {
  test('isDue mirrors the app rules', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1000000);

    final never = const Task(
        id: '1', title: 'T', prompt: 'p', repeatMinutes: 60, enabled: true);
    expect(isDue(never, now), isTrue);

    final disabled = const Task(
        id: '2', title: 'T', prompt: 'p', repeatMinutes: 60, enabled: false);
    expect(isDue(disabled, now), isFalse);

    final ran = Task(
        id: '3',
        title: 'T',
        prompt: 'p',
        repeatMinutes: 30,
        enabled: true,
        lastRun: now.millisecondsSinceEpoch);
    expect(isDue(ran, now.add(const Duration(minutes: 29))), isFalse);
    expect(isDue(ran, now.add(const Duration(minutes: 30))), isTrue);
  });

  test('FileTaskStore persists across instances', () {
    final path = 'test/tmp_tasks.json';
    final store = FileTaskStore(path);
    try {
      store.save(const Task(
          id: 'a', title: 'News', prompt: 'summarize', repeatMinutes: 60, enabled: true));
      expect(store.all().single.id, 'a');

      final reopened = FileTaskStore(path);
      expect(reopened.all().single.title, 'News');

      reopened.markRan('a', DateTime.fromMillisecondsSinceEpoch(999));
      expect(FileTaskStore(path).all().single.lastRun, 999);

      reopened.delete('a');
      expect(FileTaskStore(path).all(), isEmpty);
    } finally {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    }
  });
}
