import 'package:shared_preferences/shared_preferences.dart';

import 'chat_service.dart';
import 'history_store.dart';
import 'memory_store.dart';
import 'notifications.dart';
import 'projects_store.dart';
import 'scheduler.dart';
import 'secure_store.dart';
import 'tasks_store.dart';
import 'vault_store.dart';

/// Tiny service locator. Real bindings use the device keystore; tests bind
/// in-memory fakes via bind().
class Locator {
  static SecureStore? _store;
  static ChatService? _chat;
  static SharedPreferences? _prefs;
  static Scheduler? _scheduler;
  static NotificationService? _notifications;

  static void bind({
    SecureStore? store,
    ChatService? chat,
    SharedPreferences? prefs,
    Scheduler? scheduler,
    NotificationService? notifications,
  }) {
    if (store != null) _store = store;
    if (chat != null) _chat = chat;
    if (prefs != null) _prefs = prefs;
    if (scheduler != null) _scheduler = scheduler;
    if (notifications != null) _notifications = notifications;
  }

  static void reset() {
    _store = null;
    _chat = null;
    _prefs = null;
    _scheduler = null;
    _notifications = null;
  }

  static SecureStore get store => _store ??= SecureStoreImpl();

  static ChatService get chat => _chat ??= ChatService(vault: KeyVault(store));

  static SharedPreferences get prefs => _prefs!;

  static HistoryStore get history => HistoryStore(prefs);

  static MemoryStore get memory => MemoryStore(prefs);

  static ProjectsStore get projects => ProjectsStore(prefs);

  static VaultStore get vault => VaultStore(store);

  static TasksStore get tasks => TasksStore(prefs);

  static NotificationService get notifications =>
      _notifications ??= NotificationService();

  static Scheduler get scheduler =>
      _scheduler ??= Scheduler(tasks, chat: chat, onNotify: notifications.show);
}
