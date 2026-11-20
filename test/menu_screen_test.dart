import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/screens/security_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 34: the profile surface loses the upsell — no Upgrade button, no
/// "pro" wordmark, no plan/usage rows, no open-source blurb. The wordmark
/// card stays, and real navigation (AI Providers / Sync to daemon) replaces it.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
    );
  });

  Future<void> _pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
    await tester.pump();
  }

  testWidgets('no Upgrade button and no "pro" wordmark', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('upgrade-button')), findsNothing);
    expect(find.text('Upgrade'), findsNothing);
    expect(find.text('pro'), findsNothing);
    expect(find.byKey(const ValueKey('pro-card')), findsNothing);
    // the wordmark card is gone (user request, Movement 42)
    expect(find.text('gork'), findsNothing);
  });

  testWidgets('no Resets row, no usage-and-plan row', (tester) async {
    await _pump(tester);
    expect(find.text('Resets'), findsNothing);
    expect(find.text('Never — your keys, your limits'), findsNothing);
    expect(find.byKey(const ValueKey('menu-usage')), findsNothing);
    expect(find.text('Usage and plan'), findsNothing);
  });

  testWidgets('no open-source blurb anywhere on the menu surface',
      (tester) async {
    await _pump(tester);
    expect(find.textContaining('open source'), findsNothing);
    expect(find.textContaining('free & open'), findsNothing);
  });

  testWidgets('AI Providers is reachable through Connections (Movement 69 '
      'de-duplication)', (tester) async {
    await _pump(tester);
    // The menu is a CustomScrollView now; AI Providers no longer has its
    // own row — it lives inside Connections, one tap away.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('menu-connections')),
      100.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('menu-connections')));
    await tester.pumpAndSettle();
    // The connections list is lazy — scroll the providers row in.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('connection-providers')),
      120.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('connection-providers')));
    await tester.pumpAndSettle();
    expect(find.text('Providers'), findsOneWidget);
  });

  testWidgets('no Wallet row — the feature is removed (Movement 50)',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('menu-wallet')), findsNothing);
    expect(find.text('Wallet'), findsNothing);
    expect(find.textContaining('Wallet'), findsNothing);
  });

  testWidgets('Security row opens the Security screen (the vault)',
      (tester) async {
    await _pump(tester);
    // Movement 69 — CustomScrollView menu: scroll until the Security row
    // builds, then tap it.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('menu-security')),
      120.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-security')));
    await tester.pumpAndSettle();
    expect(find.byType(SecurityScreen), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
  });
}
