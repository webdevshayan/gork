import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:shelf/shelf.dart';

import 'package:gork_daemon/server.dart';
import 'package:gork_daemon/scheduler.dart';
import 'package:gork_daemon/cli_support.dart';
import 'package:gork_daemon/browser_agent.dart';

class FakeCdpConnection implements CdpConnection {
  final List<String> methods = [];
  @override
  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params,
      {String? sessionId}) async {
    methods.add(method);
    switch (method) {
      case 'Target.createTarget':
        return {'targetId': 't'};
      case 'Target.attachToTarget':
        return {'sessionId': 's'};
      case 'Runtime.evaluate':
        return {'result': {'value': 'ok'}};
      default:
        return {};
    }
  }

  @override
  Future<Map<String, dynamic>> waitEvent(String method, String sessionId) async => {};

  @override
  Future<void> close() async {}
}

AgentBrowser fakeBrowser(FakeCdpConnection cdp) => AgentBrowser(
      env: {'GORK_HOME': '/tmp/gork-server-test', 'GORK_BROWSER': '/bin/true'},
      launcher: (exec, args, env) async => cdp,
    );

class FakeTaskStore implements TaskStore {
  final List<Task> items = [];
  final Map<String, int> lastRuns = {};

  @override
  List<Task> all() => List.of(items);

  @override
  Future<void> save(Task task) async {
    final i = items.indexWhere((t) => t.id == task.id);
    if (i >= 0) {
      items[i] = task;
    } else {
      items.add(task);
    }
  }

  @override
  Future<void> markRan(String id, DateTime when) async =>
      lastRuns[id] = when.millisecondsSinceEpoch;

  @override
  Future<void> delete(String id) async =>
      items.removeWhere((t) => t.id == id);
}

class FakeLlm implements LlmCaller {
  @override
  Future<String> call(String prompt) async => 'ok: $prompt';

  @override
  String describe() => 'fake';
}

const noopNotifier = NoopNotifier();

Request _req(String method, String path, {Map<String, String>? headers}) =>
    Request(method, Uri.parse('http://test.local$path'), headers: headers);

Future<Map<String, dynamic>> _body(Response res) async =>
    jsonDecode(await res.readAsString()) as Map<String, dynamic>;

void main() {
  Daemon makeDaemon() => Daemon(FakeTaskStore(), FakeLlm(), noopNotifier);

  test('buildHandler without secret leaves all routes open', () async {
    final handler = buildHandler(makeDaemon());
    final res = await handler(_req('GET', '/health'));
    expect(res.statusCode, 200);
    final body = await _body(res);
    expect(body['status'], 'ok');
  });

  test('buildHandler with secret rejects gated requests without the header',
      () async {
    final handler = buildHandler(makeDaemon(), secret: 's3cret');
    final res = await handler(_req('GET', '/tasks'));
    expect(res.statusCode, 401);
  });

  test('/health stays open even when a secret is set (liveness checks must '
      'not need auth)', () async {
    final handler = buildHandler(makeDaemon(), secret: 's3cret');
    final res = await handler(_req('GET', '/health'));
    expect(res.statusCode, 200);
    final body = await _body(res);
    expect(body['status'], 'ok');
  });

  test('buildHandler with secret accepts the right header', () async {
    final handler = buildHandler(makeDaemon(), secret: 's3cret');
    final res = await handler(
        _req('GET', '/tasks', headers: {'x-gork-secret': 's3cret'}));
    expect(res.statusCode, 200);
  });

  test('taskStorePath defaults to tasks.json next to the working directory',
      () {
    expect(taskStorePath(env: {}), 'tasks.json');
    expect(taskStorePath(env: {'GORK_HOME': ''}), 'tasks.json');
  });

  test('taskStorePath honors GORK_HOME so state survives CWD changes', () {
    expect(taskStorePath(env: {'GORK_HOME': '/var/lib/gork-daemon'}),
        '/var/lib/gork-daemon/tasks.json');
    expect(taskStorePath(env: {'GORK_HOME': '/data/data/com.termux/files/home/.gork-daemon'}),
        '/data/data/com.termux/files/home/.gork-daemon/tasks.json');
  });

  test('task CRUD still works through the gated handler', () async {
    final handler = buildHandler(makeDaemon(), secret: 's3cret');
    final h = {'x-gork-secret': 's3cret', 'content-type': 'application/json'};
    final create = await handler(Request('POST', Uri.parse('http://test.local/tasks'),
        headers: h,
        body: jsonEncode({
          'title': 'Briefing',
          'prompt': 'summarize news',
          'repeatMinutes': 60,
        })));
    expect(create.statusCode, 201);

    final list = await handler(_req('GET', '/tasks', headers: h));
    final body = await _body(list);
    expect((body['tasks'] as List).length, greaterThanOrEqualTo(1));
  });

  group('Movement 58 — the agent browser endpoints', () {
    late FakeCdpConnection cdp;
    setUp(() => cdp = FakeCdpConnection());

    test('POST /v1/browser/op routes to the agent browser (Bearer auth)',
        () async {
      final handler = buildHandler(makeDaemon(), secret: 's3cret',
          browser: fakeBrowser(cdp));
      final res = await handler(Request('POST', Uri.parse('http://test.local/v1/browser/op'),
          headers: {
            'authorization': 'Bearer s3cret',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'session': 'default',
            'action': 'navigate',
            'url': 'example.com',
          })));
      expect(res.statusCode, 200);
      final body = await _body(res);
      expect(body['ok'], isTrue);
      expect(body['url'], 'https://example.com');
      expect(cdp.methods, contains('Page.navigate'));
    });

    test('the browser routes are gated by the secret', () async {
      final handler = buildHandler(makeDaemon(), secret: 's3cret',
          browser: fakeBrowser(cdp));
      final res = await handler(Request('POST', Uri.parse('http://test.local/v1/browser/op'),
          body: jsonEncode({'session': 'default', 'action': 'read'})));
      expect(res.statusCode, 401);
    });

    test('GET /v1/browser/status describes the browser honestly',
        () async {
      final handler = buildHandler(makeDaemon(), secret: 's3cret',
          browser: fakeBrowser(cdp));
      final res = await handler(_req('GET', '/v1/browser/status',
          headers: {'x-gork-secret': 's3cret'}));
      expect(res.statusCode, 200);
      final body = await _body(res);
      expect(body['actions'], contains('fill_secret'));
      expect((body['actions'] as List), contains('navigate'));
    });

    test('without a browser wired the routes 404 (feature absent, not broken)',
        () async {
      final handler = buildHandler(makeDaemon(), secret: 's3cret');
      final res = await handler(_req('GET', '/v1/browser/status',
          headers: {'x-gork-secret': 's3cret'}));
      expect(res.statusCode, 404);
    });
  });

  group('POST /config — the app pushes its config, no file editing', () {
    late Directory tmp;
    late ConfigStore config;
    late Map<String, String> overlay;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('gork-config-test');
      config = ConfigStore('${tmp.path}/config.env');
      overlay = <String, String>{};
    });

    tearDown(() async => await tmp.delete(recursive: true));

    Future<Response> post(Map<String, dynamic> body) async {
      final handler = buildHandler(makeDaemon(), secret: 's3cret',
          config: config, configOverlay: overlay);
      return handler(Request('POST', Uri.parse('http://test.local/config'),
          headers: {
            'x-gork-secret': 's3cret',
            'content-type': 'application/json',
          },
          body: jsonEncode(body)));
    }

    test('writes keys to config.env and applies the LLM config live',
        () async {
      final res = await post({
        'config': {'GORK_API_KEY': 'sk-live', 'GORK_MODEL': 'llama-3'},
      });
      expect(res.statusCode, 200);
      final values = config.read();
      expect(values['GORK_API_KEY'], 'sk-live');
      expect(values['GORK_MODEL'], 'llama-3');
      // live apply: an EnvLlmCaller sharing the overlay picks it up at once
      // (describe() reports config, never the key itself)
      final llm = EnvLlmCaller(null, overlay);
      expect(llm.describe(), contains('llama-3'));
      expect(llm.describe(), isNot(contains('sk-live')));
      expect(llm.describe(), isNot(contains('not configured')));
    });

    test('stores connector tokens as GORK_CONNECTOR_<ID>', () async {
      final res = await post({
        'connectors': {'github': 'gh-1', 'slack': 'xoxb-2'},
      });
      expect(res.statusCode, 200);
      final values = config.read();
      expect(values['GORK_CONNECTOR_GITHUB'], 'gh-1');
      expect(values['GORK_CONNECTOR_SLACK'], 'xoxb-2');
    });

    test('GET /config returns config but never leaks the API key', () async {
      await post({
        'config': {'GORK_API_KEY': 'sk-secret', 'GORK_MODEL': 'm'},
        'connectors': {'github': 'gh-1'},
      });
      final handler = buildHandler(makeDaemon(), secret: 's3cret',
          config: config, configOverlay: overlay);
      final res = await handler(
          _req('GET', '/config', headers: {'x-gork-secret': 's3cret'}));
      expect(res.statusCode, 200);
      final body = await _body(res);
      final returned = body['config'] as Map<String, dynamic>;
      expect(returned['GORK_API_KEY'], anyOf(isNull, isEmpty, '<redacted>'));
      expect(returned['GORK_MODEL'], 'm');
      // connector tokens never leave the box — listed as connected only
      expect((body['connectors'] as Map)['github'], 'connected');
    });

    test('rejects malformed JSON with 400', () async {
      final handler = buildHandler(makeDaemon(), secret: 's3cret',
          config: config, configOverlay: overlay);
      final res = await handler(Request('POST', Uri.parse('http://test.local/config'),
          headers: {
            'x-gork-secret': 's3cret',
            'content-type': 'application/json',
          },
          body: 'not json'));
      expect(res.statusCode, 400);
    });

    test('is gated by the shared secret like every other route', () async {
      final handler = buildHandler(makeDaemon(), secret: 's3cret',
          config: config, configOverlay: overlay);
      final res = await handler(
          Request('POST', Uri.parse('http://test.local/config'),
              body: jsonEncode({'config': {}})));
      expect(res.statusCode, 401);
    });
  });
}
