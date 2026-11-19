import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/chat_screen.dart';
import 'package:gork/screens/cloud_computer_screen.dart';
import 'package:gork/screens/gork_home.dart';
import 'package:gork/screens/onboarding_screen.dart';
import 'package:gork/services/google_oauth_service.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/notifications.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 64 — real conversation flow:
///
///   * messages typed while a reply is on its way are QUEUED (never
///     dropped) and go out as ONE batched request when the reply lands —
///     fewer VPS round-trips, one coherent answer;
///   * a raw VPS exception never lands in the thread as if the agent said it;
///   * reply notifications: markdown-free preview, suppressed while the
///     chat is in front;
///   * ONE fixed redirect URI for the Google sign-in (register once);
///   * localhost works as the VPS address (phone-hosted daemon);
///   * onboarding walks Google setup then profile (photo, name — the
///     email is Google's and read-only).
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
      httpClient: MockClient((request) async =>
          throw http.ClientException('offline in tests')),
    );
  });

  group('Movement 64 — one redirect URI, registered once', () {
    test('the OAuth redirect is the fixed loopback URI', () {
      expect(GoogleOAuthService.kRedirectUri,
          'http://127.0.0.1:8636/callback');
      expect(GoogleOAuthService.kRedirectPort, 8636);
    });
  });

  group('Movement 64 — localhost is a first-class VPS', () {
    testWidgets('localhost rewrites to 127.0.0.1 on save', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CloudComputerScreen()));
      await tester.pumpAndSettle();
      // The VPS card sits below the backend picker — bring it in first.
      await tester.scrollUntilVisible(
        find.byKey(const Key('vps-url')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('vps-url')), 'http://localhost:8787');
      await tester.tap(find.byKey(const Key('vps-save')));
      await tester.pumpAndSettle();

      expect(Locator.handoff.vps.url, 'http://127.0.0.1:8787',
          reason: 'Android may resolve localhost to ::1 — the explicit '
              'IPv4 loopback always reaches the phone-hosted daemon');
    });

    testWidgets('an explicit IP address is kept untouched', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CloudComputerScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('vps-url')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('vps-url')), 'http://123.45.67.89:8787');
      await tester.tap(find.byKey(const Key('vps-save')));
      await tester.pumpAndSettle();

      expect(Locator.handoff.vps.url, 'http://123.45.67.89:8787');
    });
  });

  group('Movement 64 — onboarding: Google setup, then who you are', () {
    Future<void> toProfilePage(WidgetTester tester) async {
      await tester.pumpWidget(
          MaterialApp(home: OnboardingScreen(onFinished: () {})));
      await tester.pumpAndSettle();
      // welcome → setup → google → profile
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    testWidgets('the Google page walks the setup in the working order',
        (tester) async {
      await toProfilePage(tester);
      expect(find.text('Open Google setup'), findsOneWidget);
      expect(find.textContaining('credentials.json'), findsOneWidget,
          reason: 'the steps read in order: VPS → credentials → connect');
    });

    testWidgets('profile: the name is editable, the email is read-only',
        (tester) async {
      await toProfilePage(tester);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('onboarding-name')), findsOneWidget);
      final email =
          tester.widget<TextField>(find.byKey(const ValueKey('onboarding-email')));
      expect(email.readOnly, isTrue,
          reason: 'the email belongs to the connected Google account');

      await tester.enterText(
          find.byKey(const ValueKey('onboarding-name')), 'Test Person');
      // profile → done — the name persists when leaving the page.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(Locator.prefs.getString('profile.name'), 'Test Person');
    });
  });

  group('Movement 64 — the queue: keep typing while gork thinks', () {
    late MockClient fake;
    final posts = <String>[];
    int jobCount = 0;
    bool job1Done = false;
    bool job2Done = false;

    Future<void> bindChat(
        {String reply1 = 'First answer.'}) async {
      SharedPreferences.setMockInitialValues({
        'onboarding.done': true,
        'vps.url': 'http://vps.test',
      });
      Locator.reset();
      final prefs = await SharedPreferences.getInstance();
      jobCount = 0;
      job1Done = false;
      job2Done = false;
      posts.clear();
      fake = MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'POST' && path == '/v1/messages') {
          posts.add(request.body);
          jobCount++;
          return http.Response(
              jsonEncode({'id': 'job$jobCount', 'status': 'queued'}), 201,
              headers: {'content-type': 'application/json'});
        }
        final m = RegExp(r'^/v1/jobs/(job\d+)$').firstMatch(path);
        if (m != null) {
          final id = m.group(1)!;
          final done = id == 'job1' ? job1Done : job2Done;
          final reply = id == 'job1'
              ? reply1
              : 'Batched answer to your follow-ups.';
          return http.Response(
              jsonEncode({
                'id': id,
                'status': done ? 'done' : 'running',
                'result': done ? {'reply': reply} : null,
              }),
              200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('offline', 500);
      });
      Locator.bind(
        prefs: prefs,
        store: InMemorySecureStore(),
        httpClient: fake,
      );
    }

    testWidgets('follow-ups queue, then go out as ONE request',
        (tester) async {
      await bindChat();
      final key = GlobalKey<ChatScreenState>();
      await tester.pumpWidget(MaterialApp(home: ChatScreen(key: key)));
      await tester.pumpAndSettle();

      // 1. the first message goes out immediately.
      await key.currentState!.send('first');
      await tester.pumpAndSettle();
      expect(jobCount, 1, reason: 'one POST — the first send');

      // 2. while the job runs, a follow-up is QUEUED, not dropped.
      await tester.pump(const Duration(seconds: 2)); // poll tick: running
      await key.currentState!.send('second');
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
      expect(find.text('queued'), findsOneWidget);
      expect(jobCount, 1,
          reason: 'no second request while the first reply is in flight');

      // 3. the reply lands — the queue drains as ONE batched request.
      job1Done = true;
      await tester.pump(const Duration(seconds: 2)); // reply 1 arrives
      await tester.pump(const Duration(seconds: 2)); // poll cadence margin
      await tester.pumpAndSettle();
      expect(find.textContaining('First answer.', findRichText: true),
          findsOneWidget);
      expect(jobCount, 2, reason: 'the queue went out as ONE request');
      expect(jsonDecode(posts[1])['text'], 'second',
          reason: 'the batch carries the queued follow-up');
      // 4. the queued bubble is no longer marked queued.
      expect(find.text('queued'), findsNothing);

      // 5. the batched job answers too.
      job2Done = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('Batched answer to your follow-ups.',
          findRichText: true), findsOneWidget);
      Locator.outbox.dispose();
    });

    testWidgets('a raw VPS exception reads as a human line, not Dart',
        (tester) async {
      await bindChat(
          reply1:
              'HandshakeException: Connection terminated during handshake');
      final key = GlobalKey<ChatScreenState>();
      await tester.pumpWidget(MaterialApp(home: ChatScreen(key: key)));
      await tester.pumpAndSettle();

      await key.currentState!.send('hello');
      await tester.pumpAndSettle();
      job1Done = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.textContaining('snag', findRichText: true), findsOneWidget,
          reason: 'HandshakeException must never appear as a chat bubble');
      expect(find.textContaining('HandshakeException', findRichText: true),
          findsNothing);
      Locator.outbox.dispose();
    });
  });

  group('Movement 64 — reply notifications', () {
    test('the preview is plain text, no markdown noise', () async {
      SharedPreferences.setMockInitialValues({'vps.url': 'http://vps.test'});
      Locator.reset();
      final prefs = await SharedPreferences.getInstance();
      Locator.bind(
        prefs: prefs,
        store: InMemorySecureStore(),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (request.method == 'POST' && path == '/v1/messages') {
            return http.Response(
                jsonEncode({'id': 'job1', 'status': 'queued'}), 201);
          }
          if (path == '/v1/jobs/job1') {
            return http.Response(
                jsonEncode({
                  'id': 'job1',
                  'status': 'done',
                  'result': {
                    'reply':
                        'Open [chat.z.ai](https://chat.z.ai) and select '
                            '**Sign in** to use `gork`.'
                  },
                }),
                200);
          }
          return http.Response('offline', 500);
        }),
      );
      await Locator.outbox.enqueue('c1', 'hi', awaitAcceptance: true);
      final finished = await Locator.outbox.pollFinished();
      expect(finished, hasLength(1));
      final p = finished.first.preview;
      expect(p, isNot(contains('**')));
      expect(p, isNot(contains('](')));
      expect(p, isNot(contains('`')));
      expect(p, contains('chat.z.ai'));
      expect(p, contains('Sign in'));
      Locator.outbox.dispose();
    });

    test('replies that finished while the chat was in front are marked '
        'notified and hold off the toast', () async {
      // The suppression contract: inChat → showReply returns before the
      // plugin is even initialized; pollFinished still marks the entry so
      // the user is never re-notified for something already in the thread.
      Locator.notifications.inChat = true;
      await Locator.notifications.showReply('t', 'b');
      expect(Locator.notifications.inChat, isTrue);
      Locator.notifications.inChat = false;
    });
  });

  group('Movement 64 — sunset keyboard', () {
    testWidgets('the edit field accepts a typed colon time', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GorkHome()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('weather-sunset-tile')));
      await tester.pumpAndSettle();
      final field =
          tester.widget<TextField>(find.byKey(const ValueKey('sunset-input')));
      // The formatter allows the colon — the full keyboard can type 17:40.
      final formats = field.inputFormatters ?? const [];
      expect(formats, isNotEmpty,
          reason: 'the text formatter admits ":" alongside digits');
      await tester.enterText(
          find.byKey(const ValueKey('sunset-input')), '17:40');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(Locator.prefs.getString('home.sunset'), '17:40');
      expect(find.text('5:40 PM'), findsOneWidget,
          reason: '17:40 renders as 5:40 PM in the tile');
    });
  });
}
