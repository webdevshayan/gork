import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/screens/chat_screen.dart';
import 'package:gork/services/chat_service.dart';
import 'package:gork/services/llm_client.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/outbox.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 48 — requests live on the VPS: a sent message survives device
/// death and app inactivity, is processed server-side, and nothing the app
/// does can cancel it.
void main() {
  // A tiny fake of gork_server.py: jobs are queued, the reply materializes
  // only when the test flips [jobDone].
  late bool jobDone;
  late List<String> posts;
  late http.Client fakeClient;

  Future<void> bindAll({
    String vpsUrl = 'http://vps.test',
    bool withVps = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'onboarding.done': true,
      if (withVps) 'vps.url': vpsUrl,
    });
    Locator.reset();
    final prefs = await SharedPreferences.getInstance();
    jobDone = false;
    posts = [];
    fakeClient = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path == '/v1/messages') {
        posts.add(request.body);
        return http.Response(jsonEncode({'id': 'job1', 'status': 'queued'}),
            201, headers: {'content-type': 'application/json'});
      }
      if (request.method == 'GET' && path == '/v1/jobs/job1') {
        return http.Response(
          jsonEncode({
            'id': 'job1',
            'status': jobDone ? 'done' : 'running',
            'result': jobDone ? {'reply': 'reply forged on the VPS'} : null,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' &&
          path == '/v1/conversations/c1/messages') {
        return http.Response(
          jsonEncode({
            'conversation': 'c1',
            'messages': [
              {'role': 'user', 'content': 'hello'},
              if (jobDone)
                {'role': 'assistant', 'content': 'reply forged on the VPS'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('offline', 500);
    });
    Locator.bind(
      prefs: prefs,
      store: InMemorySecureStore()..write('apikey.openai', 'sk-test'),
      chat: ChatService(
        vault: KeyVault(InMemorySecureStore()..write('apikey.openai', 'sk-test')),
        client: LlmClient(client: fakeClient),
      ),
      httpClient: fakeClient,
    );
  }

  testWidgets('a sent message is enqueued on the VPS, not sent from the app',
      (tester) async {
    await bindAll();
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-chat')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('input-bar')), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-circle')));
    await tester.pumpAndSettle();

    expect(posts, hasLength(1),
        reason: 'the message was POSTed to the VPS');
    expect(jsonDecode(posts.first)['text'], 'hello');
    expect(find.text('hello'), findsOneWidget,
        reason: 'the user message lands in the thread immediately');
    expect(find.textContaining('No provider key yet'), findsNothing,
        reason: 'the VPS path does not need a device-side provider key');
    Locator.outbox.dispose();
  });

  testWidgets('the reply arrives from the VPS while the screen stays open',
      (tester) async {
    await bindAll();
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-chat')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('input-bar')), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-circle')));
    await tester.pumpAndSettle();

    expect(find.textContaining('reply forged'), findsNothing,
        reason: 'the job is still running server-side');

    jobDone = true; // the VPS finished the work
    await tester.pump(const Duration(seconds: 3)); // poll tick
    await tester.pumpAndSettle();
    expect(find.textContaining('reply forged on the VPS', findRichText: true),
        findsOneWidget,
        reason: 'the server reply merges into the thread');
    await tester.pumpWidget(const SizedBox.shrink());
    Locator.outbox.dispose();
  });

  testWidgets('device death: the screen dies mid-request, the reply survives',
      (tester) async {
    await bindAll();
    final screenKey = GlobalKey<ChatScreenState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatScreen(key: screenKey, conversationId: 'c1'),
      ),
    ));
    await tester.pumpAndSettle();
    await screenKey.currentState!.send('hello');
    await tester.pumpAndSettle();
    expect(posts, hasLength(1), reason: 'the VPS accepted the job');

    jobDone = true; // the job finishes AFTER the screen is gone
    // The screen is destroyed (device death / app inactive) — polling stops.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    // The app comes back: the thread reopens and syncs from the server.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ChatScreen(conversationId: 'c1')),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('reply forged on the VPS', findRichText: true),
        findsOneWidget,
        reason: 'the reply was processed on the VPS and merged on return — '
            'nothing was cancelled by the screen dying');
    await tester.pumpWidget(const SizedBox.shrink());
    Locator.outbox.dispose();
  });

  testWidgets('offline at send time: the outbox retries until the VPS takes it',
      (tester) async {
    await bindAll();
    final outbox = Locator.outbox;
    // The VPS is unreachable at enqueue time, then recovers.
    var attempts = 0;
    Locator.bind(httpClient: MockClient((r) async {
      attempts++;
      if (attempts < 2) return http.Response('unreachable', 503);
      return http.Response(jsonEncode({'id': 'job1', 'status': 'queued'}), 201,
          headers: {'content-type': 'application/json'});
    }));

    final entry = await outbox.enqueue('c1', 'queued while offline',
        awaitAcceptance: true);
    expect(entry.status, OutboxStatus.pending,
        reason: 'an unreachable VPS never cancels the message');
    expect(outbox.pending(), hasLength(1));

    await outbox.flush();
    expect(outbox.pending(), isEmpty,
        reason: 'the retry delivers it once the VPS is reachable');
    // ignore: avoid_print
    outbox.dispose(); // body-level: the binding invariant runs pre-teardown
  });
}
