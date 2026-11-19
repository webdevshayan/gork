import 'dart:io';

import 'package:test/test.dart';

import 'package:gork_daemon/job_store.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gork-jobstore-test');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('jobs persist to jobs.json and survive a "restart" (new store, same '
      'file) — an accepted message is never lost', () async {
    final path = '${tmp.path}/jobs.json';
    final store = FileJobStore(path);
    await store.save(AgentJob(
      id: 'job-1',
      conversationId: 'c1',
      text: 'summarize my inbox',
      status: 'queued',
      createdAt: 1000,
    ));

    // The daemon restarts: a NEW store on the SAME file.
    final restarted = FileJobStore(path);
    final jobs = restarted.all();
    expect(jobs, hasLength(1));
    expect(jobs.first.status, 'queued');
    expect(jobs.first.text, 'summarize my inbox');
    expect(jobs.first.conversationId, 'c1');
  });

  test('save() updates in place — queued -> running -> done keeps one entry',
      () async {
    final store = FileJobStore('${tmp.path}/jobs.json');
    const job = AgentJob(
      id: 'job-2',
      conversationId: 'c1',
      text: 'hello',
      status: 'queued',
      createdAt: 5,
    );
    await store.save(job);
    await store.save(job.copyWith(status: 'running'));
    await store.save(
        job.copyWith(status: 'done', reply: 'hi there', finishedAt: 9));
    expect(store.all(), hasLength(1));
    expect(store.all().first.status, 'done');
    expect(store.all().first.reply, 'hi there');
    expect(store.all().first.finishedAt, 9);
  });

  test('a corrupt jobs.json answers empty instead of taking the daemon down',
      () {
    File('${tmp.path}/jobs.json').writeAsStringSync('{not json at all');
    expect(FileJobStore('${tmp.path}/jobs.json').all(), isEmpty);
  });

  test('jobNotificationPreview: the first lines, clipped, for the lock '
      'screen', () {
    expect(jobNotificationPreview('one\ntwo\nthree\nfour'),
        'one\ntwo\nthree');
    expect(jobNotificationPreview('   '), '(empty reply)');
    final long = jobNotificationPreview('a' * 500);
    expect(long.length, 221); // 220 chars + ellipsis
    expect(long.endsWith('…'), isTrue);
  });
}
