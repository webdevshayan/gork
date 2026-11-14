import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/screens/theme_page.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/profile_info.dart';
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

Color _navLabelColor(WidgetTester tester, String label) => DefaultTextStyle.of(
      tester.element(find.text(label)),
    ).style.color!;

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
    expect(find.text(kDefaultName), findsNothing);
    expect(find.text(kDefaultEmail), findsNothing);
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

  testWidgets('left button follows the reference: + / settings / back', (
    tester,
  ) async {
    await pumpShell(tester);

    // Home: the + (dropdown); Chat: settings; Projects: back. No ☰ anywhere.
    expect(find.byIcon(Icons.segment), findsNothing);
    expect(find.byIcon(Icons.menu), findsNothing);

    await openTab(tester, 'chat');
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    await openTab(tester, 'projects');
    expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
  });

  testWidgets('home + opens the add dropdown (file / image / panel)', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('left-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-menu')), findsOneWidget);
    for (final item in ['Add file', 'Add image', 'New panel']) {
      expect(find.text(item), findsOneWidget);
    }

    // Tapping + again closes the dropdown.
    await tester.tap(find.byKey(const ValueKey('left-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-menu')), findsNothing);
  });

  testWidgets('chat settings button opens the settings surface', (
    tester,
  ) async {
    await pumpShell(tester);

    await openTab(tester, 'chat');
    await tester.tap(find.byKey(const ValueKey('left-button')));
    await tester.pumpAndSettle();

    expect(find.text(kDefaultName), findsOneWidget,
        reason: 'the settings surface shows the identity header');
    // The left button is now back.
    expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('left-button')));
    await tester.pumpAndSettle();
    expect(find.text(kDefaultName), findsNothing);
    expect(find.text("Hey Shayan, I'm gork.", findRichText: true), findsOneWidget);
  });

  testWidgets('nav pill highlights the active tab and switches screens', (
    tester,
  ) async {
    await pumpShell(tester);

    // The labels inherit the animated default text style.
    expect(_navLabelColor(tester, 'Home'), GlassColors.textOnChip);
    expect(_navLabelColor(tester, 'Chat'), GlassColors.textDim);

    await openTab(tester, 'chat');

    expect(_navLabelColor(tester, 'Chat'), GlassColors.textOnChip);
    expect(_navLabelColor(tester, 'Home'), GlassColors.textDim);
    // Empty chat: seeded intro + the fanned GitHub link-preview stack.
    expect(find.text("Hey Shayan, I'm gork.", findRichText: true), findsOneWidget);
    expect(find.textContaining('gork PR #19', skipOffstage: false,
        findRichText: true), findsOneWidget);
    expect(
      find.text('Message Hark'),
      findsOneWidget,
      reason: 'input bar stays visible on the chat tab',
    );
  });

  testWidgets('settings surface: opens via profile, identity header, rows', (
    tester,
  ) async {
    await pumpShell(tester);

    // The settings page becomes visible when the profile is tapped.
    await tester.tap(find.byKey(const ValueKey('avatar')));
    await tester.pumpAndSettle();

    expect(find.text(kDefaultName), findsOneWidget);
    expect(find.text(kDefaultEmail), findsOneWidget);
    expect(find.text('gork'), findsNothing,
        reason: 'the gork wordmark card is removed (user request) — the '
            'menu starts with the identity header and rows');
    expect(find.text('pro'), findsNothing, reason: 'no upsell on the menu');
    expect(find.text('Upgrade'), findsNothing, reason: 'no upsell on the menu');
    expect(find.text('Resets'), findsNothing);
    expect(find.text('Usage and plan'), findsNothing);
    for (final row in [
      'Profile', 'Scheduled Tasks', 'Accounts', 'Wallet', 'Security',
      'AI Providers', 'Sync to daemon',
    ]) {
      expect(find.text(row, skipOffstage: false), findsOneWidget);
    }
    expect(find.text('Message Hark'), findsNothing,
        reason: 'the input bar is hidden on the settings surface');
    // No tab is selected on the settings surface.
    expect(_navLabelColor(tester, 'Home'), GlassColors.textDim);
    expect(_navLabelColor(tester, 'Chat'), GlassColors.textDim);
    expect(_navLabelColor(tester, 'Projects'), GlassColors.textDim);

    // Tapping a tab returns to it.
    await tester.tap(find.byKey(const ValueKey('tab-home')));
    await tester.pumpAndSettle();
    expect(find.text(kDefaultName), findsNothing);
    expect(find.text('Sehwan Taluka, PK'), findsOneWidget);
  });

  testWidgets('profile tapped twice: second tap offers to change the photo', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('avatar')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('choose-photo')), findsOneWidget);
    expect(find.byKey(const ValueKey('remove-photo')), findsOneWidget);
  });

  testWidgets('avatar without a photo shows the person icon (offline)', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(
      tester.widget<Icon>(find.descendant(
        of: find.byKey(const ValueKey('avatar')),
        matching: find.byIcon(Icons.person_outline),
      )).size,
      24,
    );
  });

  testWidgets('theme page: glass radio card, persists the choice', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('avatar')));
    await tester.pumpAndSettle();
    // Movement 38: Profile opens the identity form; Theme has its own
    // row — drag the menu list up until the row is on screen.
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-theme')));
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
        expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget,
        reason: 'back affordances are chevrons everywhere');
  });

  testWidgets('input bar: + opens the attach menu, mic becomes an arrow, '
      'and the field grows with the message', (
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

    // Typing swaps the mic for the black arrow circle.
    await tester.enterText(find.byKey(const ValueKey('input-bar')), 'hello');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('send-circle')), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsNothing);

    // The message field auto-resizes instead of clipping.
    final field = tester.widget<TextField>(find.descendant(
      of: find.byKey(const ValueKey('input-bar')),
      matching: find.byType(TextField),
    ));
    expect(field.maxLines, 6);

    // Sending jumps to the chat tab.
    await tester.tap(find.byKey(const ValueKey('send-circle')));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget,
        reason: 'the message lands on the chat tab');
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget,
        reason: 'left button on chat is now settings');
  });
}
