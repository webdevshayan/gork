import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/screens/theme_page.dart';
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
      store: InMemorySecureStore()..write('apikey.openai', 'sk-test'),
      // Weather is offline in tests → the card shows the reference copy.
      httpClient: MockClient((request) async => http.Response('offline', 500)),
    );
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey('tab-$tab')));
    await tester.pumpAndSettle();
  }

  testWidgets('home: weather card with two inner tiles + create-panel pill', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.byKey(const ValueKey('ambient-backdrop')), findsOneWidget);
    expect(find.byType(BackdropFilter), findsWidgets);
    // Reference Home has NO identity header — that lives on the menu surface.
    expect(find.text('Shayan Ali Jalb'), findsNothing);
    expect(find.text('shayanalibuilds@gmail.com'), findsNothing);
    expect(find.text('Sehwan Taluka, PK'), findsOneWidget);
    expect(find.text('Broken Clouds'), findsOneWidget);
    expect(find.text('26°C'), findsOneWidget);
    expect(find.text('Sunset'), findsOneWidget);
    expect(find.text('5:40 PM'), findsOneWidget);
    expect(find.text('Create a new panel'), findsOneWidget);
    expect(find.text('Message Hark'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('glass primitives: weather card radius 28, nav pill radius 30', (
    tester,
  ) async {
    await pumpShell(tester);

    final weather = tester.widget<GlassContainer>(
      find.ancestor(
        of: find.text('Sehwan Taluka, PK'),
        matching: find.byType(GlassContainer),
      ),
    );
    expect(weather.sigma, 10);
    expect(weather.radius, 28);

    final pill = tester.widget<GlassContainer>(
      find.ancestor(
        of: find.text('Home'),
        matching: find.byType(GlassContainer),
      ),
    );
    expect(pill.radius, 30);
  });

  testWidgets('left button follows the reference: + / search / ☰', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.byIcon(Icons.add), findsNWidgets(3),
        reason: 'left button + create pill + input attach');
    expect(find.byIcon(Icons.segment), findsNothing);

    await openTab(tester, 'chat');
    expect(find.byIcon(Icons.search), findsOneWidget);

    await openTab(tester, 'projects');
    expect(find.byIcon(Icons.segment), findsOneWidget);
  });

  testWidgets('nav pill highlights the active tab and switches screens', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(tester.widget<Text>(find.text('Home')).style!.color, Colors.white);
    expect(tester.widget<Text>(find.text('Chat')).style!.color, Colors.black54);

    await openTab(tester, 'chat');

    expect(tester.widget<Text>(find.text('Chat')).style!.color, Colors.white);
    expect(tester.widget<Text>(find.text('Home')).style!.color, Colors.black54);
    // Empty chat: seeded intro + the fanned GitHub link-preview stack.
    expect(find.text("Hey Shayan, I'm gork."), findsOneWidget);
    expect(find.textContaining('gork PR #19', skipOffstage: false),
        findsOneWidget);
    expect(
      find.text('Message Hark'),
      findsOneWidget,
      reason: 'input bar stays visible on the chat tab',
    );
  });

  testWidgets('menu surface: identity header, pro card, rows, search pill', (
    tester,
  ) async {
    await pumpShell(tester);

    await openTab(tester, 'projects');
    await tester.tap(find.byKey(const ValueKey('left-button')));
    await tester.pumpAndSettle();

    expect(find.text('Shayan Ali Jalb'), findsOneWidget);
    expect(find.text('shayanalibuilds@gmail.com'), findsOneWidget);
    expect(find.text('gork'), findsOneWidget);
    expect(find.text('pro'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);
    for (final row in [
      'Profile', 'Scheduled Tasks', 'Accounts', 'Wallet', 'Security',
    ]) {
      expect(find.text(row, skipOffstage: false), findsOneWidget);
    }
    // The Search pill sits at the bottom of the scroll.
    await tester.scrollUntilVisible(
      find.text('Search'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Message Hark'), findsNothing,
        reason: 'the input bar is hidden on the menu surface');
    // No tab is selected on the menu surface.
    expect(tester.widget<Text>(find.text('Home')).style!.color, Colors.black54);
    expect(tester.widget<Text>(find.text('Chat')).style!.color, Colors.black54);
    expect(
      tester.widget<Text>(find.text('Projects')).style!.color,
      Colors.black54,
    );

    // Tapping a tab returns to it.
    await tester.tap(find.byKey(const ValueKey('tab-home')));
    await tester.pumpAndSettle();
    expect(find.text('Shayan Ali Jalb'), findsNothing);
    expect(find.text('Sehwan Taluka, PK'), findsOneWidget);
  });

  testWidgets('theme page: glass radio card, persists the choice', (
    tester,
  ) async {
    await pumpShell(tester);

    await openTab(tester, 'projects');
    await tester.tap(find.byKey(const ValueKey('left-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Theme'), findsOneWidget);
    for (final mode in ['Auto', 'System', 'Light', 'Dark']) {
      expect(find.text(mode), findsOneWidget);
    }

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(Locator.prefs.getString('ui.theme'), 'Dark');
    expect(tester.widget<GlassRadio>(find.byType(GlassRadio).at(3)).selected,
        isTrue);
    expect(find.byKey(const ValueKey('theme-scrim')), findsOneWidget);
    expect(find.byIcon(Icons.u_turn_left), findsOneWidget);
  });

  testWidgets('chat search: search bar replaces the input, filters live', (
    tester,
  ) async {
    await pumpShell(tester);

    await openTab(tester, 'chat');
    await tester.tap(find.byKey(const ValueKey('left-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-bar')), findsOneWidget);
    expect(find.text('Message Hark'), findsNothing);
    expect(find.text('Search'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('search-bar')), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('No results for "zzzz".'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('search-clear')));
    await tester.pumpAndSettle();
    expect(find.textContaining('gork PR #19', skipOffstage: false),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('search-close')));
    await tester.pumpAndSettle();
    expect(find.text('Message Hark'), findsOneWidget);
  });

  testWidgets('input bar: + opens the attach menu, mic becomes send', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('attach-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('attach-menu')), findsOneWidget);
    for (final item in ['Camera', 'Photos', 'Files']) {
      expect(find.text(item), findsOneWidget);
    }
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('attach-menu')), findsNothing);
    // Expire the snackbar so it stops covering the input bar.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Typing swaps the mic for the black send circle.
    await tester.enterText(find.byKey(const ValueKey('input-bar')), 'hello');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-circle')), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsNothing);

    // Sending jumps to the chat tab.
    await tester.tap(find.byKey(const ValueKey('send-circle')));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget,
        reason: 'the message lands on the chat tab');
    expect(find.byIcon(Icons.search), findsOneWidget,
        reason: 'left button is now the chat search');
  });
}
