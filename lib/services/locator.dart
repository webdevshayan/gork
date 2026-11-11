import 'package:shared_preferences/shared_preferences.dart';

import 'chat_service.dart';
import 'history_store.dart';
import 'memory_store.dart';
import 'secure_store.dart';

/// Tiny service locator. Real bindings use the device keystore; tests bind
/// in-memory fakes via bind().
class Locator {
  static SecureStore? _store;
  static ChatService? _chat;
  static SharedPreferences? _prefs;

  static void bind({SecureStore? store, ChatService? chat, SharedPreferences? prefs}) {
    if (store != null) _store = store;
    if (chat != null) _chat = chat;
    if (prefs != null) _prefs = prefs;
  }

  static void reset() {
    _store = null;
    _chat = null;
    _prefs = null;
  }

  static SecureStore get store => _store ??= SecureStoreImpl();

  static ChatService get chat => _chat ??= ChatService(vault: KeyVault(store));

  static SharedPreferences get prefs => _prefs!;

  static HistoryStore get history => HistoryStore(prefs);

  static MemoryStore get memory => MemoryStore(prefs);
}
