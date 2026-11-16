import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'locator.dart';
import 'secure_store.dart';

/// The first-run intro: a handful of short messages that land one after
/// another, like a real person sending them from behind the app.
///
/// The MESSAGES ARE GENERATED IN ONE REQUEST on the VPS — a single provider
/// call returns the whole array, personalised by name — and the client then
/// sends them out as SEPARATE bubbles with human-like timing. When the VPS
/// is not configured (or unreachable) the reference set plays instead, so
/// the very first run is always good.
class IntroService {
  IntroService({http.Client? client, SharedPreferences? prefs, SecureStore? store})
      : _client = client,
        _prefsOverride = prefs,
        _storeOverride = store;

  final http.Client? _client;
  final SharedPreferences? _prefsOverride;
  final SecureStore? _storeOverride;

  SharedPreferences get prefs => _prefsOverride ?? Locator.prefs;
  SecureStore get _store => _storeOverride ?? Locator.store;
  http.Client get _http => _client ?? Locator.httpClient;

  String? get url {
    final v = prefs.getString('vps.url');
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  /// The intro lines. One request to the VPS when configured; the local
  /// reference set otherwise. Never throws.
  Future<List<String>> fetchIntro({required String name, String? email}) async {
    final base = url;
    if (base == null) return defaults(name);
    try {
      final res = await _http.post(
        Uri.parse('$base/v1/onboarding/intro'),
        headers: {
          'Content-Type': 'application/json',
          if (await _store.read('vps.token') != null)
            'Authorization': 'Bearer ${await _store.read('vps.token')}',
        },
        body: jsonEncode({'name': name, if (email != null) 'email': email}),
      );
      if (res.statusCode != 200) return defaults(name);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final messages = (body['messages'] as List? ?? const [])
          .whereType<String>()
          .where((m) => m.trim().isNotEmpty)
          .toList();
      return messages.isEmpty ? defaults(name) : messages;
    } catch (_) {
      return defaults(name);
    }
  }

  /// The shipped reference set — warm, short, one idea per bubble.
  static List<String> defaults(String name) => [
        'Hey $name, I\u2019m Gork.',
        'I keep track of life and work, trips and groceries. I pay bills '
            'securely and find opportunities you\u2019ll love.',
        'With your permission, I\u2019ll connect your email and calendar, '
            'catch up on your life, and learn how I can help.',
        'In the meantime, how\u2019s your day going?',
      ];
}
