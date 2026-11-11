import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/screens/inbox_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': 36.4,
              'weather_code': 0,
              'wind_speed_10m': 10.0,
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  test('heat suggestion appears above 35C and confirm-gates the action',
      () async {
    final actions = await Locator.inbox.suggestions();
    final heat = actions.firstWhere((a) => a.id == 'heat-reminder');
    expect(heat.requiresConfirm, isTrue);
    expect(heat.detail, contains('36'));
    expect(Locator.tasks.all(), isEmpty);
  });

  test('perform schedules a real task and marks the item done', () async {
    final actions = await Locator.inbox.suggestions();
    final heat = actions.firstWhere((a) => a.id == 'heat-reminder');

    final result = await Locator.inbox.perform(heat);
    expect(result, contains('scheduled'));

    final tasks = Locator.tasks.all();
    expect(tasks.single.title, 'Water break (heat)');
    expect(tasks.single.repeatMinutes, 120);

    // Done items no longer appear.
    expect(await Locator.inbox.suggestions(), isEmpty);
  });

  testWidgets('inbox screen shows suggestion and asks for confirmation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: InboxScreen()));
    await tester.pumpAndSettle();

    expect(find.text('It is very hot outside'), findsOneWidget);
    expect(find.text('Schedule reminder'), findsOneWidget);

    // Tap -> confirmation dialog appears (sensitive action).
    await tester.tap(find.text('Schedule reminder'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm action'), findsOneWidget);

    // Confirm -> task created, message shown.
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('scheduled'), findsOneWidget);
    expect(Locator.tasks.all().single.title, 'Water break (heat)');
    // The action card disappears (marked done).
    expect(find.text('It is very hot outside'), findsNothing);
  });
}
