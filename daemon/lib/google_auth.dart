import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'browser_agent.dart';

/// Movement 62 — the user's server becomes the Google login: the
/// credentials.json the user uploaded once (sealed in the vault) IS the
/// OAuth client, and this class drives the whole consent flow with it.
///
/// Flow (phone-side loopback — Google's supported "Desktop app" pattern):
///   1. phone opens a local HTTP listener on 127.0.0.1:<ephemeral port>
///   2. consentUrl builds the Google consent URL (redirect_uri = loopback)
///      from the SEALED client_json — the client secret never leaves the box
///   3. user logs in + consents in their browser; Google redirects to
///      http://127.0.0.1:<port>/callback?code=...&scope=... ON THE PHONE
///   4. phone POSTs the code here; the daemon exchanges it (client_secret
///      from the vault), fetches the userinfo profile (name + email), and
///      seals the refresh token + profile in the vault
///   5. phone polls /v1/google/accounts and shows the account + which
///      tools connected (Gmail / Docs / YouTube — derived from the granted
///      scopes)
class GoogleAuth {
  GoogleAuth({String? vaultDir, http.Client? client})
      : _vaultDir = vaultDir,
        _client = client ?? http.Client();

  final String? _vaultDir;
  final http.Client _client;

  static const String _tokenEndpoint =
      'https://oauth2.googleapis.com/token';
  static const String _userinfoEndpoint =
      'https://openidconnect.googleapis.com/v1/userinfo';

  /// The tool set gork connects at once — the phone shows these as chips.
  ///
  /// NOTE (2026-11-19): there is NO bare
  /// `https://www.googleapis.com/auth/gmail` scope — Google answered the
  /// whole consent with "Some requested scopes were invalid". Gmail scopes
  /// are granular; `gmail.modify` is the one that covers reading, sending,
  /// labels and trash WITHOUT permanent delete.
  static const List<(String, String)> kToolScopes = [
    ('gmail', 'https://www.googleapis.com/auth/gmail.modify'),
    ('docs', 'https://www.googleapis.com/auth/documents'),
    ('youtube', 'https://www.googleapis.com/auth/youtube'),
  ];

  static const List<String> kIdentityScopes = [
    'openid',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
  ];

  /// The sealed OAuth client: ('installed'|'web', {client_id, ...}), or
  /// null when no credentials.json was uploaded yet.
  (String, Map<String, dynamic>)? _clientJson() {
    if (_vaultDir == null) return null;
    final raw = readVault(_vaultDir)['google_credentials'];
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['installed'] is Map) return ('installed', (json['installed'] as Map).cast<String, dynamic>());
      if (json['web'] is Map) return ('web', (json['web'] as Map).cast<String, dynamic>());
    } catch (_) {}
    return null;
  }

  /// Builds the consent URL for the given redirect_uri. Throws
  /// [StateError] with a human message when no client is sealed yet.
  String consentUrl(String redirectUri) {
    final client = _clientJson();
    if (client == null) {
      throw StateError('no credentials.json on the VPS yet — upload it '
          'first (Google screen → Upload credentials.json)');
    }
    final (_, config) = client;
    final clientId = config['client_id']?.toString() ?? '';
    if (clientId.isEmpty) {
      throw StateError('the sealed credentials.json has no client_id');
    }
    final scopes = [
      ...kIdentityScopes,
      for (final (_, scope) in kToolScopes) scope,
    ];
    return Uri.parse('https://accounts.google.com/o/oauth2/v2/auth')
        .replace(queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scopes.join(' '),
      'access_type': 'offline', // a refresh token, so it outlives the hour
      'prompt': 'consent', // force the refresh token on re-consent too
    }).toString();
  }

  /// Which tools a granted-scope string covers.
  static List<String> toolsFromScopes(String scopes) {
    return [
      for (final (tool, scope) in kToolScopes)
        if (scopes.contains(scope)) tool,
    ];
  }

  /// Exchanges an authorization code for tokens, fetches the profile and
  /// seals everything in the vault. Returns {email, name, tools}.
  Future<Map<String, dynamic>> exchange(
      String code, String redirectUri) async {
    final client = _clientJson();
    if (client == null || _vaultDir == null) {
      throw StateError('no credentials.json on the VPS — upload it first');
    }
    final (kind, config) = client;
    final tokenRes = await _client.post(Uri.parse(_tokenEndpoint), body: {
      'code': code,
      'client_id': config['client_id']?.toString() ?? '',
      'client_secret': config['client_secret']?.toString() ?? '',
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
    });
    if (tokenRes.statusCode != 200) {
      throw StateError('Google refused the token exchange '
          '(HTTP ${tokenRes.statusCode}): ${_brief(tokenRes.body)}');
    }
    final tokens = jsonDecode(tokenRes.body) as Map<String, dynamic>;
    final accessToken = tokens['access_token']?.toString() ?? '';
    final refreshToken = tokens['refresh_token']?.toString() ?? '';
    final scopes = tokens['scope']?.toString() ?? '';

    // The profile comes from the userinfo endpoint with the fresh access
    // token (id_token parsing would also work, but this is one GET).
    final profile = await _client.get(Uri.parse(_userinfoEndpoint),
        headers: {'authorization': 'Bearer $accessToken'});
    if (profile.statusCode != 200) {
      throw StateError('Google refused the profile fetch '
          '(HTTP ${profile.statusCode}): ${_brief(profile.body)}');
    }
    final info = jsonDecode(profile.body) as Map<String, dynamic>;
    final email = info['email']?.toString() ?? '';
    if (email.isEmpty) {
      throw StateError('Google did not return an email — is the account '
          'valid? (scopes granted: $scopes)');
    }
    final name = info['name']?.toString() ?? email;
    final tools = toolsFromScopes(scopes);

    // Sealed, 0600, values never read back — same rules as every vault
    // entry. The phone only ever sees email / name / tool names.
    await writeVaultSecret(_vaultDir, 'google_oauth:$email',
        jsonEncode({'refresh_token': refreshToken, 'scope': scopes}));
    await writeVaultSecret(_vaultDir, 'google_profile:$email',
        jsonEncode({'email': email, 'name': name, 'tools': tools}));
    return {'email': email, 'name': name, 'tools': tools};
  }

  /// Every connected account: email + name + which tools connected.
  /// Values (tokens) never leave the box.
  List<Map<String, dynamic>> accounts() {
    if (_vaultDir == null) return const [];
    final vault = readVault(_vaultDir);
    final out = <Map<String, dynamic>>[];
    for (final label in vault.keys) {
      if (!label.startsWith('google_profile:')) continue;
      try {
        final profile =
            jsonDecode(vault[label]!) as Map<String, dynamic>;
        out.add({
          'email': profile['email'],
          'name': profile['name'],
          'tools': profile['tools'] ?? const [],
        });
      } catch (_) {}
    }
    out.sort((a, b) =>
        (a['email'] ?? '').toString().compareTo((b['email'] ?? '').toString()));
    return out;
  }

  /// Removes the account (tokens + profile) from the vault.
  Future<bool> remove(String email) async {
    if (_vaultDir == null) return false;
    var removed = false;
    removed = await deleteVaultSecret(_vaultDir, 'google_oauth:$email') ||
        removed;
    removed = await deleteVaultSecret(_vaultDir, 'google_profile:$email') ||
        removed;
    return removed;
  }

  String _brief(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final err = decoded['error_description'] ?? decoded['error'];
        final msg = err?.toString() ?? body;
        return msg.length <= 200 ? msg : msg.substring(0, 200);
      }
    } catch (_) {}
    return body.length <= 200 ? body : body.substring(0, 200);
  }
}
