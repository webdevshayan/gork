import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/screens/panels_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/panels_store.dart';
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
              'temperature_2m': 29.4,
              'weather_code': 0,
              'wind_speed_10m': 12.0,
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  test('weather panel is always seeded', () {
    final panels = Locator.panels.all();
    expect(panels.first.id, kWeatherPanel.id);
    expect(panels.first.source, PanelSource.weather);
  });

  test('manual panels persist and delete', () async {
    await Locator.panels.save(const PanelSpec(
        id: 'm1', title: 'Steps today', kind: PanelKind.metric,
        source: PanelSource.manual, manualValue: '8,432', createdAt: 1));

    final all = Locator.panels.all();
    expect(all.length, 2);
    expect(all.last.title, 'Steps today');

    await Locator.panels.delete('m1');
    expect(Locator.panels.all().length, 1);
  });

  testWidgets('weather panel renders live data', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PanelsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Weather now'), findsOneWidget);
    expect(find.text('29°C'), findsOneWidget);
    expect(find.text('Clear sky'), findsOneWidget);
    expect(find.text('wind 12 km/h'), findsOneWidget);
  });

  testWidgets('create a manual panel', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PanelsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Title (e.g. Water the plants)').first,
        'Focus streak');
    await tester.enterText(
        find.widgetWithText(TextField, 'Value to show').first, '5 days');
    await tester.tap(find.text('Save panel'));
    await tester.pumpAndSettle();

    expect(find.text('Focus streak'), findsOneWidget);
    expect(find.text('5 days'), findsOneWidget);
  });
}
