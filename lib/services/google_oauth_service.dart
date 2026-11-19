import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'installer.dart';
import 'locator.dart';
import 'secure_store.dart';
import 'vps_config.dart';

/// Movement 62 — ONE TAP connects the Google account: the user's own VPS is
/// the login server (its sealed credentials.json IS the OAuth client), and
/// this service drives Google's supported loopback flow:
///
///   1. a tiny HTTP listener on 127.0.0.1:<ephemeral port> starts
///   2. the VPS builds the consent URL (from the sealed client_json) with
///      redirect_uri = that loopback address
///   3. the system browser opens; the user signs in and consents ONCE for
///      every tool (Gmail, Docs, YouTube) + identity
///   4. Google redirects to the loopback listener; the code is POSTed to
///      the VPS which exchanges it (client_secret stays sealed on the box),
///      fetches the profile (name + email) and seals the refresh token
///   5. the account appears with its connected tools
///
/// Nothing about Google lives in the app: swap the credentials.json on the
/// VPS and the login server follows.
class GoogleOAuthService {
  GoogleOAuthService({
    http.Client? client,
    Installer? installer,
    SharedPreferences? prefs,
    SecureStore? store,
  })  : _client = client,
        _installerOverride = installer,
        _prefsOverride = prefs,
        _storeOverride = store;

  final http.Client? _client;
  final Installer? _installerOverride;
  final SharedPreferences? _prefsOverride;
  final SecureStore? _storeOverride;

  http.Client get _http => _client ?? Locator.httpClient;
  Installer get _installer => _installerOverride ?? SystemInstaller();
  SharedPreferences get _prefs => _prefsOverride ?? Locator.prefs;
  SecureStore get _store => _storeOverride ?? Locator.store;

  /// ONE VPS connection (Movement 63): the Google flow used to read only
  /// the direct `vps.token` key, so installs whose secret lived under a
  /// legacy slot (`handoff.secret` / the agent-VPS apiKey) sent NO auth at
  /// all and the daemon answered "bad or missing X-Gork-Secret". Routing
  /// through [VpsConfig] gives the Google flow the SAME url + secret
  /// resolution — and the same header — as chat handoff, tasks and vault.
  late final VpsConfig vps = VpsConfig(prefs: _prefs, store: _store);

  String? get url => vps.url;

  bool get configured => url != null;

  Future<String?> _token() => vps.token();

  Future<Map<String, String>> _headers() => _authedHeaders();

  Future<Map<String, String>> _authedHeaders() async {
    final t = await _token();
    return {
      'Content-Type': 'application/json',
      if (t != null && t.isNotEmpty) 'X-Gork-Secret': t,
    };
  }

  /// THE single redirect URI. Movement 64: the flow used to bind an
  /// EPHEMERAL port (http://127.0.0.1:40053/callback), which changes on
  /// every sign-in — Google Cloud Console needs ONE exact redirect URI and
  /// answered every attempt with "Error 400: redirect_uri_mismatch". The
  /// port is now FIXED: register this exact value once in Cloud Console →
  /// Credentials → your OAuth client → Authorized redirect URIs.
  static const int kRedirectPort = 8636;
  static const String kRedirectUri =
      'http://127.0.0.1:$kRedirectPort/callback';

  /// The FULL one-tap flow. Returns the connected account:
  /// {email, name, tools: [gmail, docs, youtube]}. Throws [StateError]
  /// with a human message on any refusal — the screen shows it as-is.
  Future<Map<String, dynamic>> connect() async {
    final base = url;
    if (base == null) {
      throw StateError('No VPS configured yet — set it up in Cloud '
          'Computer first (the login happens on YOUR server).');
    }

    // 1. the loopback listener on the FIXED port — the one URI the user
    // registered in Cloud Console. Busy port = a previous sign-in window
    // is still closing (or another app owns it); retry in a moment.
    HttpServer server;
    try {
      server = await HttpServer.bind(
          InternetAddress.loopbackIPv4, kRedirectPort);
    } on SocketException {
      throw StateError(
          'The sign-in listener could not take port $kRedirectPort — '
          'a previous sign-in window may still be closing. Try again in '
          'a few seconds.');
    }
    const redirectUri = kRedirectUri;
    final code = await _openConsentAndAwaitCode(server, redirectUri);

    // 4. the VPS exchanges the code (client_secret never leaves the box).
    final res = await _http.post(
      Uri.parse('$base/v1/google/exchange'),
      headers: await _authedHeaders(),
      body: jsonEncode({'code': code, 'redirect_uri': redirectUri}),
    );
    if (res.statusCode != 201) {
      throw StateError(_errorOf(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<String> _openConsentAndAwaitCode(
      HttpServer server, String redirectUri) async {
    final base = url!;
    try {
      // 2. the consent URL from the VPS.
      final start = await _http.post(
        Uri.parse('$base/v1/google/consent/start'),
        headers: await _headers(),
        body: jsonEncode({'redirect_uri': redirectUri}),
      );
      if (start.statusCode != 200) {
        throw StateError(_errorOf(start));
      }
      final consentUrl =
          (jsonDecode(start.body) as Map<String, dynamic>)['url'] as String;

      // 3. the system browser (Google's own page, user's own account).
      await _installer.openUrl(consentUrl);

      // The redirect lands here — capture code or error, then answer the
      // browser with a page the user understands.
      final captured = Completer<String>();
      late final StreamSubscription<HttpRequest> sub;
      sub = server.listen((req) async {
        if (req.uri.path != '/callback') {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        final error = req.uri.queryParameters['error'];
        if (error != null) {
          await _page(req, 'gork — sign-in cancelled',
              'Google said: $error. You can close this window.');
          if (!captured.isCompleted) {
            captured.completeError(StateError(
                'Google sign-in was cancelled ($error). Try again.'));
          }
          return;
        }
        final code = req.uri.queryParameters['code'] ?? '';
        await _page(req, 'gork — connected',
            'Connected. You can close this window and return to the app.');
        if (!captured.isCompleted) captured.complete(code);
      });
      try {
        return await captured.future.timeout(const Duration(minutes: 5),
            onTimeout: () => throw StateError(
                'The sign-in timed out (5 minutes) — nothing was connected; '
                'try again.'));
      } finally {
        await sub.cancel();
      }
    } finally {
      await server.close(force: true);
    }
  }

  Future<void> _page(HttpRequest req, String title, String body) async {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${Uri.encodeComponent(title)}</title></head>
<body style="font-family:system-ui,sans-serif;background:#141414;color:#eee;
display:grid;place-items:center;min-height:80vh;margin:0">
<div style="max-width:24rem;text-align:center;padding:2rem">
<h2 style="font-weight:600">${Uri.encodeComponent(title)}</h2>
<p style="color:#aaa">${Uri.encodeComponent(body)}</p>
</div></body></html>''');
    await req.response.close();
  }

  /// Every account connected through the VPS: email + name + tools.
  Future<List<Map<String, dynamic>>> accounts() async {
    final base = url;
    if (base == null) return const [];
    try {
      final res = await _http.get(Uri.parse('$base/v1/google/accounts'),
          headers: await _authedHeaders());
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['accounts'] as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Removes the account's sealed tokens + profile from the VPS.
  Future<void> remove(String email) async {
    final base = url;
    if (base == null) return;
    try {
      await _http.post(Uri.parse('$base/v1/google/revoke'),
          headers: await _authedHeaders(),
          body: jsonEncode({'email': email}));
    } catch (_) {
      // best-effort: the screen refreshes from what the VPS reports
    }
  }

  String _errorOf(http.Response res) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final err = body['error']?.toString();
      if (err != null && err.isNotEmpty) return err;
    } catch (_) {}
    return 'the VPS refused (HTTP ${res.statusCode})';
  }
}
