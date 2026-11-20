import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/constants/version.dart';
import 'package:gork/screens/gork_home.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/screens/updates_screen.dart';
import 'package:gork/services/credential_uploader.dart';
import 'package:gork/services/google_oauth_service.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 63 — three user-reported fixes:
///
///   * the Google screen no longer fails with "bad or missing
///     X-Gork-Secret": the OAuth flow and the credentials uploader resolve
///     the secret through the ONE VpsConfig (legacy `handoff.secret` and
///     agent-VPS apiKey included) and send the SAME header as everything
///     else server-side
///   * the sunset dialog's refusal is fully readable (own wrapped error,
///     no decorator ellipsis) and the NUMBER keypad works ('1740', '940')
///   * the menu carries the Preferences | About tabs itself — the separate
///     Settings screen (and its redundant title) is gone
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
      httpClient: MockClient((request) async =>
          throw http.ClientException('offline in tests')),
    );
  });

  group('Movement 63 — the Google flow authenticates like everything else', () {
    test('uploader sends X-Gork-Secret resolved from the legacy slot',
        () async {
      final prefs = Locator.prefs;
      await prefs.setString('vps.url', 'http://vps.test:8787');
      await Locator.store.write('handoff.secret', 'legacy-secret');
      Map<String, String>? sent;
      final uploader = GoogleCredentialsUploader(
        client: MockClient((request) async {
          sent = request.headers;
          return http.Response('{"ok": true}', 201);
        }),
        store: Locator.store,
      );
      final dir = await Directory.systemTemp.createTemp('gork-cred');
      final file = File('${dir.path}/credentials.json');
      await file
          .writeAsString(jsonEncode({'installed': {'client_id': 'x'}}));
      await uploader.upload(file.path);
      await dir.delete(recursive: true);

      expect(sent, isNotNull);
      expect(sent!['X-Gork-Secret'], 'legacy-secret',
          reason: 'the SAME secret chat handoff uses — no more 401');
      expect(sent!['Authorization'], isNull);
    });

    test('oauth accounts() sends X-Gork-Secret from the legacy slot too',
        () async {
      final prefs = Locator.prefs;
      await prefs.setString('vps.url', 'http://vps.test:8787');
      await Locator.store.write('handoff.secret', 'legacy-secret');
      Map<String, String>? sent;
      final oauth = GoogleOAuthService(
        client: MockClient((request) async {
          sent = request.headers;
          return http.Response('{"accounts": []}', 200);
        }),
        prefs: prefs,
        store: Locator.store,
      );
      await oauth.accounts();

      expect(sent, isNotNull);
      expect(sent!['X-Gork-Secret'], 'legacy-secret');
    });

    test('direct vps.token still wins when both are present', () async {
      final prefs = Locator.prefs;
      await prefs.setString('vps.url', 'http://vps.test:8787');
      await Locator.store.write('vps.token', 'direct-secret');
      await Locator.store.write('handoff.secret', 'legacy-secret');
      Map<String, String>? sent;
      final oauth = GoogleOAuthService(
        client: MockClient((request) async {
          sent = request.headers;
          return http.Response('{"accounts": []}', 200);
        }),
        prefs: prefs,
        store: Locator.store,
      );
      await oauth.accounts();

      expect(sent!['X-Gork-Secret'], 'direct-secret');
    });
  });

  group('Movement 63 — the sunset dialog', () {
    testWidgets('accepts bare digits from the number keypad', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GorkHome()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('weather-sunset-tile')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('sunset-input')), '2015');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(Locator.prefs.getString('home.sunset'), '20:15');
      expect(find.text('8:15 PM'), findsOneWidget,
          reason: 'the override now wins over the fallback label');
    });

    testWidgets('the refusal is fully readable, never ellipsized',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GorkHome()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('weather-sunset-tile')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('sunset-input')), '00');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // The error is its OWN widget (not a decorator one-liner) and carries
      // every accepted format.
      final error = find.byKey(const ValueKey('sunset-error'));
      expect(error, findsOneWidget);
      final text = tester.widget<Text>(error).data!;
      expect(text, contains('5:40 PM'));
      expect(text, contains('17:40'));
      expect(text, contains('1740'));
      expect(tester.widget<Text>(error).maxLines, greaterThan(1));
    });
  });

  group('Movement 63 — Preferences live in the menu, no Settings screen', () {
    testWidgets('the theme is a row that pushes its own screen — and the '
        'Preferences | About tabs are GONE (Movement 68: one flat list '
        'scans faster than tabs-within-a-list)', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
      await tester.pumpAndSettle();

      // The Theme row sits below the fold in the lazy ListView — bring it
      // in before asserting anything.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('menu-theme')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(
          find.byKey(const ValueKey('menu-theme')), const Offset(0, -120));
      await tester.pumpAndSettle();

      // Movement 68 — no tabs, no panes, no background-responses card.
      expect(find.text('Preferences', skipOffstage: false), findsNothing);
      expect(find.text('About', skipOffstage: false), findsNothing);
      expect(find.byKey(const ValueKey('settings-tab-preferences')),
          findsNothing);
      expect(find.byKey(const ValueKey('settings-tab-about')), findsNothing);
      expect(find.text('Background responses'), findsNothing);

      // No nested "Settings" row anywhere.
      expect(find.text('Settings'), findsNothing);
      expect(find.byKey(const ValueKey('menu-settings')), findsNothing);

      // The theme keys are NOT on the menu anymore — the row pushes the
      // screen that owns them (Movement 65).
      expect(find.byKey(const ValueKey('theme-auto')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('menu-theme')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('theme-auto')), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-light')), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-dark')), findsOneWidget);

      // Picking a theme still persists — now from the dedicated screen.
      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pumpAndSettle();
      expect(Locator.prefs.getString('ui.theme'), 'dark');
    });

    testWidgets('version + update checks live on the Updates row, not in '
        'a vanished About pane', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
      await tester.pumpAndSettle();

      expect(find.text('gork v$kAppVersion'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('menu-updates')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      // The row carries the version as its trailing label (hidden in dev
      // builds, where the version is literally 'dev')...
      if (kAppVersion != 'dev') {
        expect(find.text('v$kAppVersion'), findsOneWidget);
      }
      // ...and pushes the Updates screen (which owns the check).
      await tester.tap(find.byKey(const ValueKey('menu-updates')));
      await tester.pumpAndSettle();
      expect(find.byType(UpdatesScreen), findsOneWidget);
    });
  });
}
