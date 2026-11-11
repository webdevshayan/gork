import 'package:flutter_test/flutter_test.dart';

import 'package:gork/services/secure_store.dart';
import 'package:gork/services/vault_store.dart';

void main() {
  test('vault lives in secure storage, not plain prefs', () async {
    final secure = InMemorySecureStore();
    final vault = VaultStore(secure);

    expect(await vault.all(), isEmpty);

    await vault.save(const VaultEntry(
      id: '1',
      title: 'GitHub login',
      username: 'webdevshayan',
      secret: 'hunter2',
      notes: '',
      createdAt: 1,
    ));

    // The encrypted blob exists in secure storage.
    expect(await secure.read('vault.entries'), isNotNull);

    final entries = await vault.all();
    expect(entries.single.title, 'GitHub login');
    expect(entries.single.secret, 'hunter2');
  });

  test('save overwrites by id, delete removes', () async {
    final vault = VaultStore(InMemorySecureStore());

    await vault.save(const VaultEntry(
        id: 'a', title: 'Card', username: '', secret: '4242', notes: '', createdAt: 1));
    await vault.save(const VaultEntry(
        id: 'a', title: 'Card updated', username: '', secret: '1111', notes: '', createdAt: 1));
    await vault.save(const VaultEntry(
        id: 'b', title: 'Mail', username: 'me@x.com', secret: 'pw', notes: '', createdAt: 2));

    final all = await vault.all();
    expect(all.length, 2);
    expect(all.firstWhere((e) => e.id == 'a').title, 'Card updated');
    expect(all.firstWhere((e) => e.id == 'a').secret, '1111');

    await vault.delete('a');
    expect((await vault.all()).map((e) => e.id), ['b']);
  });
}
