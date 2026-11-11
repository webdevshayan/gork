import 'package:gork/services/chat_service.dart';
import 'package:gork/services/secure_store.dart';

/// Tiny service locator. Real bindings use the device keystore; tests bind
/// in-memory fakes via bind().
class Locator {
  static SecureStore? _store;
  static ChatService? _chat;

  static void bind({SecureStore? store, ChatService? chat}) {
    if (store != null) _store = store;
    if (chat != null) _chat = chat;
  }

  static void reset() {
    _store = null;
    _chat = null;
  }

  static SecureStore get store => _store ??= SecureStoreImpl();

  static ChatService get chat => _chat ??= ChatService(vault: KeyVault(store));
}
