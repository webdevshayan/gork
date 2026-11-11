import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/screens/chat_screen.dart';
import 'package:gork/services/chat_service.dart';
import 'package:gork/services/history_store.dart';
import 'package:gork/services/llm_client.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';

void main() {
  Future<void> bindServices({required bool withKey}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = InMemorySecureStore();
    if (withKey) await store.write('apikey.openai', 'sk-test');
    final fakeHttp = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': {'content': 'mock reply'}}
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
      chat: ChatService(vault: KeyVault(store), client: LlmClient(client: fakeHttp)),
    );
  }

  testWidgets('sends a message and shows the assistant reply', (tester) async {
    await bindServices(withKey: true);
    await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello gork');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    // One match in the bubble, one in the app bar (title = first message).
    expect(find.text('hello gork'), findsNWidgets(2));
    expect(find.text('mock reply'), findsOneWidget);
    expect(find.textContaining('OpenAI'), findsWidgets);

    // History persisted.
    final conversation = Locator.history.latest!;
    expect(conversation.providerId, 'openai');
    expect(conversation.messages.first.role, 'user');
    expect(conversation.messages.first.content, 'hello gork');
    expect(conversation.messages.last.content, 'mock reply');
    expect(conversation.title, 'hello gork');
  });

  testWidgets('without a key shows guidance instead of sending', (tester) async {
    await bindServices(withKey: false);
    await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No provider key yet'), findsOneWidget);
  });

  testWidgets('provider errors surface as text, not crashes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = InMemorySecureStore();
    await store.write('apikey.openai', 'sk-bad');
    final failingHttp = MockClient((request) async {
      return http.Response('{"error":"invalid api key"}', 401);
    });
    Locator.reset();
    Locator.bind(
      prefs: prefs,
      store: store,
      chat: ChatService(
        vault: KeyVault(store),
        client: LlmClient(client: failingHttp),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('LlmException 401'), findsOneWidget);
    // The user message stays visible for context.
    // One in the bubble, one in the app bar title.
    expect(find.text('hi'), findsNWidgets(2));
  });

  testWidgets('restores the latest conversation on open', (tester) async {
    await bindServices(withKey: true);
    // Pre-seed history.
    await Locator.history.save(
      const Conversation(
        id: 'seed',
        title: 'Old chat',
        providerId: 'openai',
        updatedAt: 42,
        messages: [ChatTurn('user', 'old message')],
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Old chat'), findsOneWidget);
    expect(find.text('old message'), findsOneWidget);
  });
}
