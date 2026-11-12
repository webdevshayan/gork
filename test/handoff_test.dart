import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gork/services/handoff_service.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/tasks_store.dart';
import 'package:gork/services/tool_registry.dart';
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

void main() {
  late HandoffService handoff;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
      httpClient: _CapturingClient((req) {
        if (req.url.path.endsWith('/health')) {
          return http.Response(
              jsonEncode({'status': 'ok', 'service': 'gork-daemon'}), 200);
        }
        if (req.url.path == '/tasks') {
          if (req.method == 'GET') {
            return http.Response(
                jsonEncode({
                  'tasks': [
                    {
                      'id': '99',
                      'title': 'Morning briefing',
                      'prompt': 'summarize the news',
                      'repeatMinutes': 1440,
                      'enabled': true,
                      'lastRun': null
                    }
                  ]
                }),
                200);
          }
          return http.Response(
              jsonEncode({'saved': {'id': '1'}}), 201);
        }
        if (req.url.path == '/run') {
          return http.Response(jsonEncode({'ran': 2}), 200);
        }
        return http.Response('{}', 200);
      }),
    );
    handoff = Locator.handoff;
  });

  test('not configured until a URL is saved', () async {
    expect(handoff.configured, isFalse);
    await handoff.setUrl('http://vps.example:8787/');
    expect(handoff.configured, isTrue);
    expect(handoff.url, 'http://vps.example:8787'); // trailing / stripped
  });

  test('ping hits /health', () async {
    await handoff.setUrl('http://vps.example:8787');
    final client = Locator.httpClient as _CapturingClient;
    expect(await handoff.ping(), 'daemon alive');
    expect(client.sent.single.url.path, '/health');
  });

  test('push sends every local task, pull merges daemon tasks', () async {
    await handoff.setUrl('http://vps.example:8787');
    final now = DateTime.now().millisecondsSinceEpoch;
    await Locator.tasks.save(ScheduledTask(
      id: '1',
      title: 'Water plants',
      prompt: 'remind me',
      repeatMinutes: 60,
      enabled: true,
      createdAt: now,
    ));

    expect(await handoff.pushTasks(), 'pushed 1 task(s) to the daemon');
    expect(await handoff.pullTasks(), 'pulled 1 task(s) from the daemon');

    final tasks = Locator.tasks.all();
    expect(tasks.map((t) => t.id), containsAll(['1', '99']));
    final pulled = tasks.firstWhere((t) => t.id == '99');
    expect(pulled.title, 'Morning briefing');
    expect(pulled.createdAt, greaterThan(0)); // fallback filled
  });

  test('shared secret is sent as X-Gork-Secret header', () async {
    await handoff.setUrl('http://vps.example:8787');
    await handoff.setSecret('hunter2');
    final client = Locator.httpClient as _CapturingClient;
    await handoff.ping();
    expect(client.sent.single.headers['X-Gork-Secret'], 'hunter2');
  });

  test('triggerRun reports how many ran', () async {
    await handoff.setUrl('http://vps.example:8787');
    expect(await handoff.triggerRun(), '2 due task(s) executed on the daemon');
  });

  test('401 from the daemon maps to a secret-mismatch message via tool',
      () async {
    await handoff.setUrl('http://vps.example:8787');
    Locator.bind(
      httpClient: _CapturingClient((req) =>
          http.Response(jsonEncode({'error': 'bad or missing secret'}), 401)),
    );
    final badHandoff = Locator.handoff;
    final registry = ToolRegistry(
      memory: Locator.memory,
      projects: Locator.projects,
      tasks: Locator.tasks,
      panels: Locator.panels,
      vault: Locator.vault,
      weather: Locator.weather,
      handoff: badHandoff,
    );
    final out = await registry.execute('daemon_status', {});
    expect(out, contains('rejected the secret'));
  });

  test('daemon tools fail friendly when not configured', () async {
    final registry = buildAppToolRegistry();
    expect(await registry.execute('daemon_status', {}),
        contains('not configured'));
  });

  test('daemon tools work end to end when configured', () async {
    await handoff.setUrl('http://vps.example:8787');
    final registry = buildAppToolRegistry();
    expect(await registry.execute('daemon_status', {}), contains('alive'));
    final sync = await registry.execute('daemon_sync', {});
    expect(sync, contains('pushed'));
    expect(sync, contains('pulled'));
    expect(await registry.execute('daemon_run', {}), contains('2 due task(s)'));
  });
}
