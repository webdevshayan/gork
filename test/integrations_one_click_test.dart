import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/integrations_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Movement 34: connecting a service is ONE action. One tap on the card,
/// one paste, one Connect button — the button saves AND verifies AND closes.
/// And the connection is one-time setup: nothing expires behind the user's
/// back, it stays until they remove it.
void main() {
  setUp(() {
    Locator.reset();
    Locator.bind(
      store: InMemorySecureStore(),
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'login': 'tester'}), 200);
      }),
    );
  });

  testWidgets('one Connect action saves, verifies and closes', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IntegrationsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ghp_test_token');

    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Save token'), findsNothing);
    expect(find.text('Test'), findsNothing);

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    // sheet closed, card shows the connected state
    expect(find.text('Connect'), findsNothing);
    expect(find.textContaining('one-time setup'), findsOneWidget);
    expect(
        (await Locator.integrations.vault.token('github')), 'ghp_test_token');
  });

  testWidgets('a failed verification does not save the token', (tester) async {
    Locator.reset();
    Locator.bind(
      store: InMemorySecureStore(),
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'message': 'Bad credentials'}), 401);
      }),
    );
    await tester.pumpWidget(const MaterialApp(home: IntegrationsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'bad-token');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    // the sheet stays open and tells the truth
    expect(find.textContaining('Failed'), findsOneWidget);
    expect(await Locator.integrations.vault.token('github'), isNull);
  });

  testWidgets('connected state never talks about expiry', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IntegrationsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ghp_x');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('expire'), findsNothing);
    expect(find.textContaining('expires'), findsNothing);
    expect(find.textContaining('days left'), findsNothing);
  });
}
