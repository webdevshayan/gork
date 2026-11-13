import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/providers.dart';
import 'integrations.dart';
import 'secure_store.dart';
import 'tasks_store.dart';

/// Handoff: the phone app and the user's VPS daemon share the task list.
///
/// The daemon (daemon/ in this repo) exposes /health, /tasks, /run and can
/// push results to the phone via ntfy. This service syncs with it over REST.
/// An optional shared secret (X-Gork-Secret) protects the daemon endpoints.
class HandoffService {
  final http.Client client;
  final SharedPreferences prefs;
  final SecureStore store;
  final TasksStore tasks;

  HandoffService({
    required this.client,
    required this.prefs,
    required this.store,
    required this.tasks,
  });

  static const String kUrl = 'handoff.url';
  static const String kNtfy = 'handoff.ntfy';
  static const String kSecret = 'handoff.secret';

  String? get url {
    final raw = prefs.getString(kUrl) ?? '';
    if (raw.isEmpty) return null;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  bool get configured => url != null;

  Future<void> setUrl(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(kUrl);
    } else {
      await prefs.setString(kUrl, trimmed);
    }
  }

  Future<void> setNtfyTopic(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(kNtfy);
    } else {
      await prefs.setString(kNtfy, trimmed);
    }
  }

  String? get ntfyTopic => prefs.getString(kNtfy);

  Future<String?> secret() => store.read(kSecret);

  Future<void> setSecret(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await store.delete(kSecret);
    } else {
      await store.write(kSecret, trimmed);
    }
  }

  Future<dynamic> _call(String method, String path,
      {Map<String, dynamic>? body}) async {
    final base = url;
    if (base == null) {
      throw const IntegrationException(
          'Daemon not configured — set its URL in Cloud Computer');
    }
    final s = await secret();
    return jsonRequest(client, method, Uri.parse('$base$path'),
        headers: {
          if (s != null && s.isNotEmpty) 'X-Gork-Secret': s,
          'Content-Type': 'application/json',
        },
        body: body);
  }

  /// Test connection.
  Future<String> ping() async {
    final data = await _call('GET', '/health') as Map<String, dynamic>;
    if (data['status'] != 'ok') {
      throw const IntegrationException('daemon answered but is not ok');
    }
    return 'daemon alive';
  }

  /// Push every local task to the daemon (upsert by id).
  Future<String> pushTasks() async {
    final local = tasks.all();
    for (final t in local) {
      await _call('POST', '/tasks', body: t.toJson());
    }
    return 'pushed ${local.length} task(s) to the daemon';
  }

  /// Pull the daemon's task list into the phone (upsert by id). The daemon
  /// Task has no createdAt, so pulled tasks get "now" as createdAt.
  Future<String> pullTasks() async {
    final data = await _call('GET', '/tasks') as Map<String, dynamic>;
    final list = data['tasks'] as List? ?? [];
    var merged = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final raw in list) {
      final j = raw as Map<String, dynamic>;
      final prompt = j['prompt'] as String? ?? '';
      if (prompt.isEmpty) continue;
      await tasks.save(ScheduledTask(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Untitled',
        prompt: prompt,
        repeatMinutes: (j['repeatMinutes'] as num?)?.toInt() ?? 60,
        enabled: j['enabled'] as bool? ?? true,
        lastRun: j['lastRun'] as int?,
        createdAt: (j['createdAt'] as num?)?.toInt() ?? now,
      ));
      merged++;
    }
    return 'pulled $merged task(s) from the daemon';
  }

  /// Ask the daemon to run its due tasks right now.
  Future<String> triggerRun() async {
    final data = await _call('POST', '/run') as Map<String, dynamic>;
    final ran = (data['ran'] as num?)?.toInt() ?? 0;
    return '$ran due task(s) executed on the daemon';
  }

  /// Push the phone's config to the daemon in one action: the first
  /// provider that has a key (api key, base URL, model), every connected
  /// connector token, and the ntfy topic. The daemon writes them into its
  /// config.env and applies the LLM config live — no file editing on the
  /// VPS, ever.
  Future<String> pushConfig() async {
    final base = url;
    if (base == null) {
      throw const IntegrationException(
          'Daemon not configured — set its URL in Cloud Computer');
    }

    // LLM: the first provider (in registry order) that has a key saved.
    final config = <String, String>{};
    for (final p in kProviders) {
      final key = await store.read('apikey.${p.id}');
      if (key != null && key.isNotEmpty) {
        config['GORK_API_KEY'] = key;
        config['GORK_BASE_URL'] = p.baseURL;
        config['GORK_MODEL'] = p.defaultModel;
        break;
      }
    }

    // Connectors: every integration with a stored token.
    final connectors = <String, String>{};
    for (final i in kIntegrations) {
      final token = await store.read(IntegrationVault.keyFor(i.id));
      if (token != null && token.isNotEmpty) {
        connectors[i.id] = token;
      }
    }

    // ntfy topic rides along so scheduled pushes land on this phone.
    final topic = ntfyTopic;
    if (topic != null && topic.isNotEmpty) {
      config['NTFY_TOPIC'] = topic;
    }

    if (config.isEmpty && connectors.isEmpty) {
      return 'nothing to sync — save a provider key or connect a service first';
    }

    final data = await _call('POST', '/config',
        body: {'config': config, 'connectors': connectors}) as Map<String, dynamic>;
    final saved = (data['saved'] as List? ?? []).length;
    return 'synced $saved key(s) to the daemon';
  }
}
