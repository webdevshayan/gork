import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'locator.dart';
import 'secure_store.dart';
import 'vps_config.dart';

/// Uploads the Google Cloud Console credentials JSON to the VPS vault and
/// reports its status. The JSON is parsed client-side (structure validation),
/// POSTed once, and NEVER read back — the server stores it sealed and only
/// ever answers with a boolean + timestamp.
class GoogleCredentialsUploader {
  GoogleCredentialsUploader({http.Client? client, SecureStore? store})
      : _client = client,
        _storeOverride = store;

  final http.Client? _client;
  final SecureStore? _storeOverride;

  http.Client get _http => _client ?? Locator.httpClient;

  /// ONE VPS connection (Movement 63): like the OAuth flow, the uploader
  /// used to read only the direct `vps.token` key — installs configured
  /// through a legacy slot uploaded with NO auth and the daemon answered
  /// "bad or missing X-Gork-Secret". [VpsConfig] resolves url + secret the
  /// same way as everything else server-side.
  VpsConfig get _vps => VpsConfig(
      prefs: Locator.prefs, store: _storeOverride ?? Locator.store);

  String? get url => _vps.url;

  Future<String?> _token() => _vps.token();

  Future<Map<String, String>> _headers() async {
    final t = await _token();
    return {
      'Content-Type': 'application/json',
      if (t != null && t.isNotEmpty) 'X-Gork-Secret': t,
    };
  }

  bool get configured => url != null;

  /// Validates and uploads the credentials file. Throws [ArgumentError] with
  /// a helpful message when the file is not a Cloud Console credentials
  /// JSON; throws [StateError] when no VPS is configured.
  Future<void> upload(String path) async {
    final base = url;
    if (base == null) {
      throw StateError('No VPS configured yet — set it in Security first.');
    }
    final raw = File(path).readAsStringSync();
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      throw ArgumentError('That file is not valid JSON credentials.');
    }
    final isOAuthClient =
        json.containsKey('installed') || json.containsKey('web');
    final isServiceAccount = json.containsKey('private_key') &&
        json.containsKey('client_email');
    if (!isOAuthClient && !isServiceAccount) {
      throw ArgumentError(
          'Not a Cloud Console credentials file — expected an OAuth client '
          '("installed"/"web") or a service-account JSON.');
    }
    final res = await _http.post(
      Uri.parse('$base/v1/credentials/google'),
      headers: await _headers(),
      body: jsonEncode({'client_json': json}),
    );
    if (res.statusCode != 201) {
      throw StateError('the VPS refused the upload (HTTP ${res.statusCode})');
    }
  }

  /// Movement 69 — the ONE-TAP path: the user creates an ANDROID OAuth
  /// client in Cloud Console (package dev.shayan.gork + their SHA-1) and
  /// pastes ONLY its client id here. No credentials.json, no secret, no
  /// redirect-URI dance — the daemon exchanges installed-app codes without
  /// a client secret.
  Future<void> uploadClientId(String clientId) async {
    final base = url;
    if (base == null) {
      throw StateError('no VPS configured — set it up in Cloud Computer');
    }
    final res = await _http.post(
      Uri.parse('$base/v1/credentials/google'),
      headers: await _headers(),
      body: jsonEncode({
        'client_json': {'android': {'client_id': clientId.trim()}},
      }),
    );
    if (res.statusCode != 201) {
      throw StateError('the VPS refused the client id (HTTP ${res.statusCode})');
    }
  }

  /// Status only — the server never returns the secret itself.
  Future<bool> hasCredentials() async {
    final base = url;
    if (base == null) return false;
    try {
      final res = await _http.get(
        Uri.parse('$base/v1/credentials/google/status'),
        headers: await _headers(),
      );
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['has_client_json'] == true;
    } catch (_) {
      return false;
    }
  }
}
