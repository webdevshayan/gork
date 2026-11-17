import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/google_accounts_screen.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 55 — the screenshot receipts:
/// 1. the Google Cloud Console upload card is REACHABLE. It used to be the
///    first Stack child of the Google screen — painted UNDER the ambient
///    backdrop, findable by tests, invisible to humans (the M49 widget test
///    passed because the backdrop ignores pointer events). The card must be
///    a descendant of the screen's ListView to ever be seen.
/// 2. the menu lists EVERY settings screen — Inbox, Panels and Cloud
///    Computer were built but reachable from nowhere.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
  });

  Future<void> bindMinimal() async {
    final prefs = await SharedPreferences.getInstance();
    Locator.bind(prefs: prefs, store: InMemorySecureStore());
  }

  testWidgets('the Google Cloud Console upload card lives IN the list',
      (tester) async {
    await bindMinimal();
    await tester.pumpWidget(const MaterialApp(home: GoogleAccountsScreen()));
    await tester.pumpAndSettle();

    final card = find.text('Google Cloud Console');
    expect(card, findsOneWidget);
    expect(
      find.ancestor(of: card, matching: find.byType(ListView)),
      findsOneWidget,
      reason: 'the upload card must scroll with the content — it used to '
          'sit under the backdrop, invisible to humans',
    );
    expect(find.byKey(const ValueKey('gconsole-upload')), findsOneWidget);
  });

  testWidgets('the menu lists every settings screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
    await tester.pumpAndSettle();

    // The menu is a lazy ListView — nine rows in the first card alone, so
    // scroll to each row before asserting it.
    for (final row in [
      'Profile',
      'Scheduled Tasks',
      'Accounts',
      'Integrations',
      'Google',
      'Inbox',
      'Panels',
      'Cloud Computer',
      // Movement 59: the Theme row is gone — the app is always auto.
      'Security',
      'AI Providers',
      'Updates',
    ]) {
      await tester.scrollUntilVisible(
        find.text(row, skipOffstage: false),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(row, skipOffstage: false), findsOneWidget,
          reason: '$row is reachable');
    }
  });
}
