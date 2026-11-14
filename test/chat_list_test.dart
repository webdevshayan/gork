import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/chat_screen.dart';
import 'package:gork/services/chat_service.dart';
import 'package:gork/services/history_store.dart';
import 'package:gork/services/llm_client.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 2026-11-01 09:00 and 2026-11-03 17:40 local — two different days, so the
  // thread must render two pinned date groups.
  final day1 = DateTime(2026, 11, 1, 9, 0);
  final day2 = DateTime(2026, 11, 3, 17, 40);
  final day1Ms = day1.millisecondsSinceEpoch;
  final day2Ms = day2.millisecondsSinceEpoch;

  Future<void> bindServices() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = InMemorySecureStore();
    await store.write('apikey.openai', 'sk-test');
    final fakeHttp = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': {'content': 'mock reply'}},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    Locator.reset();
    Locator.bind(
      prefs: prefs,
      store: store,
      chat: ChatService(
        vault: KeyVault(store),
        client: LlmClient(client: fakeHttp),
      ),
    );
  }

  Future<void> seedThread() async {
    await Locator.history.save(Conversation(
      id: 't1',
      title: 'Trip',
      providerId: 'openai',
      updatedAt: day2Ms,
      messages: [
        ChatTurn('user', 'hello on day one', time: day1Ms),
        ChatTurn('assistant', 'hi there', time: day1Ms + 60000),
        ChatTurn('user', 'hello on day two', time: day2Ms),
        ChatTurn('assistant', 'welcome back', time: day2Ms + 60000),
      ],
    ));
  }

  Future<void> pumpThread(WidgetTester tester) async {
    await bindServices();
    await seedThread();
    await tester.pumpWidget(const MaterialApp(
      home: ChatScreen(conversationId: 't1'),
    ));
  }

  testWidgets('answered user bubbles carry no Read receipts', (tester) async {
    await pumpThread(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Read'), findsNothing,
        reason: 'the •••• Read receipts are gone — timestamps replace them');
  });

  testWidgets('every bubble shows a time-only stamp', (tester) async {
    await pumpThread(tester);
    await tester.pumpAndSettle();

    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('9:01 AM'), findsOneWidget);
    expect(find.text('5:40 PM'), findsOneWidget);
    expect(find.text('5:41 PM'), findsOneWidget);
  });

  testWidgets('date badges are sticky pinned headers, one per day',
      (tester) async {
    await pumpThread(tester);
    await tester.pumpAndSettle();

    // Two days in the thread → two sticky groups (WhatsApp-style labels).
    expect(find.byType(PinnedHeaderSliver), findsNWidgets(2));
    expect(find.text('1 November 2026'), findsOneWidget);
    expect(find.text('3 November 2026'), findsOneWidget);
  });

  testWidgets('history renders on the first frame — no placeholder flash',
      (tester) async {
    await bindServices();
    // A provider check that stays pending for 10s: with the old ordering
    // (await hasKey BEFORE the history load) the first frames show the
    // seeded intro placeholders — the exact flash from the screenshots.
    final slowChat = _SlowKeyChat(
      Locator.chat,
      delay: const Duration(seconds: 10),
    );
    // Rebind with the SAME prefs/store (reset keeps no references) so the
    // seeded thread is still visible to the rebuilt HistoryStore.
    final samePrefs = Locator.prefs;
    final sameStore = Locator.store;
    Locator.reset();
    Locator.bind(prefs: samePrefs, store: sameStore, chat: slowChat);
    await seedThread();
    await tester.pumpWidget(const MaterialApp(
      home: ChatScreen(conversationId: 't1'),
    ));
    // ONE pump — the very first frame must already show the real thread.
    await tester.pump();

    expect(find.text('hello on day one'), findsOneWidget,
        reason: 'the thread must preload synchronously; the intro '
            'placeholders must never flash before real history');

    // Flush the slow hasKey so the test ends without a pending timer.
    await tester.pump(const Duration(seconds: 11));
  });
}

/// ChatService whose hasKey deliberately hangs — forces the slow-provider
/// path so the preload test proves the ordering, not mock speed.
class _SlowKeyChat implements ChatService {
  _SlowKeyChat(this._inner, {required this.delay});

  final ChatService _inner;
  final Duration delay;

  @override
  Future<bool> hasKey(String providerId) =>
      Future<bool>.delayed(delay, () => _inner.hasKey(providerId));

  @override
  Future<LlmReply> chat({
    required String providerId,
    required List<ChatMessage> messages,
    String? model,
    String? baseURL,
    String? defaultModel,
    List<ToolDef>? tools,
    int maxTokens = 1024,
  }) =>
      _inner.chat(
        providerId: providerId,
        messages: messages,
        model: model,
        baseURL: baseURL,
        defaultModel: defaultModel,
        tools: tools,
        maxTokens: maxTokens,
      );

  @override
  Future<void> clearKey(String providerId) => _inner.clearKey(providerId);

  @override
  Future<void> saveKey(String providerId, String apiKey) =>
      _inner.saveKey(providerId, apiKey);

  @override
  Future<String?> testConnection({
    required String providerId,
    String? model,
    String? baseURL,
    String? defaultModel,
  }) =>
      _inner.testConnection(
        providerId: providerId,
        model: model,
        baseURL: baseURL,
        defaultModel: defaultModel,
      );
}
