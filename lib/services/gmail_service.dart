import 'package:http/http.dart' as http;

import 'integrations.dart';

/// Gmail API v1 with a user-supplied OAuth access token.
/// Scopes: gmail.readonly (read) — tokens are short-lived; the user pastes a
/// fresh one from the OAuth playground when it expires.
class GmailService {
  static const String base = 'https://gmail.googleapis.com';

  final http.Client client;
  final Future<String?> Function() token;

  GmailService({required this.client, required this.token});

  Future<dynamic> _call(String method, String path,
      {Map<String, String>? query}) async {
    final t = await token();
    if (t == null || t.isEmpty) {
      throw const IntegrationException('Gmail token missing — connect it in Integrations');
    }
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    return jsonRequest(client, method, uri, headers: {
      'Authorization': 'Bearer $t',
    });
  }

  /// Test connection: the mailbox address.
  Future<String> whoAmI() async {
    final data =
        await _call('GET', '/gmail/v1/users/me/profile') as Map<String, dynamic>;
    return data['emailAddress'] as String? ?? 'unknown mailbox';
  }

  /// Unread inbox: "From — Subject" lines, newest first.
  Future<List<String>> unread({int limit = 5}) async {
    final listRes = await _call('GET', '/gmail/v1/users/me/messages',
        query: {'q': 'is:unread', 'maxResults': '$limit'})
        as Map<String, dynamic>;
    final messages = listRes['messages'] as List? ?? [];
    final lines = <String>[];
    for (final m in messages.take(limit)) {
      final id = (m as Map<String, dynamic>)['id'] as String;
      final full = await _call('GET', '/gmail/v1/users/me/messages/$id',
          query: {'format': 'metadata'}) as Map<String, dynamic>;
      lines.add(_line(full));
    }
    return lines;
  }

  String _line(Map<String, dynamic> message) {
    final payload = message['payload'] as Map<String, dynamic>? ?? {};
    final headers = payload['headers'] as List? ?? [];
    String from = '?';
    String subject = '(no subject)';
    for (final h in headers) {
      final hh = h as Map<String, dynamic>;
      if (hh['name'] == 'From') from = hh['value'] as String? ?? from;
      if (hh['name'] == 'Subject') subject = hh['value'] as String? ?? subject;
    }
    // Keep just the address part if it's "Name <a@b.c>".
    final match = RegExp(r'<([^>]+)>').firstMatch(from);
    final addr = match != null ? match.group(1)! : from;
    return '$addr — $subject';
  }
}
