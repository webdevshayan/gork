import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/screens/chat_screen.dart';
import 'package:gork/services/chat_service.dart';
import 'package:gork/services/history_store.dart';
import 'package:gork/services/llm_client.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 45 — the Chat tab is a HOME: a list of recent threads (title,
/// snippet, time). Threads open as pushed full-screen screens; the input bar
/// composes a NEW thread.
void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
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
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore()..write('apikey.openai', 'sk-test'),
      chat: ChatService(
        vault: KeyVault(InMemorySecureStore()..write('apikey.openai', 'sk-test')),
        client: LlmClient(client: fakeHttp),
      ),
      httpClient: MockClient((request) async => http.Response('offline', 500)),
    );
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey('tab-$tab')));
    await tester.pumpAndSettle();
  }

  Future<void> seedThreads() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await Locator.history.save(Conversation(
      id: 'th1',
      title: 'Flight plans',
      providerId: 'openai',
      updatedAt: now,
      messages: [
        ChatTurn('user', 'book the trip to Karachi', time: now),
        ChatTurn('assistant', 'looking at fares', time: now + 60000),
      ],
    ));
    await Locator.history.save(Conversation(
      id: 'th2',
      title: 'Groceries',
      providerId: 'openai',
      updatedAt: now - 86400000,
      messages: [ChatTurn('user', 'milk and eggs', time: now - 86400000)],
    ));
  }

  testWidgets('the chat tab is a home list of recent threads',
      (tester) async {
    await pumpShell(tester);
    await seedThreads();
    // Rebuild so the freshly seeded threads appear.
    await tester.pumpAndSettle();
    await openTab(tester, 'chat');
    await tester.pumpAndSettle();

    expect(find.text('Flight plans'), findsOneWidget,
        reason: 'recent threads are listed by title');
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.byType(ChatScreen, skipOffstage: false), findsNothing,
        reason: 'the thread is NOT opened in the tab — the list is the home');
  });

  testWidgets('rows carry the last message as a snippet', (tester) async {
    await pumpShell(tester);
    await seedThreads();
    await tester.pumpAndSettle();
    await openTab(tester, 'chat');
    await tester.pumpAndSettle();

    expect(find.textContaining('looking at fares'), findsOneWidget,
        reason: 'the row previews the LAST message (the assistant reply)');
  });

  testWidgets('tapping a thread pushes it full-screen', (tester) async {
    await pumpShell(tester);
    await seedThreads();
    await tester.pumpAndSettle();
    await openTab(tester, 'chat');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('thread-th1')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget,
        reason: 'the thread opens as its own screen');
    expect(find.text('Flight plans'), findsWidgets,
        reason: 'the pushed screen carries the thread title');
    expect(find.text('book the trip to Karachi'), findsOneWidget,
        reason: 'the thread content is inside the pushed screen');
    expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget,
        reason: 'a chevron returns to the chat home');
  });

  testWidgets('sending from the home input bar opens a new thread',
      (tester) async {
    await pumpShell(tester);
    await openTab(tester, 'chat');
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('input-bar')), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-circle')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget,
        reason: 'composing opens a new thread screen');
    expect(find.text('hello'), findsOneWidget,
        reason: 'the message lands in the new thread');
  });

  testWidgets('an empty chat home keeps the seeded intro', (tester) async {
    await pumpShell(tester);
    await openTab(tester, 'chat');
    await tester.pumpAndSettle();

    expect(find.text("Hey Shayan, I'm gork.", findRichText: true),
        findsOneWidget);
    expect(find.textContaining('gork PR #19',
        skipOffstage: false, findRichText: true), findsOneWidget);
  });
}
