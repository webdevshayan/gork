import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/integrations_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'login': 'tester'}), 200);
      }),
    );
  });

  testWidgets('lists all six integrations', (tester) async {
    // Tall viewport: the connections list is lazy and Google sits first.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ConnectionsScreen()));
    await tester.pumpAndSettle();

    for (final name in ['GitHub', 'Slack', 'Strava', 'Spotify', 'Gmail', 'PayPal']) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('saving a token marks the integration connected', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ConnectionsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ghp_test_token');
    await tester.tap(find.text('Connect').last);
    await tester.pumpAndSettle();

    // Movement 69 — the connected state is a quiet green check on the row.
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('test connection reports success for a good token',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ConnectionsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ghp_test_token');
    await tester.tap(find.text('Connect').last);
    await tester.pumpAndSettle();

    // verification happens inside the Connect action: the sheet closes on
    // success and the token is stored.
    expect(find.byType(TextField), findsNothing);
    expect((await Locator.integrations.vault.token('github')), 'ghp_test_token');
  });
}
