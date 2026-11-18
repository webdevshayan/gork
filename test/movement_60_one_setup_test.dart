import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/constants/ambient.dart';
import 'package:gork/screens/cloud_computer_screen.dart';
import 'package:gork/screens/gork_home.dart';
import 'package:gork/screens/security_screen.dart';
import 'package:gork/services/cloud_computer_store.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 60 — ONE VPS setup, solid surfaces, toggleable theme, editable
/// sunset, full-width home tiles.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
      // Home fetches weather on build — fail fast so tests are offline-
      // deterministic and the fallback labels apply.
      httpClient: MockClient((request) async =>
          throw http.ClientException('offline in tests')),
    );
  });

  group('VpsConfig — the ONE connection with legacy fallbacks', () {
    test('resolution order: vps.url > handoff.url > agentvps endpoint',
        () async {
      final vps = Locator.handoff.vps;
      expect(vps.configured, isFalse);

      // The deepest fallback: the AgentVPS endpoint from the picker.
      await Locator.cloudComputer.save(const CloudComputerConfig(
        backend: CloudBackend.agentvps,
        endpoint: 'http://5.5.5.5:8787',
        apiKey: '',
        updatedAt: 0,
      ));
      expect(vps.url, 'http://5.5.5.5:8787');

      // The legacy daemon URL outranks the picker endpoint.
      await Locator.prefs.setString('handoff.url', 'http://6.6.6.6:8787/');
      expect(vps.url, 'http://6.6.6.6:8787',
          reason: 'trailing slash stripped');
      expect(vps.configured, isTrue);

      // vps.url outranks everything.
      await vps.save('http://7.7.7.7:8787/');
      expect(vps.url, 'http://7.7.7.7:8787');

      // A third-party browseruse endpoint is NOT a gork daemon fallback.
      await Locator.prefs.remove('handoff.url');
      await vps.clear();
      await Locator.cloudComputer.save(const CloudComputerConfig(
        backend: CloudBackend.browseruse,
        endpoint: '',
        apiKey: 'k',
        updatedAt: 0,
      ));
      expect(vps.url, isNull);
    });

    test('token fallback: vps.token > handoff.secret > agentvps apiKey',
        () async {
      final vps = Locator.handoff.vps;
      await Locator.store.write('handoff.secret', 'legacy');
      expect(await vps.token(), 'legacy');

      await vps.save('http://x', token: 'new');
      expect(await vps.token(), 'new');
      await vps.save('http://x', token: null);
      expect(await vps.token(), 'new', reason: 'null keeps the saved one');
      await vps.save('http://x', token: '');
      expect(await vps.token(), isNull, reason: 'empty clears it');
    });

    test('handoff reads and writes the SAME vps state', () async {
      final handoff = Locator.handoff;
      await handoff.setUrl('http://vps.example:8787');
      expect(Locator.prefs.getString('vps.url'), 'http://vps.example:8787');
      expect(handoff.url, 'http://vps.example:8787');
      await handoff.setNtfyTopic('gork-phone');
      expect(Locator.prefs.getString('vps.ntfy'), 'gork-phone');
      expect(handoff.ntfyTopic, 'gork-phone');
      await handoff.setSecret('hunter2');
      expect(await Locator.store.read('vps.token'), 'hunter2');
    });
  });

  group('Cloud Computer screen — the one setup surface', () {
    testWidgets('agentvps shows the VPS card; no duplicate handoff fields',
        (tester) async {
      await Locator.prefs.setString('handoff.url', 'http://6.6.6.6:8787');
      await tester.pumpWidget(const MaterialApp(home: CloudComputerScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vps-url')), findsOneWidget);
      expect(find.byKey(const Key('vps-secret')), findsOneWidget);
      expect(find.byKey(const Key('handoff-url')), findsNothing,
          reason: 'the daemon rides the same connection — no second form');

      // The handoff status section sits below the fold.
      await tester.scrollUntilVisible(
        find.textContaining('Connected to http://6.6.6.6:8787'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Connected to http://6.6.6.6:8787'),
          findsOneWidget);
      // Back up: the card heading sits above the status section.
      await tester.scrollUntilVisible(
        find.textContaining('one setup for everything'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('one setup for everything'),
          findsOneWidget);
    });
  });

  group('Home — theme toggle, editable sunset, full-width tiles', () {
    testWidgets('theme toggle persists the choice and nudges the shell',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GorkHome()));
      await tester.pumpAndSettle();

      final before = ambient.version.value;
      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pumpAndSettle();
      expect(Locator.prefs.getString('ui.theme'), 'dark');
      expect(ambient.version.value, greaterThan(before),
          reason: 'the shell rebuilds immediately');

      await tester.tap(find.byKey(const ValueKey('theme-light')));
      await tester.pumpAndSettle();
      expect(Locator.prefs.getString('ui.theme'), 'light');

      await tester.tap(find.byKey(const ValueKey('theme-auto')));
      await tester.pumpAndSettle();
      expect(Locator.prefs.getString('ui.theme'), 'auto');
    });

    testWidgets('sunset is editable: the override persists and wins',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GorkHome()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('weather-sunset-tile')));
      await tester.pumpAndSettle();
      expect(find.text('Edit sunset time'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('sunset-input')), '6:15 PM');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(Locator.prefs.getString('home.sunset'), '18:15');
      expect(find.text('6:15 PM'), findsOneWidget);

      // Garbage is refused in place.
      await tester.tap(find.byKey(const ValueKey('weather-sunset-tile')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('sunset-input')), 'not a time');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not a time — try'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Back to the computed value.
      await tester.tap(find.byKey(const ValueKey('weather-sunset-tile')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use computed'));
      await tester.pumpAndSettle();
      expect(Locator.prefs.getString('home.sunset'), isNull);
    });

    testWidgets('the inner tiles stretch full width inside the first card',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GorkHome()));
      await tester.pumpAndSettle();

      final conditions = tester
          .getSize(find.byKey(const ValueKey('weather-conditions-tile')));
      final sunset =
          tester.getSize(find.byKey(const ValueKey('weather-sunset-tile')));
      expect(conditions.width, sunset.width);
      expect(conditions.width, greaterThan(600),
          reason: 'edge to edge inside the card, not content-hugging');
    });
  });

  group('Security screen — routes to the ONE setup', () {
    testWidgets('shows the VPS connection card with the connected URL',
        (tester) async {
      await Locator.prefs.setString('vps.url', 'http://vps.example:8787');
      await tester.pumpWidget(const MaterialApp(home: SecurityScreen()));
      await tester.pumpAndSettle();

      expect(find.text('VPS connection'), findsOneWidget);
      expect(find.textContaining('Connected to http://vps.example:8787'),
          findsOneWidget);
      expect(find.text('Change in Cloud Computer'), findsOneWidget);
    });
  });
}
