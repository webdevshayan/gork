import 'dart:convert';
import 'dart:io';

import 'package:gork_daemon/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

  group('EnvLlmCaller — scheduled LLM calls', () {
    test('the request carries an explicit max_tokens ceiling', () async {
      Map<String, dynamic>? capturedBody;
      final caller = EnvLlmCaller(MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': 'done'}}
            ],
          }),
          200,
        );
      }), {
        'GORK_API_KEY': 'k',
      });

      final out = await caller.call('summarize');
      expect(out, 'done');
      expect(capturedBody!['max_tokens'], 1024);
    });

    test('a 402 answer surfaces as a human line, not a JSON dump',
        () async {
      const message = 'This request requires more credits, or fewer '
          'max_tokens. You requested up to 65536 tokens, but can only '
          'afford 64911.';
      final body = jsonEncode({
        'error': {
          'message': message,
          'code': 402,
          'metadata': {
            'remedy_hint':
                'Add credits at https://openrouter.ai/settings/credits.',
            'previous_errors': [
              for (var i = 0; i < 8; i++) {'code': 402, 'message': message},
            ],
          },
        },
      });
      final caller = EnvLlmCaller(
          MockClient((request) async => http.Response(body, 402)),
          {'GORK_API_KEY': 'k'});

      await expectLater(
        caller.call('summarize'),
        throwsA(isA<HttpException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('more credits'),
            contains('openrouter.ai/settings/credits'),
            isNot(contains('previous_errors')),
          ),
        )),
      );
    });
  });
}
