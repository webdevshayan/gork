import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gork/services/handoff_service.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _CapturingClient extends http.BaseClient {
  final http.Response Function(http.Request request) handler;
  final List<http.Request> sent = [];

  _CapturingClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request as http.Request);
    final res = handler(request);
    return http.StreamedResponse(
        Stream.value(res.bodyBytes), res.statusCode,
        headers: res.headers);
  }
}

/// Movement 34: the app pushes its whole config to the user's own daemon —
/// LLM provider keys, model/base URL, connector tokens, ntfy topic — in one
/// "Sync to daemon" action. No file editing on the VPS, ever.
void main() {
  late HandoffService handoff;
  late _CapturingClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    client = _CapturingClient((req) {
      return http.Response(jsonEncode({
        'saved': ['GORK_API_KEY', 'GORK_MODEL'],
        'needsRestart': <String>[],
      }), 200);
    });
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
      httpClient: client,
    );
    handoff = Locator.handoff;
    await handoff.setUrl('http://vps.example:8787');
    await handoff.setSecret('vps-secret');
  });

  test('pushConfig posts keys, model and connector tokens to /config',
      () async {
    await Locator.chat.saveKey('openai', 'sk-test-key');
    await Locator.integrations.vault.setToken('github', 'gh-token-1');
    await Locator.integrations.vault.setToken('slack', 'xoxb-2');
    await handoff.setNtfyTopic('gork-shayan');

    final summary = await handoff.pushConfig();

    final req = client.sent.single;
    expect(req.url.path, '/config');
    expect(req.headers['x-gork-secret'], 'vps-secret');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final config = body['config'] as Map<String, dynamic>;
    expect(config['GORK_API_KEY'], 'sk-test-key');
    expect(config['GORK_BASE_URL'], 'https://api.openai.com/v1');
    expect(config['GORK_MODEL'], 'gpt-4o-mini');
    expect(config['NTFY_TOPIC'], 'gork-shayan');
    final connectors = body['connectors'] as Map<String, dynamic>;
    expect(connectors['github'], 'gh-token-1');
    expect(connectors['slack'], 'xoxb-2');
    expect(summary, contains('synced'));
    expect(summary, contains('daemon'));
  });

  test('pushConfig with several providers syncs the first key holder',
      () async {
    await Locator.chat.saveKey('gemini', 'g-key');
    await handoff.pushConfig();
    final body = jsonDecode(client.sent.single.body) as Map<String, dynamic>;
    final config = body['config'] as Map<String, dynamic>;
    expect(config['GORK_API_KEY'], 'g-key');
    expect(config['GORK_BASE_URL'], 'https://generativelanguage.googleapis.com/v1beta/openai');
    expect(config['GORK_MODEL'], 'gemini-2.0-flash');
  });

  test('pushConfig sends nothing when no keys exist yet', () async {
    final summary = await handoff.pushConfig();
    expect(client.sent, isEmpty);
    expect(summary, contains('nothing to sync'));
  });

  test('pushConfig without a daemon URL fails loudly', () async {
    await handoff.setUrl('');
    expect(() => handoff.pushConfig(),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg',
            contains('not configured'))));
  });
}
