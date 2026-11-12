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
  final chatKey = GlobalKey<ChatScreenState>();

  Future<void> bindServices({required bool withKey}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = InMemorySecureStore();
    if (withKey) await store.write('apikey.openai', 'sk-test');
    final fakeHttp = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'mock reply'},
            },
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

  testWidgets(
    'AI bubbles are solid white, user bubbles are translucent glass',
    (tester) async {
      await bindServices(withKey: true);
      await tester.pumpWidget(MaterialApp(home: ChatScreen(key: chatKey)));
      await tester.pumpAndSettle();

      await chatKey.currentState!.send('hello gork');
      await tester.pumpAndSettle();

      final userFinder = find.text('hello gork').last;
      final Container userContainer = tester.firstWidget<Container>(
        find.ancestor(of: userFinder, matching: find.byType(Container)),
      );
      final BoxDecoration userDecoration =
          userContainer.decoration! as BoxDecoration;
      expect(userDecoration.color, Colors.white.withValues(alpha: 0.4));
      expect(userDecoration.borderRadius, BorderRadius.circular(32));

      final replyFinder = find.text('mock reply', findRichText: true);
      expect(replyFinder, findsOneWidget);
      final Container aiContainer = tester.firstWidget<Container>(
        find.ancestor(of: replyFinder, matching: find.byType(Container)),
      );
      final BoxDecoration aiDecoration =
          aiContainer.decoration! as BoxDecoration;
      expect(aiDecoration.color, Colors.white);
      expect(aiDecoration.borderRadius, BorderRadius.circular(32));
    },
  );

  testWidgets('sends a message and shows the assistant reply', (tester) async {
    await bindServices(withKey: true);
    await tester.pumpWidget(MaterialApp(home: ChatScreen(key: chatKey)));
    await tester.pumpAndSettle();

    await chatKey.currentState!.send('hello gork');
    await tester.pumpAndSettle();

    expect(find.text('hello gork'), findsOneWidget);
    expect(find.text('mock reply', findRichText: true), findsOneWidget);
    // History persisted.
    final conversation = Locator.history.latest!;
    expect(conversation.providerId, 'openai');
    expect(conversation.messages.first.role, 'user');
    expect(conversation.messages.first.content, 'hello gork');
    expect(conversation.messages.last.content, 'mock reply');
    expect(conversation.title, 'hello gork');
  });

  testWidgets('without a key shows guidance instead of sending', (
    tester,
  ) async {
    await bindServices(withKey: false);
    await tester.pumpWidget(MaterialApp(home: ChatScreen(key: chatKey)));
    await tester.pumpAndSettle();

    await chatKey.currentState!.send('hi');
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

    await tester.pumpWidget(MaterialApp(home: ChatScreen(key: chatKey)));
    await tester.pumpAndSettle();

    await chatKey.currentState!.send('hi');
    await tester.pumpAndSettle();

    expect(find.textContaining('LlmException 401'), findsOneWidget);
    // The user message stays visible for context.
    expect(find.text('hi'), findsOneWidget);
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

    await tester.pumpWidget(MaterialApp(home: ChatScreen(key: chatKey)));
    await tester.pumpAndSettle();

    expect(find.text('old message'), findsOneWidget);
  });

  testWidgets('empty chat shows the intro and the fanned preview stack',
      (tester) async {
    await bindServices(withKey: true);
    await tester.pumpWidget(MaterialApp(home: ChatScreen(key: chatKey)));
    await tester.pumpAndSettle();

    expect(find.text("Hey Shayan, I'm gork.", findRichText: true), findsOneWidget);
    expect(find.textContaining('gork PR #19', findRichText: true), findsOneWidget);
    // It sits below the fanned stack — scroll to it.
    await tester.scrollUntilVisible(
      find.textContaining('open source', findRichText: true),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('open source', findRichText: true), findsOneWidget);
  });

  testWidgets('search(null) leaves search mode; search(q) filters hits',
      (tester) async {
    await bindServices(withKey: true);
    await tester.pumpWidget(MaterialApp(home: ChatScreen(key: chatKey)));
    await tester.pumpAndSettle();

    await chatKey.currentState!.send('find the zip file');
    await tester.pumpAndSettle();

    chatKey.currentState!.search('zip');
    await tester.pumpAndSettle();
    expect(find.textContaining('find the zip file'), findsOneWidget);
    expect(find.textContaining('mock reply', findRichText: true), findsNothing);

    chatKey.currentState!.search('nothing-matches');
    await tester.pumpAndSettle();
    expect(find.text('No results for "nothing-matches".'), findsOneWidget);

    chatKey.currentState!.search(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('mock reply', findRichText: true), findsOneWidget,
        reason: 'search(null) leaves search mode and shows the full thread');
  });
}
