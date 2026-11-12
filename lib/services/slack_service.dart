import 'dart:convert';

import 'package:http/http.dart' as http;

import 'integrations.dart';

/// Slack Web API with a bot token (xoxb-…).
/// Slack answers HTTP 200 with {"ok": false, "error": "…"} on API errors —
/// that is mapped to IntegrationException so callers see one error type.
class SlackService {
  static const String base = 'https://slack.com/api';

  final http.Client client;
  final Future<String?> Function() token;

  SlackService({required this.client, required this.token});

  Map<String, String> _headers(String t) => {
        'Authorization': 'Bearer $t',
        'Content-Type': 'application/json; charset=utf-8',
      };

  Future<dynamic> _call(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final t = await token();
    if (t == null || t.isEmpty) {
      throw const IntegrationException('Slack token missing — connect it in Integrations');
    }
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final data = await jsonRequest(client, method, uri,
        headers: _headers(t), body: body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw IntegrationException('Slack API error: ${data['error'] ?? 'unknown'}');
    }
    return data;
  }

  /// Test connection: identity of the bot/user behind the token.
  Future<String> whoAmI() async {
    final data = await _call('POST', '/auth.test') as Map<String, dynamic>;
    final user = data['user'] as String? ?? data['bot_id'] ?? 'unknown';
    final team = data['team'] as String? ?? '';
    return team.isEmpty ? '$user' : '$user in $team';
  }

  /// Channel names the bot can see, e.g. "#general".
  Future<List<String>> channels({int limit = 20}) async {
    final data = await _call('GET', '/conversations.list',
        query: {'limit': '$limit', 'types': 'public_channel'}) as Map<String, dynamic>;
    final list = data['channels'] as List? ?? [];
    return [
      for (final c in list) '#${(c as Map<String, dynamic>)['name']}'
    ];
  }

  /// Post a message; returns the channel + timestamp.
  Future<String> postMessage(
      {required String channel, required String text}) async {
    final data = await _call('POST', '/chat.postMessage',
        body: {'channel': channel, 'text': text}) as Map<String, dynamic>;
    final ts = data['ts'] as String? ?? '';
    return 'posted to $channel${ts.isEmpty ? '' : ' (ts $ts)'}';
  }
}
