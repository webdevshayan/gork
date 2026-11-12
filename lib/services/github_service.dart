import 'package:http/http.dart' as http;

import 'integrations.dart';

/// GitHub REST API v3 with a personal access token.
/// Docs: docs.github.com/rest — every call is JSON, bearer auth.
class GitHubService {
  static const String base = 'https://api.github.com';

  final http.Client client;
  final Future<String?> Function() token;

  GitHubService({required this.client, required this.token});

  Map<String, String> _headers(String t) => {
        'Authorization': 'Bearer $t',
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'gork-app',
      };

  Future<dynamic> _call(String method, String path,
      {Map<String, String>? query, Map<String, dynamic>? body}) async {
    final t = await token();
    if (t == null || t.isEmpty) {
      throw const IntegrationException('GitHub token missing — connect it in Integrations');
    }
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    return jsonRequest(client, method, uri,
        headers: _headers(t), body: body);
  }

  /// Test connection: returns the login name of the token owner.
  Future<String> whoAmI() async {
    final data = await _call('GET', '/user') as Map<String, dynamic>;
    return data['login'] as String? ?? 'unknown';
  }

  /// Unread notifications, newest first, e.g. "#123 PR: fix login".
  Future<List<String>> notifications({int limit = 5}) async {
    final data = await _call('GET', '/notifications',
        query: {'per_page': '$limit', 'all': 'false'}) as List;
    return [
      for (final n in data.take(limit))
        _describeSubject(n as Map<String, dynamic>)
    ];
  }

  String _describeSubject(Map<String, dynamic> n) {
    final subject = n['subject'] as Map<String, dynamic>? ?? {};
    final title = subject['title'] as String? ?? 'untitled';
    final type = subject['type'] as String? ?? 'item';
    final repo = (n['repository'] as Map<String, dynamic>? ?? {})['full_name'];
    return '${repo ?? 'unknown'} · $type: $title';
  }

  /// Open issues for `owner/repo`. Pull requests are filtered out.
  Future<List<String>> openIssues(String repo, {int limit = 5}) async {
    final data = await _call('GET', '/repos/$repo/issues',
        query: {'state': 'open', 'per_page': '25'}) as List;
    final lines = <String>[];
    for (final raw in data) {
      final issue = raw as Map<String, dynamic>;
      if (issue.containsKey('pull_request')) continue;
      lines.add('#${issue['number']} ${issue['title']}');
      if (lines.length >= limit) break;
    }
    return lines;
  }

  /// Create an issue; returns a confirmation line with the number.
  Future<String> createIssue(String repo,
      {required String title, String body = ''}) async {
    final data = await _call('POST', '/repos/$repo/issues',
        body: {'title': title, if (body.isNotEmpty) 'body': body})
        as Map<String, dynamic>;
    final n = data['number'];
    final url = data['html_url'] as String? ?? '';
    return 'created issue #$n${url.isEmpty ? '' : ' — $url'}';
  }

  /// JSON body of a call — exposed for tests and future tools.
  Future<dynamic> raw(String method, String path,
          {Map<String, String>? query, Map<String, dynamic>? body}) =>
      _call(method, path, query: query, body: body);
}
