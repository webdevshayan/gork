import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/widgets/glass.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Blocks raw Image.network calls (the ambient backdrop + avatar fall back to
/// their offline paths). Keeps widget tests deterministic — no Unsplash.
class _BlockedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient();
}

class _BlockedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in widget tests');
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _BlockedOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  Future<void> pumpShell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
      // Weather is offline in tests → the card shows the spec fallback copy.
      httpClient: MockClient((request) async => http.Response('offline', 500)),
    );
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey('tab-$tab')));
    await tester.pumpAndSettle();
  }

  testWidgets('home shows identity, weather panel and create-panel pill', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.byKey(const ValueKey('ambient-backdrop')), findsOneWidget);
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(find.text('Shayan Ali Jalb'), findsOneWidget);
    expect(find.text('shayanalibuilds@gmail.com'), findsOneWidget);
    expect(find.text('Sehwan Taluka, PK'), findsOneWidget);
    expect(find.text('Broken Clouds, 26°C'), findsOneWidget);
    expect(find.text('Sunset, 5:40 PM'), findsOneWidget);
    expect(find.text('Create a new panel'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(
      find.byIcon(Icons.add),
      findsNWidgets(2),
      reason: 'one + on the create-panel pill, one in the input bar',
    );
    expect(find.text('Message Hark'), findsOneWidget);
  });

  testWidgets(
    'glass primitives: blur sigma 10, card radius 16, pill radius 30',
    (tester) async {
      await pumpShell(tester);

      final weather = tester.widget<GlassContainer>(
        find.ancestor(
          of: find.text('Sehwan Taluka, PK'),
          matching: find.byType(GlassContainer),
        ),
      );
      expect(weather.sigma, 10);
      expect(weather.radius, 16);

      final pill = tester.widget<GlassContainer>(
        find.ancestor(
          of: find.text('Home'),
          matching: find.byType(GlassContainer),
        ),
      );
      expect(pill.radius, 30);
    },
  );

  testWidgets('nav pill highlights the active tab and switches screens', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(tester.widget<Text>(find.text('Home')).style!.color, Colors.white);
    expect(tester.widget<Text>(find.text('Chat')).style!.color, Colors.black54);

    await openTab(tester, 'chat');

    expect(tester.widget<Text>(find.text('Chat')).style!.color, Colors.white);
    expect(tester.widget<Text>(find.text('Home')).style!.color, Colors.black54);
    expect(find.text('Shayan Ali Jalb'), findsNothing);
    // Empty chat shows the GitHub link preview card from the spec.
    expect(find.text('webdevshayan/gork'), findsOneWidget);
    expect(
      find.text('Message Hark'),
      findsOneWidget,
      reason: 'input bar stays visible on the chat tab',
    );
  });

  testWidgets(
    'menu opens System Preferences; back arrow returns; input hides',
    (tester) async {
      await pumpShell(tester);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      expect(find.text('System Preferences'), findsOneWidget);
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'the input bar is hidden on the preferences screen',
      );
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
      for (final row in ['Theme', 'Data Management', 'Security', 'About']) {
        expect(find.text(row), findsOneWidget);
      }
      expect(find.text('System'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) => w is Divider && w.color == Colors.black12,
        ),
        findsWidgets,
      );

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();

      expect(find.text('Shayan Ali Jalb'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    },
  );

  testWidgets('Projects tab opens the same preferences screen', (tester) async {
    await pumpShell(tester);

    await openTab(tester, 'projects');

    expect(find.text('System Preferences'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    expect(find.text('Shayan Ali Jalb'), findsOneWidget);
  });
}
