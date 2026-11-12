import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/integrations_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  testWidgets('lists all six integrations', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IntegrationsScreen()));
    await tester.pumpAndSettle();

    for (final name in ['GitHub', 'Slack', 'Strava', 'Spotify', 'Gmail', 'PayPal']) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('saving a token marks the integration connected', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IntegrationsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ghp_test_token');
    await tester.tap(find.text('Save token'));
    await tester.pumpAndSettle();

    expect(find.text('Connected — token on this device'), findsOneWidget);
  });

  testWidgets('test connection reports success for a good token',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IntegrationsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ghp_test_token');
    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();

    expect(find.text('Connection OK — token works.'), findsOneWidget);
  });
}
