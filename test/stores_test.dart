import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/services/history_store.dart';
import 'package:gork/services/memory_store.dart';

void main() {
  group('HistoryStore', () {
    Future<SharedPreferences> getPrefs() async {
      SharedPreferences.setMockInitialValues({});
      return SharedPreferences.getInstance();
    }

    test('save, load, latest, delete, clear', () async {
      final store = HistoryStore(await getPrefs());

      expect(store.all(), isEmpty);

      final c1 = Conversation(
        id: '1',
        title: 'First chat',
        providerId: 'openai',
        updatedAt: 100,
        messages: const [ChatTurn('user', 'hi'), ChatTurn('assistant', 'hello')],
      );
      await store.save(c1);

      final c2 = Conversation(
        id: '2',
        title: 'Second',
        providerId: 'gemini',
        updatedAt: 200,
        messages: const [ChatTurn('user', 'yo')],
      );
      await store.save(c2);

      expect(store.all().length, 2);
      expect(store.all().first.id, '2'); // newest first
      expect(store.latest!.id, '2');
      expect(store.byId('1')!.title, 'First chat');
      expect(store.byId('1')!.messages.first.content, 'hi');

      await store.delete('1');
      expect(store.all().length, 1);

      await store.clear();
      expect(store.all(), isEmpty);
    });

    test('json round-trip keeps roles and content', () async {
      final store = HistoryStore(await getPrefs());
      await store.save(Conversation(
        id: 'r1',
        title: 'Round trip',
        providerId: 'anthropic',
        updatedAt: 5,
        messages: const [
          ChatTurn('system', 'sys'),
          ChatTurn('user', 'u'),
          ChatTurn('assistant', 'a'),
        ],
      ));
      final loaded = store.byId('r1')!;
      expect(loaded.messages.map((m) => m.role).toList(),
          ['system', 'user', 'assistant']);
      expect(loaded.messages.last.content, 'a');
    });
  });

  group('MemoryStore', () {
    test('remember, dedupe, forget, systemPromptBlock', () async {
      SharedPreferences.setMockInitialValues({});
      final memory =
          MemoryStore(await SharedPreferences.getInstance());

      expect(memory.all(), isEmpty);
      expect(memory.systemPromptBlock(), '');

      await memory.remember('User likes tea');
      await memory.remember('User lives in Karachi');
      await memory.remember('User likes tea'); // dedupe

      expect(memory.all(), ['User likes tea', 'User lives in Karachi']);
      final block = memory.systemPromptBlock();
      expect(block, contains('- User likes tea'));
      expect(block, contains('- User lives in Karachi'));

      expect(await memory.forget('User likes tea'), isTrue);
      expect(await memory.forget('never said'), isFalse);
      expect(memory.all(), ['User lives in Karachi']);

      await memory.clear();
      expect(memory.all(), isEmpty);
    });
  });
}
