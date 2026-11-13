import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/wallet_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/vault_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 34: the old password "vault" is now the Wallet — the wallets
/// (and their keys) the user chooses to give their own AI access to.
/// Entries stay encrypted on-device; AI access is a per-wallet toggle.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
    );
  });

  test('aiAccess round-trips through the encrypted store', () async {
    final store = VaultStore(InMemorySecureStore());
    const entry = VaultEntry(
      id: '1',
      title: 'Metamask',
      username: '0xabc',
      secret: 'seed phrase words here',
      notes: 'hot wallet',
      createdAt: 123,
      aiAccess: true,
    );
    await store.save(entry);
    final loaded = await store.all();
    expect(loaded.single.aiAccess, isTrue);

    // entries written by older versions (no aiAccess field) stay readable
    await store.save(const VaultEntry(
      id: '2',
      title: 'Old entry',
      username: '',
      secret: 's',
      notes: '',
      createdAt: 456,
    ));
    final two = await store.all();
    expect(two.firstWhere((e) => e.id == '2').aiAccess, isFalse);
  });

  testWidgets('empty wallet explains what it is for', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WalletScreen()));
    await tester.pump();
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.textContaining('wallets'), findsOneWidget);
    expect(find.textContaining('AI'), findsOneWidget);
  });

  testWidgets('add a wallet, then grant the AI access with one toggle',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WalletScreen()));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('wallet-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Metamask');
    await tester.enterText(find.byType(TextField).at(1), '0xabc123');
    await tester.enterText(find.byType(TextField).at(2), 'seed phrase words');
    await tester.tap(find.text('Save wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Metamask'), findsOneWidget);
    expect(find.text('AI access off'), findsOneWidget);

    final saved = (await Locator.vault.all()).single;
    await tester.tap(find.byKey(ValueKey('ai-access-${saved.id}')));
    await tester.pumpAndSettle();
    expect(find.text('AI access on'), findsOneWidget);

    final entry = (await Locator.vault.all()).single;
    expect(entry.aiAccess, isTrue);
  });
}
