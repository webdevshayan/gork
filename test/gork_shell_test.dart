import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/screens/search_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/profile_info.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/widgets/glass.dart';
import 'package:gork/widgets/bottom_input_bar.dart';
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

  testWidgets('Movement 62 — CHAT is the landing surface (the app opens '
      'into the conversation, Home is one tap away)', (tester) async {
    await pumpShell(tester);

    // No weather card on the first screen — the chat is facing the user.
    expect(find.text('Sehwan Taluka, PK'), findsNothing);
    expect(find.text('Create a new panel'), findsNothing);

    // The nav pill starts on chat…
    await tester.tap(find.byKey(const ValueKey('left-button')));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget,
        reason: 'the top-left button opens the chat-scoped search');
    await tester.tap(find.descendant(
      of: find.byType(SearchScreen),
      matching: find.byIcon(Icons.arrow_back_ios_new),
    ));
    await tester.pumpAndSettle();

    // …and Home is still there, one tap away.
    await openTab(tester, 'home');
    expect(find.text('Sehwan Taluka, PK'), findsOneWidget);
  });

  testWidgets('home: weather card with two inner tiles + create-panel pill', (
    tester,
  ) async {
    await pumpShell(tester);
    await openTab(tester, 'home');

    expect(find.byKey(const ValueKey('ambient-backdrop')), findsOneWidget);
    // Movement 60 — solid surfaces: no backdrop blur anywhere.
    expect(find.byType(BackdropFilter), findsNothing);
    // Reference Home has NO identity header — that lives on the menu surface.
    expect(find.text(kDefaultName), findsNothing);
    expect(find.text(kDefaultEmail), findsNothing);
    expect(find.text('Sehwan Taluka, PK'), findsOneWidget);
    expect(find.text('Broken Clouds'), findsOneWidget);
    expect(find.text('26°C'), findsOneWidget);
    expect(find.text('Sunset'), findsOneWidget);
    expect(find.text('5:40 PM'), findsOneWidget);
    expect(find.text('Create a new panel'), findsOneWidget);
    expect(find.text('Message Gork'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    // Movement 62 — the theme toggle MOVED to Settings › Preferences:
    // Home keeps weather and panels only.
    expect(find.byKey(const ValueKey('theme-auto')), findsNothing);
    expect(find.byKey(const ValueKey('theme-light')), findsNothing);
    expect(find.byKey(const ValueKey('theme-dark')), findsNothing);
  });

  testWidgets('glass primitives: weather card radius 28, nav pill radius 30', (
    tester,
  ) async {
    await pumpShell(tester);
    await openTab(tester, 'home');

    final weather = tester.widget<GlassContainer>(
      find.ancestor(
        of: find.text('Sehwan Taluka, PK'),
        matching: find.byType(GlassContainer),
      ),
    );
    expect(weather.radius, 28);
    // Movement 60 — solid surfaces: no sigma/blur parameter anymore.
    expect(weather.strong, isFalse);

    final pill = tester.widget<GlassContainer>(
      find.ancestor(
        of: find.text('Home'),
        matching: find.byType(GlassContainer),
      ),
    );
    expect(pill.radius, 30);
  });

  testWidgets('left button is search on every tab (one verb, one place)', (
    tester,
  ) async {
    await pumpShell(tester);

    IconData leftIcon() => tester
        .widget<Icon>(find.descendant(
          of: find.byKey(const ValueKey('left-button')),
          matching: find.byType(Icon),
        ))
        .icon!;

    // Home, Chat, Projects: the top-left button is ALWAYS search (chevron
    // only on the settings surface). No + dropdown, no settings icon.
    expect(leftIcon(), Icons.search);
    expect(find.byIcon(Icons.menu), findsNothing);

    await openTab(tester, 'chat');
    expect(leftIcon(), Icons.search);

    await openTab(tester, 'projects');
    expect(leftIcon(), Icons.search);
  });

  testWidgets('home search opens the scoped overlay (the + dropdown is gone)',
    (tester) async {
    await pumpShell(tester);
    await openTab(tester, 'home');

    await tester.tap(find.byKey(const ValueKey('left-button')));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget,
        reason: 'the top-left button opens search on home');
    expect(find.text('Add file'), findsNothing,
        reason: 'attachments live in the input bar +, not the top-left');


    // Closing via the overlay's own chevron returns to home.
    await tester.tap(find.descendant(
      of: find.byType(SearchScreen),
      matching: find.byIcon(Icons.arrow_back_ios_new),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
  });

  testWidgets('chat search is scoped to the active thread; '
      'settings live behind the avatar', (tester) async {
    await pumpShell(tester);

    await openTab(tester, 'chat');
    await tester.tap(find.byKey(const ValueKey('left-button')));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget);
    expect(
      tester.widget<SearchScreen>(find.byType(SearchScreen)).initialScope,
      SearchScope.chat,
      reason: 'searching from the chat tab searches the conversation',
    );

    // Settings surface: avatar (the left button is search now).
    await tester.tap(find.descendant(
      of: find.byType(SearchScreen),
      matching: find.byIcon(Icons.arrow_back_ios_new),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('avatar')));
    await tester.pumpAndSettle();
    expect(find.text(kDefaultName), findsOneWidget,
        reason: 'the settings surface shows the identity header');
    expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('left-button')));
    await tester.pumpAndSettle();
    expect(find.text(kDefaultName), findsNothing);
    // Movement 53: the intro is dynamic — it plays as animated bubbles, so
    // no static seed text remains on the empty surface.
    expect(find.textContaining("I'm gork.", findRichText: true), findsNothing);
  });

  testWidgets('nav pill highlights the active tab and switches screens', (
    tester,
  ) async {
    await pumpShell(tester);

    // Movement 62 — the shell LANDS on chat: chat is highlighted first.
    expect(_navLabelColor(tester, 'Chat'), GlassColors.textOnChip);
    expect(_navLabelColor(tester, 'Home'), GlassColors.textDim);

    await openTab(tester, 'home');

    expect(_navLabelColor(tester, 'Home'), GlassColors.textOnChip);
    expect(_navLabelColor(tester, 'Chat'), GlassColors.textDim);

    // Back to chat for the surface-content assertions.
    await openTab(tester, 'chat');
    // Empty chat: seeded intro + the fanned GitHub link-preview stack.
    // Movement 53: the intro is dynamic — it plays as animated bubbles, so
    // no static seed text remains on the empty surface.
    expect(find.textContaining("I'm gork.", findRichText: true), findsNothing);
    expect(find.textContaining('gork PR #19', skipOffstage: false,
        findRichText: true), findsOneWidget);
    expect(
      find.text('Message Gork'),
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
      'Profile', 'Scheduled Tasks', 'Accounts', 'Security',
      'AI Providers', 'Sync to daemon',
    ]) {
      // Movement 55 added Inbox/Panels/Cloud Computer rows — the list grew,
      // so scroll to each row (lazy ListView) before asserting it.
      await tester.scrollUntilVisible(
        find.text(row, skipOffstage: false),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(row, skipOffstage: false), findsOneWidget);
    }
    expect(find.text('Message Gork'), findsNothing,
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

  testWidgets('Movement 63: the theme lives IN the menu — embedded '
      'Preferences section, still no separate theme row or page',
      (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('avatar')));
    await tester.pumpAndSettle();
    // The old menu-theme ROW is still gone; the picker is the embedded
    // Preferences section instead. Drag far enough to reach it.
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('menu-theme')), findsNothing);
    expect(find.byKey(const ValueKey('theme-auto')), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget,
        reason: 'the picker is right here in the profile screen');
  });

  testWidgets('Movement 59: the attach menu NEVER overflows the right '
      'screen edge (screenshot bug)', (tester) async {
    await pumpShell(tester);
    await openTab(tester, 'chat');
    await tester.tap(find.byKey(const ValueKey('attach-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('attach-menu')), findsOneWidget);
    final menuRect = tester.getRect(find.byKey(const ValueKey('attach-menu')));
    final screenWidth = tester.view.physicalSize.width /
        tester.view.devicePixelRatio;
    // The screenshot bug: the menu sat past the right edge, chevrons clipped.
    expect(menuRect.right, lessThanOrEqualTo(screenWidth),
        reason: 'menu right edge must stay on screen');
    expect(menuRect.left, greaterThanOrEqualTo(0),
        reason: 'menu left edge must stay on screen');
    // And it must sit ABOVE the input bar, not cover the whole screen.
    final inputRect = tester.getRect(find.byType(BottomInputBar));
    expect(menuRect.bottom, lessThanOrEqualTo(inputRect.top + 1),
        reason: 'menu bottom must not cover the input bar');
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

    // Sending jumps to the Chat tab — THE one global chat (Movement 55:
    // nothing in the app composes a new thread anymore).
    await tester.tap(find.byKey(const ValueKey('send-circle')));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget,
        reason: 'the message lands in THE global chat');
    expect(find.byIcon(Icons.search), findsOneWidget,
        reason: 'the Chat tab is the global chat itself — not a pushed '
            'screen, so the top-left stays the search button');
  });
}
