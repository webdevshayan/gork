import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:gork/services/chat_service.dart';
import 'package:gork/services/llm_client.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/screens/providers_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  setUp(() {
    Locator.reset();
    final store = InMemorySecureStore();
    final fakeHttp = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': {'content': 'ok'}}
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    Locator.bind(
      store: store,
      chat: ChatService(
        vault: KeyVault(store),
        client: LlmClient(client: fakeHttp),
      ),
    );
  });

  testWidgets('lists all five providers', (tester) async {
    await tester.pumpWidget(_wrap(const ProvidersScreen()));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('OpenRouter'), findsOneWidget);
    expect(find.text('Gemini'), findsOneWidget);
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text('Custom (OpenAI-compatible)'), findsOneWidget);
    expect(find.text('No key yet'), findsNWidgets(5));
  });

  testWidgets('saving a key stores it on-device and updates status',
      (tester) async {
    await tester.pumpWidget(_wrap(const ProvidersScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OpenAI'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'sk-secret-123');
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();

    expect(await Locator.store.read('apikey.openai'), 'sk-secret-123');
    expect(find.text('Key saved on this device'), findsOneWidget);
    expect(find.text('No key yet'), findsNWidgets(4));
  });

  testWidgets('test connection reports success with a working key',
      (tester) async {
    await tester.pumpWidget(_wrap(const ProvidersScreen()));
    await tester.pumpAndSettle();

    // Save the key first (sheet closes), then reopen and test.
    await tester.tap(find.text('OpenRouter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'sk-or-key');
    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('OpenRouter'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Test connection'));
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Connection OK'), findsOneWidget);
  });

  testWidgets('test connection reports failure without a key', (tester) async {
    final store = InMemorySecureStore();
    Locator.reset();
    Locator.bind(
      store: store,
      chat: ChatService(
        vault: KeyVault(store),
        client: LlmClient(client: MockClient((r) async => http.Response('{}', 500))),
      ),
    );

    await tester.pumpWidget(_wrap(const ProvidersScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gemini'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed'), findsOneWidget);
  });
}
