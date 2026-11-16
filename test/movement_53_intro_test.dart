import 'dart:convert';
import 'dart:io';

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

/// Movement 53 — the first-run intro: ONE request generates every message
/// (VPS when configured, reference set otherwise) and the bubbles then land
/// one after another with a real-person entrance animation.

class _BlockedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient();
}

class _BlockedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in widget tests');
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _BlockedOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  test('intro falls back to the reference set without a VPS', () async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(prefs: await SharedPreferences.getInstance(),
        store: InMemorySecureStore());
    final intro = await Locator.intro.fetchIntro(name: 'Shyan');
    expect(intro.length, greaterThanOrEqualTo(3));
    expect(intro.first, contains('Shyan'));
  });

  test('intro arrives from ONE VPS request as an array', () async {
    final bodies = <String>[];
    final paths = <String>[];
    final stub = MockClient((request) async {
      paths.add(request.url.path);
      bodies.add(request.body);
      return http.Response(
          jsonEncode({
            'messages': ['Bubble one', 'Bubble two', 'Bubble three'],
          }),
          200,
          headers: {'content-type': 'application/json'});
    });
    SharedPreferences.setMockInitialValues({'vps.url': 'https://vps.example'});
    Locator.reset();
    Locator.bind(prefs: await SharedPreferences.getInstance(),
        store: InMemorySecureStore()..write('vps.token', 'tok'),
        httpClient: stub);
    final intro = await Locator.intro.fetchIntro(name: 'Shyan');
    expect(intro, ['Bubble one', 'Bubble two', 'Bubble three']);
    expect(paths, ['/v1/onboarding/intro'],
        reason: 'ONE request generated the whole set');
    final sent = jsonDecode(bodies.single) as Map<String, dynamic>;
    expect(sent['name'], 'Shyan');
  });

  testWidgets('the intro plays as separate animated bubbles on first run',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore()..write('apikey.openai', 'sk-test'),
      chat: ChatService(
        vault: KeyVault(InMemorySecureStore()..write('apikey.openai', 'sk-test')),
        client: LlmClient(client: MockClient((request) async => http.Response(
              jsonEncode({
                'choices': [
                  {'message': {'content': 'mock reply'}},
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            ))),
      ),
    );
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-chat')));
    await tester.pumpAndSettle();

    // The staggered sequence runs on Future.delayed timers — advance the
    // fake clock through every beat, then let the entrance animations end.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 900));
    }
    await tester.pumpAndSettle();

    expect(find.textContaining('Gork.', findRichText: true), findsOneWidget,
        reason: 'the first bubble landed');
    expect(find.byType(SelectionArea), findsWidgets,
        reason: 'intro bubbles are selectable, like real AI replies');
    expect(tester.state<ChatScreenState>(find.byType(ChatScreen).first)
        .messageCount, greaterThanOrEqualTo(3),
        reason: 'the visible state holds every intro message');
    expect(find.byType(FadeTransition), findsWidgets,
        reason: 'bubbles entered with the real-person animation');

    final global = Locator.history.byId(kGlobalChatId);
    expect(global, isNotNull);
    expect(global!.messages.length, greaterThanOrEqualTo(3),
        reason: 'every intro bubble persisted as its own message');
    expect(
        global.messages.every((m) => m.role == 'assistant'),
        isTrue,
        reason: 'the intro messages are separate assistant messages');
    expect(Locator.prefs.getBool('intro.done'), isTrue,
        reason: 'the sequence never replays');
  });
}
