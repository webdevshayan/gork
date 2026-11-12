import 'dart:convert';

import 'package:http/http.dart' as http;

import 'github_service.dart';
import 'secure_store.dart';

/// Service integrations — BYO token, same philosophy as BYOK.
///
/// gork talks to the services the user already pays for. The user pastes
/// their own token; it is stored encrypted in the device keystore and sent
/// only to that service's official API endpoint.
class IntegrationDef {
  final String id;
  final String name;
  final String tokenLabel;
  final String tokenHint;

  const IntegrationDef({
    required this.id,
    required this.name,
    required this.tokenLabel,
    required this.tokenHint,
  });
}

const List<IntegrationDef> kIntegrations = [
  IntegrationDef(
    id: 'github',
    name: 'GitHub',
    tokenLabel: 'Personal access token',
    tokenHint:
        'github.com/settings/tokens — fine-grained or classic, '
        'scopes: repo, notifications',
  ),
  IntegrationDef(
    id: 'slack',
    name: 'Slack',
    tokenLabel: 'Bot token (xoxb-…)',
    tokenHint:
        'api.slack.com/apps — your app needs scopes: '
        'chat:write, channels:read',
  ),
  IntegrationDef(
    id: 'strava',
    name: 'Strava',
    tokenLabel: 'Access token',
    tokenHint: 'strava.com/settings/api — create an app, then authorize',
  ),
  IntegrationDef(
    id: 'spotify',
    name: 'Spotify',
    tokenLabel: 'OAuth access token',
    tokenHint:
        'developer.spotify.com/console — Premium required for playback; '
        'scopes: user-read-playback-state, user-modify-playback-state',
  ),
  IntegrationDef(
    id: 'gmail',
    name: 'Gmail',
    tokenLabel: 'OAuth access token',
    tokenHint:
        'developers.google.com/oauthplayground — scope: '
        'https://mail.google.com/ or gmail.readonly',
  ),
  IntegrationDef(
    id: 'paypal',
    name: 'PayPal',
    tokenLabel: 'Client ID : Secret',
    tokenHint:
        'developer.paypal.com/dashboard/applications — paste as '
        'client_id:secret (live or sandbox base URL below)',
  ),
];

IntegrationDef? integrationById(String id) {
  for (final i in kIntegrations) {
    if (i.id == id) return i;
  }
  return null;
}

/// Tokens live in the keystore, namespaced `integration.<id>`.
class IntegrationVault {
  final SecureStore store;

  IntegrationVault(this.store);

  static String keyFor(String id) => 'integration.$id';

  Future<String?> token(String id) => store.read(keyFor(id));

  Future<void> setToken(String id, String token) =>
      store.write(keyFor(id), token);

  Future<void> clearToken(String id) => store.delete(keyFor(id));
}

class IntegrationException implements Exception {
  final int? status;
  final String message;

  const IntegrationException(this.message, {this.status});

  @override
  String toString() => status == null
      ? 'IntegrationException: $message'
      : 'IntegrationException ${status}: $message';
}

/// One shared REST helper for every integration: bearer-style JSON calls
/// with uniform error mapping. Services with different auth (Slack ok-flag,
/// PayPal basic auth) build on it or roll their own request.
Future<dynamic> jsonRequest(
  http.Client client,
  String method,
  Uri uri, {
  Map<String, String> headers = const {},
  Object? body,
  String? basicAuth,
}) async {
  final req = http.Request(method, uri)..headers.addAll(headers);
  if (basicAuth != null) req.headers['Authorization'] = 'Basic $basicAuth';
  if (body != null) req.body = jsonEncode(body);
  final http.Response res;
  try {
    res = await http.Response.fromStream(await client.send(req));
  } catch (e) {
    throw IntegrationException('network error: $e');
  }
  if (res.statusCode == 401 || res.statusCode == 403) {
    throw IntegrationException('unauthorized — check the token',
        status: res.statusCode);
  }
  if (res.statusCode == 429) {
    throw const IntegrationException('rate limited — try again later',
        status: 429);
  }
  if (res.statusCode >= 400) {
    throw IntegrationException('http ${res.statusCode}: ${briefBody(res.body)}',
        status: res.statusCode);
  }
  if (res.body.isEmpty) return const <String, dynamic>{};
  return jsonDecode(res.body);
}

String briefBody(String body) {
  final t = body.trim();
  return t.length > 200 ? t.substring(0, 200) : t;
}

/// Facade over all integrations. Services are constructed lazily with the
/// stored token; null when that integration is not connected.
class Integrations {
  final SecureStore store;
  final http.Client client;

  const Integrations(this.store, this.client);

  IntegrationVault get vault => IntegrationVault(store);

  Future<bool> isConnected(String id) async {
    final t = await vault.token(id);
    return t != null && t.isNotEmpty;
  }

  /// GitHubService built from the stored token; null when not connected.
  Future<GitHubService?> githubService() async {
    final t = await vault.token('github');
    if (t == null || t.isEmpty) return null;
    return GitHubService(client: client, token: () async => t);
  }

  /// Null on success, error text otherwise. Fill cases per movement.
  /// [tokenOverride] lets the UI test a freshly pasted token before saving.
  Future<String?> testConnection(String id, {String? tokenOverride}) async {
    final t = tokenOverride?.trim().isNotEmpty == true
        ? tokenOverride!.trim()
        : await vault.token(id);
    if (t == null || t.isEmpty) return 'No token saved yet';
    try {
      switch (id) {
        case 'github':
          await GitHubService(client: client, token: () async => t).whoAmI();
          break;
        default:
          return 'Token saved (no live test for $id yet)';
      }
    } on IntegrationException catch (e) {
      return e.message;
    }
    return null;
  }
}
