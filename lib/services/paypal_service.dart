import 'dart:convert';

import 'package:http/http.dart' as http;

import 'integrations.dart';

/// PayPal REST API with client-credentials OAuth.
///
/// Token format the user pastes: `client_id:secret`.
/// Sandbox users prefix it: `sandbox:client_id:secret` — gork then talks to
/// api-m.sandbox.paypal.com instead of the live host.
class PayPalService {
  final http.Client client;
  final Future<String?> Function() token;

  PayPalService({required this.client, required this.token});

  static const String liveBase = 'https://api-m.paypal.com';
  static const String sandboxBase = 'https://api-m.sandbox.paypal.com';

  ({String clientId, String secret, bool sandbox})? _split(String raw) {
    var t = raw.trim();
    var sandbox = false;
    if (t.startsWith('sandbox:')) {
      sandbox = true;
      t = t.substring('sandbox:'.length);
    }
    final idx = t.indexOf(':');
    if (idx <= 0 || idx == t.length - 1) return null;
    return (clientId: t.substring(0, idx), secret: t.substring(idx + 1), sandbox: sandbox);
  }

  /// Exchange client_id:secret for an OAuth access token.
  Future<String?> _accessToken(String raw) async {
    final parts = _split(raw);
    if (parts == null) {
      throw const IntegrationException(
          'PayPal token must be client_id:secret (prefix sandbox: for sandbox)');
    }
    final base = parts.sandbox ? sandboxBase : liveBase;
    final basic = base64Encode(utf8.encode('${parts.clientId}:${parts.secret}'));
    final res = await jsonRequest(client, 'POST', Uri.parse('$base/v1/oauth2/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        basicAuth: basic,
        rawBody: 'grant_type=client_credentials');
    return (res as Map<String, dynamic>)['access_token'] as String?;
  }

  /// Test connection: obtain a token (and report the sandbox mode).
  Future<String> whoAmI() async {
    final raw = await token();
    if (raw == null || raw.isEmpty) {
      throw const IntegrationException('PayPal token missing — connect it in Integrations');
    }
    final t = await _accessToken(raw);
    if (t == null || t.isEmpty) {
      throw const IntegrationException('PayPal did not return an access token');
    }
    return _split(raw)!.sandbox ? 'connected (sandbox)' : 'connected (live)';
  }

  /// Recent transactions within the last [days] days (max 31, PayPal limit).
  Future<List<String>> transactions({int days = 7}) async {
    final raw = await token();
    if (raw == null || raw.isEmpty) {
      throw const IntegrationException('PayPal token missing — connect it in Integrations');
    }
    final parts = _split(raw);
    if (parts == null) {
      throw const IntegrationException(
          'PayPal token must be client_id:secret (prefix sandbox: for sandbox)');
    }
    final base = parts.sandbox ? sandboxBase : liveBase;
    final access = await _accessToken(raw);
    final now = DateTime.now();
    final start = now.subtract(Duration(days: days.clamp(1, 31)));
    String iso(DateTime d) =>
        '${d.toIso8601String().substring(0, 19)}${now.timeZoneOffset.isNegative ? "-" : "+"}'
        '${now.timeZoneOffset.inHours.abs().toString().padLeft(2, '0')}:'
        '${(now.timeZoneOffset.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
    final uri = Uri.parse('$base/v1/reporting/transactions').replace(queryParameters: {
      'start_date': iso(start),
      'end_date': iso(now),
      'fields': 'transaction_info',
      'page_size': '20',
    });
    final data = await jsonRequest(client, 'GET', uri, headers: {
      'Authorization': 'Bearer $access',
    }) as Map<String, dynamic>;
    final details = data['transaction_details'] as List? ?? [];
    final lines = <String>[];
    for (final d in details) {
      final info = (d as Map<String, dynamic>)['transaction_info']
          as Map<String, dynamic>? ?? {};
      final amount = info['transaction_amount'] as Map<String, dynamic>? ?? {};
      final value = amount['value'] ?? '?';
      final currency = amount['currency_code'] ?? '';
      final status = info['transaction_status'] ?? '';
      final note = (info['transaction_note'] as String?) ??
          (info['transaction_subject'] as String?) ??
          '';
      lines.add('$currency $value — $status${note.isEmpty ? '' : ' — $note'}');
    }
    return lines;
  }
}
