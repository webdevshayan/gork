import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Key-value storage for secrets, backed by the device keystore
/// (flutter_secure_storage). Keys are namespaced per provider so switching
/// providers never overwrites another provider's key.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// In-memory implementation for tests.
class InMemorySecureStore implements SecureStore {
  final Map<String, String> _map = {};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<void> delete(String key) async => _map.remove(key);
}

/// Device-backed implementation. Keys never leave the phone.
class SecureStoreImpl implements SecureStore {
  final FlutterSecureStorage _storage;

  SecureStoreImpl([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// API-key vault: one namespaced key per provider.
class KeyVault {
  final SecureStore _store;

  KeyVault(this._store);

  static String keyFor(String providerId) => 'apikey.$providerId';

  Future<void> setKey(String providerId, String apiKey) =>
      _store.write(keyFor(providerId), apiKey);

  Future<String?> getKey(String providerId) => _store.read(keyFor(providerId));

  Future<void> clearKey(String providerId) => _store.delete(keyFor(providerId));
}
