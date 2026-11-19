import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:shelf/shelf.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:gork_daemon/server.dart';
import 'package:gork_daemon/scheduler.dart';
import 'package:gork_daemon/cli_support.dart';
import 'package:gork_daemon/browser_agent.dart';
import 'package:gork_daemon/google_auth.dart';
import 'package:gork_daemon/job_store.dart';

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
  Future<String> call(String prompt, {String? system}) async => 'ok: $prompt';

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

  group('GET /v1/vault — the sealed vault, labels only', () {
    Future<Directory> seededVault() async {
      final dir = await Directory.systemTemp.createTemp('gork-vault-test');
      // Deliberately unsorted on disk + values that must never leak.
      await writeVaultSecret(dir.path, 'zeta-login', 'zeta-value-9');
      await writeVaultSecret(dir.path, 'alpha-login', 'alpha-value-1');
      return dir;
    }

    test('lists labels sorted and NEVER the values', () async {
      final dir = await seededVault();
      addTearDown(() => dir.deleteSync(recursive: true));
      final handler = buildHandler(makeDaemon(), vaultDir: dir.path);
      final res = await handler(_req('GET', '/v1/vault'));
      expect(res.statusCode, 200);
      final body = await _body(res);
      expect(body['count'], 2);
      expect(
        [for (final e in body['entries'] as List) e['label']],
        ['alpha-login', 'zeta-login'],
      );
      final raw = jsonEncode(body);
      expect(raw, isNot(contains('zeta-value-9')));
      expect(raw, isNot(contains('alpha-value-1')));
    });

    test('an empty vault answers an empty list, not an error', () async {
      final dir = await Directory.systemTemp.createTemp('gork-vault-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final handler = buildHandler(makeDaemon(), vaultDir: dir.path);
      final res = await handler(_req('GET', '/v1/vault'));
      expect(res.statusCode, 200);
      final body = await _body(res);
      expect(body['count'], 0);
      expect(body['entries'], isEmpty);
    });

    test('stays behind the shared-secret gate like every other route',
        () async {
      final dir = await seededVault();
      addTearDown(() => dir.deleteSync(recursive: true));
      final handler = buildHandler(makeDaemon(), secret: 's3cret',
          vaultDir: dir.path);
      final res = await handler(_req('GET', '/v1/vault'));
      expect(res.statusCode, 401);
    });

    test('an unwired daemon answers 500 honestly instead of faking empty',
        () async {
      final handler = buildHandler(makeDaemon());
      final res = await handler(_req('GET', '/v1/vault'));
      expect(res.statusCode, 500);
      final body = await _body(res);
      expect(body['error'], contains('vault not wired'));
    });
  });

  group('Movement 61 — version + credentials endpoints', () {
    test('/health reports the daemon version (the app shows it and points '
        'at `gork daemon update` when an old daemon refuses)', () async {
      final handler = buildHandler(makeDaemon());
      final res = await handler(_req('GET', '/health'));
      final body = await _body(res);
      expect(body['version'], kDaemonVersion);
    });

    test('POST /v1/credentials/google seals the client JSON into the vault '
        'and answers 201', () async {
      final dir = await Directory.systemTemp.createTemp('gork-creds-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final handler = buildHandler(makeDaemon(), vaultDir: dir.path);
      final res = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/credentials/google'),
        body: jsonEncode({
          'client_json': {
            'installed': {
              'client_id': 'abc.apps.googleusercontent.com',
              'client_secret': 'GOCSPX-supersecret',
            },
          },
        }),
        headers: {'content-type': 'application/json'},
      ));
      expect(res.statusCode, 201);
      final stored = await _body(res);
      expect(stored['stored'], true);

      // Sealed on disk; the secret never leaks through any endpoint.
      final vault = readVault(dir.path);
      expect(vault['google_credentials'], contains('GOCSPX-supersecret'));
      final status =
          await handler(_req('GET', '/v1/credentials/google/status'));
      expect(status.statusCode, 200);
      final statusBody = await _body(status);
      expect(statusBody['has_client_json'], true);
      expect(jsonEncode(statusBody), isNot(contains('GOCSPX-supersecret')));
    });

    test('a service-account JSON is accepted too', () async {
      final dir = await Directory.systemTemp.createTemp('gork-creds-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final handler = buildHandler(makeDaemon(), vaultDir: dir.path);
      final res = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/credentials/google'),
        body: jsonEncode({
          'client_json': {
            'type': 'service_account',
            'private_key': '-----BEGIN PRIVATE KEY-----',
            'client_email': 'bot@project.iam.gserviceaccount.com',
          },
        }),
        headers: {'content-type': 'application/json'},
      ));
      expect(res.statusCode, 201);
    });

    test('a junk client_json is refused with 400', () async {
      final dir = await Directory.systemTemp.createTemp('gork-creds-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final handler = buildHandler(makeDaemon(), vaultDir: dir.path);
      final res = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/credentials/google'),
        body: jsonEncode({'client_json': {'hello': 'world'}}),
        headers: {'content-type': 'application/json'},
      ));
      expect(res.statusCode, 400);
      final body = await _body(res);
      expect(body['error'], contains('OAuth client'));
    });

    test('malformed (non-JSON) bodies are refused with 400', () async {
      final dir = await Directory.systemTemp.createTemp('gork-creds-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final handler = buildHandler(makeDaemon(), vaultDir: dir.path);
      final res = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/credentials/google'),
        body: 'this is not json',
        headers: {'content-type': 'application/json'},
      ));
      expect(res.statusCode, 400);
    });

    test('credentials routes are gated by the shared secret', () async {
      final dir = await Directory.systemTemp.createTemp('gork-creds-test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final handler =
          buildHandler(makeDaemon(), secret: 's3cret', vaultDir: dir.path);
      final res =
          await handler(_req('GET', '/v1/credentials/google/status'));
      expect(res.statusCode, 401);
    });

    test('an unwired vault answers 500 honestly for the credentials routes',
        () async {
      final handler = buildHandler(makeDaemon());
      final status =
          await handler(_req('GET', '/v1/credentials/google/status'));
      expect(status.statusCode, 500);
    });
  });

  group('Movement 62 — never-losable chat jobs', () {
    late Directory tmp;
    late _RecordingNotifier notifier;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('gork-jobs-test');
      notifier = _RecordingNotifier();
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    Daemon daemonWith() => Daemon(
        FakeTaskStore(),
        FakeLlm(),
        notifier,
        clock: () => DateTime.fromMillisecondsSinceEpoch(1000));

    /// The job processing is async (persist BEFORE the 201, LLM after).
    /// Wait until the job reaches a terminal state.
    Future<AgentJob> finished(JobStore store, String id) async {
      for (var i = 0; i < 100; i++) {
        final m = store.all().where((j) => j.id == id).toList();
        if (m.isNotEmpty && (m.first.status == 'done' || m.first.status == 'error')) {
          return m.first;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      fail('job $id never reached a terminal state');
    }

    test('POST /v1/messages persists FIRST, then the reply lands and the '
        'notification carries its first lines', () async {
      final store = FileJobStore('${tmp.path}/jobs.json');
      final handler = buildHandler(daemonWith(), jobStore: store);
      final res = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/messages'),
        body: jsonEncode({'conversation_id': 'c1', 'text': 'hello gork'}),
        headers: {'content-type': 'application/json'},
      ));
      expect(res.statusCode, 201);
      final id = (await _body(res))['id'] as String;

      // Durable at acceptance: the job exists on disk even before the LLM
      // finished (here it finishes fast — the point is the store has it).
      expect(store.all().where((j) => j.id == id), isNotEmpty);

      final job = await finished(store, id);
      expect(job.status, 'done');
      expect(job.reply, 'ok: hello gork');

      final got = await handler(_req('GET', '/v1/jobs/$id'));
      expect(got.statusCode, 200);
      final body = await _body(got);
      expect(body['status'], 'done');
      expect((body['result'] as Map)['reply'], 'ok: hello gork');

      // The notification: title says ready, body = the reply's gist.
      expect(notifier.titles, contains('gork — response ready'));
      expect(notifier.bodies, contains('ok: hello gork'));
    });

    test('GET /v1/conversations/<id>/messages returns user/assistant pairs',
        () async {
      final store = FileJobStore('${tmp.path}/jobs.json');
      final handler = buildHandler(daemonWith(), jobStore: store);
      for (final text in ['first question', 'second question']) {
        await handler(Request(
          'POST',
          Uri.parse('http://test.local/v1/messages'),
          body: jsonEncode({'conversation_id': 'c9', 'text': text}),
          headers: {'content-type': 'application/json'},
        ));
      }
      // Wait until BOTH jobs are done (the phone pulls when it returns).
      for (final id in store.all().map((j) => j.id)) {
        await finished(store, id);
      }
      final res =
          await handler(_req('GET', '/v1/conversations/c9/messages'));
      final body = await _body(res);
      final messages = [
        for (final m in body['messages'] as List) m as Map<String, dynamic>
      ];
      expect(messages, hasLength(4));
      expect(messages[0]['role'], 'user');
      expect(messages[0]['content'], 'first question');
      expect(messages[1]['role'], 'assistant');
      expect(messages[1]['content'], 'ok: first question');
      expect(messages[3]['content'], 'ok: second question');
    });

    test('an LLM failure is stored (status error), notified honestly, and '
        'the client still gets the pair — nothing silently vanishes',
        () async {
      final store = FileJobStore('${tmp.path}/jobs.json');
      final failing = Daemon(FakeTaskStore(), _ThrowingLlm(), notifier);
      final handler = buildHandler(failing, jobStore: store);
      final res = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/messages'),
        body: jsonEncode({'conversation_id': 'c2', 'text': 'doomed'}),
        headers: {'content-type': 'application/json'},
      ));
      final id = (await _body(res))['id'] as String;
      final job = await finished(store, id);
      expect(job.status, 'error');
      expect(job.reply, contains('LLM exploded'));
      expect(notifier.titles, contains('gork — the request failed'));
    });

    test('validation: empty text 400, bad JSON 400, unknown job 404, '
        'unwired store 500', () async {
      final store = FileJobStore('${tmp.path}/jobs.json');
      final handler = buildHandler(daemonWith(), jobStore: store);
      final empty = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/messages'),
        body: jsonEncode({'conversation_id': 'c1', 'text': '   '}),
        headers: {'content-type': 'application/json'},
      ));
      expect(empty.statusCode, 400);
      final bad = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/messages'),
        body: 'not json',
        headers: {'content-type': 'application/json'},
      ));
      expect(bad.statusCode, 400);
      final missing = await handler(_req('GET', '/v1/jobs/nope'));
      expect(missing.statusCode, 404);
      final unwired = await buildHandler(daemonWith())(_req('GET', '/v1/jobs/anything'));
      expect(unwired.statusCode, 500);
    });
  });

  group('Movement 62 — Google login on the user\'s server', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('gork-google-test');
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    /// Daemon + handler with the vault wired and Google's token/userinfo
    /// endpoints mocked (the flow itself runs for real).
    Future<(Handler, GoogleAuth)> wired({
      required String tokenBody,
      required int tokenStatus,
      required String userinfoBody,
    }) async {
      final handler = buildHandler(makeDaemon(), vaultDir: tmp.path,
          google: GoogleAuth(
              vaultDir: tmp.path,
              client: MockClient((request) async {
                if (request.url.toString().contains('/token')) {
                  return http.Response(tokenBody, tokenStatus);
                }
                return http.Response(userinfoBody, 200);
              })));
      final google = GoogleAuth(vaultDir: tmp.path);
      return (handler, google);
    }

    const clientJson = {
      'installed': {
        'client_id': '123.apps.googleusercontent.com',
        'client_secret': 'GOCSPX-supersecret',
      },
    };

    test('consent/start without a sealed credentials.json names the fix',
        () async {
      final (handler, _) = await wired(
          tokenBody: '', tokenStatus: 400, userinfoBody: '{}');
      final res = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/google/consent/start'),
        body: jsonEncode({'redirect_uri': 'http://127.0.0.1:9/x'}),
        headers: {'content-type': 'application/json'},
      ));
      expect(res.statusCode, 400);
      final body = await _body(res);
      expect(body['error'], contains('upload it first'));
    });

    test('consent/start builds the full consent URL from the SEALED client '
        '(every tool scope, offline access, the loopback redirect)',
        () async {
      final (handler, _) = await wired(
          tokenBody: '', tokenStatus: 400, userinfoBody: '{}');
      // Seal the client first — exactly what the phone's upload does.
      final upload = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/credentials/google'),
        body: jsonEncode({'client_json': clientJson}),
        headers: {'content-type': 'application/json'},
      ));
      expect(upload.statusCode, 201);

      final res = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/google/consent/start'),
        body: jsonEncode({'redirect_uri': 'http://127.0.0.1:4321/callback'}),
        headers: {'content-type': 'application/json'},
      ));
      expect(res.statusCode, 200);
      final url = (await _body(res))['url'] as String;
      expect(url, contains('client_id=123.apps.googleusercontent.com'));
      expect(url, contains('redirect_uri=http%3A%2F%2F127.0.0.1%3A4321%2Fcallback'));
      expect(url, contains('gmail'));
      expect(url, contains('documents'));
      expect(url, contains('youtube'));
      expect(url, contains('access_type=offline'));
      // The client_secret NEVER appears in a consent URL.
      expect(url, isNot(contains('GOCSPX')));
    });

    test('exchange turns a code into a sealed account + profile; accounts '
        'lists email/name/tools and never a token', () async {
      final (handler, google) = await wired(
          tokenStatus: 200,
          tokenBody: jsonEncode({
            'access_token': 'ya29.fresh',
            'refresh_token': '1//refresh-me',
            'scope':
                'openid https://www.googleapis.com/auth/gmail '
                    'https://www.googleapis.com/auth/documents',
          }),
          userinfoBody: jsonEncode({
            'email': 'user@example.com',
            'name': 'The User',
          }));

      await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/credentials/google'),
        body: jsonEncode({'client_json': clientJson}),
        headers: {'content-type': 'application/json'},
      ));
      final res = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/google/exchange'),
        body: jsonEncode({
          'code': '4/0authcode',
          'redirect_uri': 'http://127.0.0.1:4321/callback',
        }),
        headers: {'content-type': 'application/json'},
      ));
      expect(res.statusCode, 201);
      final account = await _body(res);
      expect(account['email'], 'user@example.com');
      expect(account['name'], 'The User');
      expect(account['tools'], ['gmail', 'docs']);

      // Sealed on disk.
      final vault = readVault(tmp.path);
      expect(vault['google_oauth:user@example.com'], contains('1//refresh-me'));
      expect(vault['google_profile:user@example.com'], contains('The User'));

      // The phone's view: labels + tools, NEVER a token.
      final list = await handler(_req('GET', '/v1/google/accounts'));
      final body = await _body(list);
      final accounts = body['accounts'] as List;
      expect(accounts, hasLength(1));
      final encoded = jsonEncode(accounts);
      expect(encoded, isNot(contains('1//refresh-me')));
      expect(encoded, isNot(contains('ya29.fresh')));

      expect(google.accounts().first['tools'], ['gmail', 'docs']);
    });

    test('a Google refusal surfaces as a human 400', () async {
      final (handler, _) = await wired(
          tokenStatus: 400,
          tokenBody: jsonEncode({
            'error': 'invalid_grant',
            'error_description': 'code was already redeemed.',
          }),
          userinfoBody: '{}');
      await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/credentials/google'),
        body: jsonEncode({'client_json': clientJson}),
        headers: {'content-type': 'application/json'},
      ));
      final res = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/google/exchange'),
        body: jsonEncode({
          'code': '4/0authcode',
          'redirect_uri': 'http://127.0.0.1:4321/callback',
        }),
        headers: {'content-type': 'application/json'},
      ));
      expect(res.statusCode, 400);
      expect((await _body(res))['error'], contains('already redeemed'));
    });

    test('revoke removes the account from the vault and the phone view',
        () async {
      final (handler, google) = await wired(
          tokenStatus: 200,
          tokenBody: jsonEncode({
            'access_token': 'ya29.fresh',
            'refresh_token': '1//refresh-me',
            'scope': 'openid',
          }),
          userinfoBody:
              jsonEncode({'email': 'gone@example.com', 'name': 'Gone'}));
      await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/credentials/google'),
        body: jsonEncode({'client_json': clientJson}),
        headers: {'content-type': 'application/json'},
      ));
      await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/google/exchange'),
        body: jsonEncode({
          'code': '4/0authcode',
          'redirect_uri': 'http://127.0.0.1:4321/callback',
        }),
        headers: {'content-type': 'application/json'},
      ));
      expect(google.accounts(), hasLength(1));
      final revoke = await handler(Request(
        'POST',
        Uri.parse('http://test.local/v1/google/revoke'),
        body: jsonEncode({'email': 'gone@example.com'}),
        headers: {'content-type': 'application/json'},
      ));
      expect((await _body(revoke))['removed'], true);
      expect(google.accounts(), isEmpty);
    });

    test('unwired google auth answers 500 instead of pretending', () async {
      final handler = buildHandler(makeDaemon());
      final res = await handler(_req('GET', '/v1/google/accounts'));
      expect(res.statusCode, 500);
    });
  });
}

/// Records notifications — the job pipeline must push "response ready".
class _RecordingNotifier implements Notifier {
  final List<String> titles = [];
  final List<String> bodies = [];

  @override
  Future<void> notify(String title, String body) async {
    titles.add(title);
    bodies.add(body);
  }
}

class _ThrowingLlm implements LlmCaller {
  @override
  Future<String> call(String prompt, {String? system}) async =>
      throw StateError('LLM exploded');

  @override
  String describe() => 'throwing';
}
