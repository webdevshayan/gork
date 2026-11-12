import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_service.dart';
import 'chat_service.dart';
import 'cloud_computer_store.dart';
import 'history_store.dart';
import 'handoff_service.dart';
import 'inbox_service.dart';
import 'integrations.dart';
import 'memory_store.dart';
import 'notifications.dart';
import 'panels_store.dart';
import 'projects_store.dart';
import 'scheduler.dart';
import 'secure_store.dart';
import 'tasks_store.dart';
import 'tool_registry.dart';
import 'vault_store.dart';
import 'weather_service.dart';

/// Tiny service locator. Real bindings use the device keystore; tests bind
/// in-memory fakes via bind().
class Locator {
  static SecureStore? _store;
  static ChatService? _chat;
  static SharedPreferences? _prefs;
  static Scheduler? _scheduler;
  static NotificationService? _notifications;
  static http.Client? _httpClient;

  static void bind({
    SecureStore? store,
    ChatService? chat,
    SharedPreferences? prefs,
    Scheduler? scheduler,
    NotificationService? notifications,
    http.Client? httpClient,
  }) {
    if (store != null) _store = store;
    if (chat != null) _chat = chat;
    if (prefs != null) _prefs = prefs;
    if (scheduler != null) _scheduler = scheduler;
    if (notifications != null) _notifications = notifications;
    if (httpClient != null) _httpClient = httpClient;
  }

  static void reset() {
    _store = null;
    _chat = null;
    _prefs = null;
    _scheduler = null;
    _notifications = null;
    _httpClient = null;
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

  static CloudComputerStore get cloudComputer => CloudComputerStore(prefs);

  static http.Client get httpClient => _httpClient ??= http.Client();

  static WeatherService get weather => WeatherService(httpClient);

  static PanelsStore get panels => PanelsStore(prefs);

  static ToolRegistry get toolRegistry => ToolRegistry(
        memory: memory,
        projects: projects,
        tasks: tasks,
        panels: panels,
        vault: vault,
        weather: weather,
        integrations: integrations,
        handoff: handoff,
      );

  static AgentService get agent =>
      AgentService(chat, toolRegistry, memory);

  static InboxService get inbox => InboxService(prefs, weather);

  static Integrations get integrations => Integrations(store, httpClient);

  static HandoffService get handoff => HandoffService(
        client: httpClient,
        prefs: prefs,
        store: store,
        tasks: tasks,
      );

  static double get ambientLat =>
      prefs.getDouble('ambient.lat') ?? 24.8607; // Karachi default
  static double get ambientLon =>
      prefs.getDouble('ambient.lon') ?? 67.0011;
}
