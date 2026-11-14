// Movement 38 — the profile is a real profile, and Google connects in one click.
//
// What the user asked for, verbatim:
//   * a form for changing name and email;
//   * connecting Google (ALL services) with just one click;
//   * an account selection screen.
//
// Before this movement the identity header was two compile-time constants —
// nothing in the app could be edited, and Google (Gmail) could only be
// connected one token dialog at a time inside the Integrations screen.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/google_accounts_screen.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/screens/profile_edit_screen.dart';
import 'package:gork/services/google_accounts.dart';
import 'package:gork/services/integrations.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verifier fake: 'good' tokens resolve to a mailbox, anything else 401s
/// exactly like the real Gmail whoAmI call would.
Future<String> fakeVerify(String token) async {
  if (token == 'good-token') return 'shayanalibuilds@gmail.com';
  if (token == 'work-token') return 'shyan@work.example';
  throw const IntegrationException('HTTP 401 — invalid token');
}

GoogleAccountStore makeStore([IntegrationVault? vault]) =>
    GoogleAccountStore(
      store: InMemorySecureStore(),
      verifier: fakeVerify,
      vault: vault ?? IntegrationVault(InMemorySecureStore()),
    );

void main() {
  group('GoogleAccountStore — accounts live in the keystore', () {
    test('addAccount verifies the token and persists the account', () async {
      final store = makeStore();
      final acct = await store.addAccount('good-token');
      expect(acct.email, 'shayanalibuilds@gmail.com');
      expect(await store.accounts().then((a) => a.length), 1);
    });

    test('a bad token throws and persists nothing', () async {
      final store = makeStore();
      await expectLater(store.addAccount('garbage'), throwsException);
      expect(await store.accounts(), isEmpty);
    });

    test('re-adding the same email upserts instead of duplicating',
        () async {
      final store = makeStore();
      await store.addAccount('good-token');
      await store.addAccount('good-token');
      expect(await store.accounts().then((a) => a.length), 1);
    });

    test('active account round-trips', () async {
      final store = makeStore();
      await store.addAccount('good-token');
      await store.addAccount('work-token');
      await store.setActive('shyan@work.example');
      expect((await store.active())?.email, 'shyan@work.example');
    });

    test('removeAccount drops it and clears the active pointer', () async {
      final store = makeStore();
      await store.addAccount('good-token');
      await store.setActive('shayanalibuilds@gmail.com');
      await store.removeAccount('shayanalibuilds@gmail.com');
      expect(await store.accounts(), isEmpty);
      expect(await store.active(), isNull);
    });
  });

  group('one click — connectAll binds EVERY Google service at once', () {
    test('writes the token into each Google-scoped integration', () async {
      final vaultStore = InMemorySecureStore();
      final store = makeStore(IntegrationVault(vaultStore));
      await store.addAccount('good-token');
      final connected = await store.connectAll('shayanalibuilds@gmail.com');
      // Every id in the Google service registry got the token.
      for (final id in GoogleAccountStore.kGoogleServices) {
        expect(await vaultStore.read('integration.$id'), 'good-token');
      }
      // The report names real services, not ids.
      expect(connected, contains('Gmail'));
      // The chosen account became the active one.
      expect((await store.active())?.email, 'shayanalibuilds@gmail.com');
    });

    test('the Google registry is the source of truth for scope', () {
      // Gmail rides on the Google account today; any future Google-backed
      // connector lands here and connectAll covers it automatically.
      expect(GoogleAccountStore.kGoogleServices, contains('gmail'));
    });
  });

  group('profile edit form — the identity is editable and persists', () {
    testWidgets('shows the current identity, saves edits to prefs',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Locator.bind(prefs: prefs);
      await tester.pumpWidget(const MaterialApp(home: ProfileEditScreen()));

      expect(find.text('Shyan Ali Jalb'), findsOneWidget);
      expect(find.text('shayanalibuilds@gmail.com'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('profile-name-field')), 'Shyan A. Jalb');
      await tester.enterText(
          find.byKey(const ValueKey('profile-email-field')),
          'shyan@work.example');
      await tester.tap(find.byKey(const ValueKey('profile-save')));
      await tester.pumpAndSettle();

      expect(prefs.getString('profile.name'), 'Shyan A. Jalb');
      expect(prefs.getString('profile.email'), 'shyan@work.example');
    });

    testWidgets('a broken email is rejected and never saved', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Locator.bind(prefs: prefs);
      await tester.pumpWidget(const MaterialApp(home: ProfileEditScreen()));

      await tester.enterText(
          find.byKey(const ValueKey('profile-name-field')), 'Shyan');
      await tester.enterText(
          find.byKey(const ValueKey('profile-email-field')), 'not-an-email');
      await tester.tap(find.byKey(const ValueKey('profile-save')));
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(prefs.getString('profile.email'), isNull);
    });
  });

  group('account selection screen — one tap connects everything', () {
    testWidgets('lists accounts and connects the tapped one',
        (tester) async {
      final vaultStore = InMemorySecureStore();
      final store = makeStore(IntegrationVault(vaultStore));
      await store.addAccount('good-token');
      await store.addAccount('work-token');

      await tester.pumpWidget(MaterialApp(
          home: GoogleAccountsScreen(store: store, report: (_) {})));
      await tester.pumpAndSettle();

      expect(find.text('shayanalibuilds@gmail.com'), findsOneWidget);
      expect(find.text('shyan@work.example'), findsOneWidget);

      // One tap: account becomes active AND every Google service binds.
      await tester.tap(find.byKey(const ValueKey('account-shyan@work.example')));
      await tester.pumpAndSettle();

      expect((await store.active())?.email, 'shyan@work.example');
      expect(await vaultStore.read('integration.gmail'), 'work-token');
    });
  });

  group('the menu shows the real identity and the Google entry', () {
    testWidgets('header reflects persisted name and email', (tester) async {
      SharedPreferences.setMockInitialValues({
        'profile.name': 'Edited Name',
        'profile.email': 'edited@example.com',
      });
      final prefs = await SharedPreferences.getInstance();
      Locator.bind(prefs: prefs);
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));

      expect(find.text('Edited Name'), findsOneWidget);
      expect(find.text('edited@example.com'), findsOneWidget);
    });

    testWidgets('menu has a Google row', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Locator.bind(prefs: prefs);
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));

      expect(find.byKey(const ValueKey('menu-google')), findsOneWidget);
    });
  });

  test('accounts JSON round-trips through the keystore unchanged', () async {
    final s = InMemorySecureStore();
    final store = GoogleAccountStore(
        store: s, verifier: fakeVerify, vault: IntegrationVault(s));
    await store.addAccount('work-token');
    final json =
        jsonDecode(await s.read('google.accounts') as String) as List;
    expect(json.first['email'], 'shyan@work.example');
  });
}
