import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'secure_store.dart';

/// The ONE VPS connection — one URL and one shared secret for everything
/// server-side: chat handoff (outbox), scheduled-task handoff, the browser
/// agent, the sealed vault, memory rooms and the credentials upload.
///
/// Keys live under `vps.*`. Older installs configured the task daemon under
/// `handoff.*` and the browser backend under `cloudcomputer.config`; those
/// are honored as read-only fallbacks so nothing breaks, but every write
/// goes to `vps.*` — one setup, same states, same server.
class VpsConfig {
  final SharedPreferences prefs;
  final SecureStore store;

  VpsConfig({required this.prefs, required this.store});

  static const String kUrl = 'vps.url';
  static const String kToken = 'vps.token';
  static const String kNtfy = 'vps.ntfy';

  /// Set once this app has MANAGED the token (saved or deliberately
  /// cleared). While true, the legacy fallbacks stay out of the way — a
  /// cleared token means NO token, not "resurrect the old daemon secret".
  static const String kHasToken = 'vps.hasToken';

  /// The VPS base URL. Resolution order: `vps.url`, then the legacy task
  /// daemon URL (`handoff.url`), then the AgentVPS endpoint saved in the
  /// cloud-computer picker — all the same server in practice. Trailing
  /// slashes are stripped so path joins stay clean.
  String? get url {
    String? clean(String? raw) {
      if (raw == null) return null;
      final t = raw.trim();
      if (t.isEmpty) return null;
      return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
    }

    return clean(prefs.getString(kUrl)) ??
        clean(prefs.getString('handoff.url')) ??
        clean(_agentVpsEndpoint());
  }

  /// Parses `cloudcomputer.config` and answers the endpoint ONLY when the
  /// chosen backend is the self-hosted agent VPS — a Browser Use or
  /// openbrowse endpoint is a third-party service, not the gork daemon.
  String? _agentVpsEndpoint() {
    final raw = prefs.getString('cloudcomputer.config');
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['backend'] != 'agentvps') return null;
      return json['endpoint'] as String?;
    } catch (_) {
      return null;
    }
  }

  bool get configured => url != null;

  /// The shared secret. Falls back to the legacy daemon secret only while
  /// this app has never managed the token itself.
  Future<String?> token() async {
    final direct = await store.read(kToken);
    if (direct != null && direct.isNotEmpty) return direct;
    if (prefs.getBool(kHasToken) == true) return null;
    final legacy = await store.read('handoff.secret');
    if (legacy != null && legacy.isNotEmpty) return legacy;
    final raw = prefs.getString('cloudcomputer.config');
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['backend'] == 'agentvps') {
          final key = json['apiKey'] as String?;
          if (key != null && key.isNotEmpty) return key;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Saves the connection. A null [token] keeps the saved one; an empty
  /// string clears it (and stays cleared — no legacy resurrection).
  Future<void> save(String url, {String? token}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(kUrl);
    } else {
      await prefs.setString(kUrl, trimmed);
    }
    if (token == null) return;
    await prefs.setBool(kHasToken, true);
    if (token.trim().isEmpty) {
      await store.delete(kToken);
    } else {
      await store.write(kToken, token.trim());
    }
  }

  Future<void> clear() async {
    await prefs.remove(kUrl);
    await prefs.remove(kHasToken);
    await store.delete(kToken);
  }

  String? get ntfyTopic {
    final direct = prefs.getString(kNtfy);
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    final legacy = prefs.getString('handoff.ntfy');
    if (legacy != null && legacy.trim().isNotEmpty) return legacy.trim();
    return null;
  }

  Future<void> setNtfyTopic(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(kNtfy);
    } else {
      await prefs.setString(kNtfy, trimmed);
    }
  }
}
