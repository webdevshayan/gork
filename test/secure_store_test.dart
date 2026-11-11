import 'package:flutter_test/flutter_test.dart';

import 'package:gork/services/secure_store.dart';

void main() {
  group('InMemorySecureStore', () {
    test('write, read, overwrite, delete', () async {
      final store = InMemorySecureStore();

      expect(await store.read('a'), isNull);

      await store.write('a', 'one');
      expect(await store.read('a'), 'one');

      await store.write('a', 'two');
      expect(await store.read('a'), 'two');

      await store.delete('a');
      expect(await store.read('a'), isNull);
    });
  });

  group('KeyVault namespaces keys per provider', () {
    test('switching providers never overwrites another key', () async {
      final vault = KeyVault(InMemorySecureStore());

      await vault.setKey('openai', 'sk-openai-key');
      await vault.setKey('openrouter', 'sk-or-key');
      await vault.setKey('anthropic', 'ak-key');

      expect(await vault.getKey('openai'), 'sk-openai-key');
      expect(await vault.getKey('openrouter'), 'sk-or-key');
      expect(await vault.getKey('anthropic'), 'ak-key');

      // Overwrite openai; others untouched.
      await vault.setKey('openai', 'sk-new');
      expect(await vault.getKey('openai'), 'sk-new');
      expect(await vault.getKey('openrouter'), 'sk-or-key');

      // Clear anthropic; others untouched.
      await vault.clearKey('anthropic');
      expect(await vault.getKey('anthropic'), isNull);
      expect(await vault.getKey('openai'), 'sk-new');
    });
  });
}
