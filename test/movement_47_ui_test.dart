import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/chat_screen.dart';
import 'package:gork/screens/updates_screen.dart';
import 'package:gork/services/chat_service.dart';
import 'package:gork/services/history_store.dart';
import 'package:gork/services/llm_client.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/update_service.dart';
import 'package:gork/widgets/markdown_view.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 47 — AI responses are selectable (assistant markdown lives in a
/// SelectionArea), and the Updates page renders release notes as FULL
/// markdown with the action button on top.
void main() {
  testWidgets('assistant replies are selectable', (tester) async {
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
      httpClient: fakeHttp,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await Locator.history.save(Conversation(
      id: 'sel1',
      title: 'Selection',
      providerId: 'openai',
      updatedAt: now,
      messages: [
        ChatTurn('user', 'hello', time: now),
        ChatTurn('assistant', '## Heading\n- one\n- two\ncopy me',
            time: now + 60000),
      ],
    ));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ChatScreen(conversationId: 'sel1')),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea, skipOffstage: false), findsWidgets,
        reason: 'the assistant bubble is wrapped in a SelectionArea so its '
            'markdown can be copied');
  });

  group('updates page', () {
    const notes = '## v1.5.0 notes\n\n- first line\n- second line\n'
        '- third line\n- fourth line\n- fifth line\n- sixth line\n'
        '- seventh line\n- eighth line\n- ninth line deep inside the body\n\n'
        'A closing paragraph that must remain visible.';
    Future<http.Response> releases(Object body) async =>
        http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'});

    Future<void> openAvailable(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'onboarding.done': true});
      final svc = UpdateService(
        client: MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            return releases([
              {
                'tag_name': 'v1.5.0',
                'name': 'gork v1.5.0',
                'body': notes,
                'prerelease': false,
                'draft': false,
                'assets': [
                  {
                    'name': 'gork-v1.5.0-release.apk',
                    'browser_download_url': 'https://example.invalid/a.apk',
                    'size': 11,
                  }
                ],
              }
            ]);
          }
          return http.Response('offline', 500);
        }),
        currentVersion: '1.4.2',
        downloadDir: '/tmp/gork-m47-updates',
      );
      await tester.pumpWidget(MaterialApp(
        home: UpdatesScreen(
          currentVersion: '1.4.2',
          service: svc,
          downloadDir: '/tmp/gork-m47-updates',
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('updates-check')));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('release notes render as markdown, in full', (tester) async {
      await openAvailable(tester);

      expect(find.byType(MarkdownView), findsOneWidget,
          reason: 'the notes are markdown, not a plain truncated Text');
      expect(find.textContaining('ninth line deep inside', findRichText: true),
          findsOneWidget,
          reason: 'the notes are NOT clipped at eight lines');
      expect(find.textContaining('closing paragraph', findRichText: true),
          findsOneWidget,
          reason: 'the content is shown fully');
    });

    testWidgets('the download button sits above the notes', (tester) async {
      await openAvailable(tester);

      final buttonTop =
          tester.getTopLeft(find.byKey(const ValueKey('updates-download'))).dy;
      final notesTop = tester.getTopLeft(find.byType(MarkdownView)).dy;
      expect(buttonTop, lessThan(notesTop),
          reason: 'the action button comes first, content below');
    });
  });
}
