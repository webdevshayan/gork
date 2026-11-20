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

  testWidgets('no manual form — widgets are AI-authored (Movement 69); '
      'an AI spec lands on the feed', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PanelsScreen()));
    await tester.pumpAndSettle();

    // No FAB, no form anywhere: the user asks in chat, the AI answers with
    // a gork-panel block, and the app harvests it.
    expect(find.byIcon(Icons.add), findsNothing);
    await Locator.panels.addSpec(
        PanelSpec.fromAgent({'title': 'Focus streak', 'value': '5 days'}));
    await tester.pump();
    // The screen reads the store on init; force a remount (same widget
    // type would reuse the stale state).
    await tester
        .pumpWidget(MaterialApp(home: PanelsScreen(key: UniqueKey())));
    await tester.pumpAndSettle();
    expect(find.text('Focus streak'), findsOneWidget);
    expect(find.text('5 days'), findsOneWidget);
  });
}
