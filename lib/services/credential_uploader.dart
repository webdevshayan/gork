import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'locator.dart';
import 'secure_store.dart';

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

  String? get url {
    final v = Locator.prefs.getString('vps.url');
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  Future<String?> _token() async =>
      await (_storeOverride ?? Locator.store).read('vps.token');

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
    final token = await _token();
    final res = await _http.post(
      Uri.parse('$base/v1/credentials/google'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'client_json': json}),
    );
    if (res.statusCode != 201) {
      throw StateError('the VPS refused the upload (HTTP ${res.statusCode})');
    }
  }

  /// Status only — the server never returns the secret itself.
  Future<bool> hasCredentials() async {
    final base = url;
    if (base == null) return false;
    try {
      final token = await _token();
      final res = await _http.get(
        Uri.parse('$base/v1/credentials/google/status'),
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['has_client_json'] == true;
    } catch (_) {
      return false;
    }
  }
}
