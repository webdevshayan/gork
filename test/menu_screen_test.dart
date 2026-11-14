import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/screens/wallet_screen.dart';
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
    // the wordmark itself stays
    expect(find.text('gork'), findsWidgets);
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

  testWidgets('an AI Providers row reaches the BYOK screen',
      (tester) async {
    await _pump(tester);
    // Google + Theme rows pushed AI Providers below the fold — drag
    // the menu list up before anything that touches the row.
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-providers')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('menu-providers')),
      100.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('menu-providers')));
    await tester.pumpAndSettle();
    expect(find.text('Providers'), findsOneWidget);
  });

  testWidgets('Wallet row opens the Wallet screen', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('menu-wallet')));
    await tester.pumpAndSettle();
    expect(find.byType(WalletScreen), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
  });

  testWidgets('Security row opens the Wallet screen (the secure store)',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('menu-security')));
    await tester.pumpAndSettle();
    expect(find.byType(WalletScreen), findsOneWidget);
  });
}
