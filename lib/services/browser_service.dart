import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'locator.dart';
import 'secure_store.dart';

/// Client for the AI's full browser on the VPS and the accounts data.
///
/// The secure fill protocol lives here too: the AI asks for a LABEL it
/// generated, the VPS fills the ACTIVE input from its sealed vault, and the
/// secret is never in any response — the AI model can never see it, no
/// matter how insecure the website is.
class BrowserService {
  BrowserService({http.Client? client, SharedPreferences? prefs, SecureStore? store})
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

  bool get configured => url != null;

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// One browser op (navigate / click / type / read / screenshot). Returns
  /// the result JSON or null when the VPS is unconfigured/unreachable.
  Future<Map<String, dynamic>?> op(String action,
      {String session = 'default', Map<String, dynamic> args = const {}}) async {
    final base = url;
    if (base == null) return null;
    try {
      final res = await _http.post(
        Uri.parse('$base/v1/browser/op'),
        headers: _headers(await _store.read('vps.token')),
        body: jsonEncode({'session': session, 'action': action, ...args}),
      );
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// The secure fill: the AI names a LABEL, the VPS fills the active input
  /// from the sealed vault. The response NEVER carries the value.
  Future<Map<String, dynamic>?> fillSecret(String label,
      {String session = 'default'}) =>
      op('fill_secret', session: session, args: {'label': label});

  /// The labels in the VPS's sealed vault — the names the AI can fill by.
  /// Labels only: values never travel. Returns null when the VPS is
  /// unreachable (or answers non-200) so callers can show an honest
  /// "couldn't reach" state instead of a fake "nothing saved".
  Future<List<String>?> vaultLabels() async {
    final base = url;
    if (base == null) return null;
    try {
      final res = await _http.get(
        Uri.parse('$base/v1/vault'),
        headers: _headers(await _store.read('vps.token')),
      );
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return [
        for (final e in (body['entries'] as List? ?? const []))
          ((e as Map<String, dynamic>)['label'] ?? '').toString()
      ].where((l) => l.isNotEmpty).toList();
    } catch (_) {
      return null;
    }
  }

  /// Every account the user has logged into from the app, per website.
  Future<List<Map<String, dynamic>>> accounts() async {
    final base = url;
    if (base == null) return const [];
    try {
      final res = await _http.get(
        Uri.parse('$base/v1/accounts'),
        headers: _headers(await _store.read('vps.token')),
      );
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return [
        for (final a in (body['accounts'] as List? ?? const []))
          a as Map<String, dynamic>
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Records a login (site + username + vault label) on the VPS. Secrets
  /// are never part of this call.
  Future<bool> saveAccount({
    required String site,
    required String username,
    String label = '',
  }) async {
    final base = url;
    if (base == null) return false;
    try {
      final res = await _http.post(
        Uri.parse('$base/v1/accounts'),
        headers: _headers(await _store.read('vps.token')),
        body: jsonEncode({'site': site, 'username': username, 'label': label}),
      );
      return res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Tool entry point for `browser` — args as produced by the model:
  /// {"action": "navigate"|"click"|"type"|"read"|"screenshot"|"fill_secret",
  ///  "session"?, "url"?/"selector"?/"text"?/"label"?}
  Future<String> execute(Map<String, dynamic> args) async {
    if (!configured) {
      return 'error: the AI browser lives on your VPS — configure it in '
          'Cloud Computer first';
    }
    final action = (args['action'] as String?)?.trim() ?? '';
    if (action.isEmpty) return 'error: action is required';
    final session = (args['session'] as String?)?.trim();
    final result = await op(
      action,
      session: (session == null || session.isEmpty) ? 'default' : session,
      args: args,
    );
    if (result == null) {
      return 'error: the VPS did not answer — browser op not performed';
    }
    return jsonEncode(result);
  }
}
