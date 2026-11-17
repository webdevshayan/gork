import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import 'package:gork_daemon/cli_support.dart';
import 'package:gork_daemon/server.dart';
import 'package:gork_daemon/scheduler.dart';
import 'package:gork_daemon/autostart.dart';
import 'package:gork_daemon/daemon_control.dart';
import 'package:gork_daemon/browser_agent.dart';

class FakeLlm implements LlmCaller {
  @override
  Future<String> call(String prompt) async => 'test-llm-ok';

  @override
  String describe() => 'fake';
}

void main() {
  group('ConfigStore', () {
    late Directory home;

    setUp(() {
      home = Directory.systemTemp.createTempSync('gork-cli-config');
    });

    tearDown(() => home.deleteSync(recursive: true));

    test('config lives at GORK_HOME/config.env', () {
      final path = configPath(env: {'GORK_HOME': home.path});
      expect(path, '${home.path}/config.env');
    });

    test('set creates, upserts and preserves other keys + comments', () async {
      final store = ConfigStore('${home.path}/config.env');
      await store.set('GORK_PORT', '8787');
      await store.set('GORK_API_KEY', 'sk-first');
      // upsert the same key
      await store.set('GORK_API_KEY', 'sk-second');
      final values = store.read();
      expect(values['GORK_PORT'], '8787');
      expect(values['GORK_API_KEY'], 'sk-second');
      final raw = File('${home.path}/config.env').readAsStringSync();
      expect('GORK_API_KEY="sk-first"'.allMatches(raw).length, 0,
          reason: 'no stale duplicate lines');
      expect('GORK_API_KEY="sk-second"'.allMatches(raw).length, 1);
    });

    test('get/list roundtrip through the file', () async {
      final store = ConfigStore('${home.path}/config.env');
      await store.set('GORK_MODEL', 'gpt-4o-mini');
      expect(store.get('GORK_MODEL'), 'gpt-4o-mini');
      expect(store.get('GORK_MISSING'), isNull);
      expect(store.list()['GORK_MODEL'], 'gpt-4o-mini');
    });

    test('ensureSecret adds a hex secret once', () async {
      final store = ConfigStore('${home.path}/config.env');
      await store.ensureSecret();
      final first = store.get('GORK_SECRET')!;
      expect(first.length, greaterThanOrEqualTo(48));
      await store.ensureSecret();
      expect(store.get('GORK_SECRET'), first, reason: 'generated once');
    });
  });

  group('llm presets', () {
    test('known providers map to real endpoints + models', () {
      final openai = llmPreset('openai');
      expect(openai!.baseUrl, 'https://api.openai.com/v1');
      expect(openai.model, 'gpt-4o-mini');
      expect(llmPreset('openrouter')!.baseUrl,
          'https://openrouter.ai/api/v1');
      expect(llmPreset('gemini')!.baseUrl,
          'https://generativelanguage.googleapis.com/v1beta/openai');
      expect(llmPreset('groq')!.baseUrl, 'https://api.groq.com/openai/v1');
      expect(llmPreset('ollama')!.baseUrl, 'http://127.0.0.1:11434/v1');
      expect(llmPreset('does-not-exist'), isNull,
          reason: 'unknown preset -> caller decides');
    });
  });

  group('DaemonClient against a real in-process server', () {
    late HttpServer server;
    late Directory home;

    setUp(() async {
      home = Directory.systemTemp.createTempSync('gork-cli-daemon');
      final daemon = Daemon(
        FileTaskStore('${home.path}/tasks.json'),
        FakeLlm(),
        const NoopNotifier(),
      );
      server = await shelf_io.serve(
        buildHandler(daemon, secret: 'cli-secret'),
        '127.0.0.1',
        0,
      );
    });

    tearDown(() async => server.close(force: true));

    DaemonClient makeClient() => DaemonClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
          secret: 'cli-secret',
        );

    test('health reports ok', () async {
      final client = makeClient();
      final health = await client.health();
      expect(health['status'], 'ok');
    });

    test('tasks add/list/remove/run roundtrip', () async {
      final client = makeClient();
      await client.tasksAdd(
        title: 'Morning briefing',
        prompt: 'summarize news',
        repeatMinutes: 60,
      );
      var tasks = await client.tasksList();
      expect(tasks.length, 1);
      expect(tasks.first['title'], 'Morning briefing');
      expect(tasks.first['repeatMinutes'], 60);

      final id = tasks.first['id'] as String;
      final removed = await client.tasksRemove(id);
      expect(removed['deleted'], id);
      tasks = await client.tasksList();
      expect(tasks, isEmpty);

      final ran = await client.tasksRun();
      expect(ran['ran'], 0);
    });

    test('secret mismatch fails loudly, not silently', () async {
      final client = DaemonClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        secret: 'wrong',
      );
      await expectLater(client.tasksList(), throwsA(isA<DaemonApiError>()));
    });

    test('statusLine formats daemon + task count', () async {
      final client = makeClient();
      final line = await client.statusLine();
      expect(line, contains('ok'));
    });
  });

  group('runCli', () {
    late Directory home;
    setUp(() {
      home = Directory.systemTemp.createTempSync('gork-cli-run');
    });
    tearDown(() => home.deleteSync(recursive: true));

    ConfigStore makeConfig() => ConfigStore('${home.path}/config.env');

    test('config set/get/list via the CLI surface', () async {
      final out = <String>[];
      final code = await runCli(
        ['config', 'set', 'GORK_API_KEY', 'sk-via-cli'],
        config: makeConfig(),
        out: out.add,
      );
      expect(code, 0);
      final code2 = await runCli(
        ['config', 'get', 'GORK_API_KEY'],
        config: makeConfig(),
        out: out.add,
      );
      expect(code2, 0);
      expect(out.join('\n'), contains('sk-via-cli'));
      final code3 = await runCli(
        ['config', 'list'],
        config: makeConfig(),
        out: out.add,
      );
      expect(code3, 0);
      expect(out.join('\n'), contains('GORK_API_KEY=sk-via-cli'));
    });

    test('unknown command exits non-zero with usage', () async {
      final out = <String>[];
      final code = await runCli(['nonsense'],
          config: makeConfig(), out: out.add);
      expect(code, isNot(0));
      expect(out.join('\n'), contains('usage'));
    });

    test('llm set maps a preset and persists it', () async {
      final out = <String>[];
      final config = makeConfig();
      final code = await runCli(
        ['llm', 'set', 'groq'],
        config: config,
        out: out.add,
      );
      expect(code, 0);
      expect(config.get('GORK_BASE_URL'), 'https://api.groq.com/openai/v1');
      expect(config.get('GORK_MODEL'), 'llama-3.3-70b-versatile');
      expect(out.join('\n'), contains('groq'));
    });

    test('llm providers lists the presets', () async {
      final out = <String>[];
      final code = await runCli(
        ['llm', 'providers'],
        config: makeConfig(),
        out: out.add,
      );
      expect(code, 0);
      final printed = out.join('\n');
      for (final p in ['openai', 'openrouter', 'gemini', 'groq', 'ollama']) {
        expect(printed, contains(p));
      }
    });

    test('gork daemon status/logs via the injected control', () async {
      final ctlHome = Directory.systemTemp.createTempSync('gork-cli-ctl');
      addTearDown(() => ctlHome.deleteSync(recursive: true));
      final control = DaemonControl(env: {
        'HOME': ctlHome.path,
        'GORK_HOME': '${ctlHome.path}/state',
        'GORK_PORT': '59977', // nothing listens here in tests
      });
      final out = <String>[];
      final code = await runCli(['daemon', 'status'],
          config: makeConfig(), control: control, out: out.add);
      expect(code, 0);
      expect(out.join('\n'), contains('daemon: down'));
      expect(out.join('\n'), contains('59977'));

      final code2 = await runCli(['daemon', 'logs'],
          config: makeConfig(), control: control, out: out.add);
      expect(code2, 0);
      expect(out.join('\n'), contains('no log yet'));

      // The shorthand: `gork status-lifecycle` without the daemon word.
      final code3 = await runCli(['stop'],
          config: makeConfig(), control: control, out: out.add);
      expect(code3, 0);
      expect(out.join('\n'), contains('daemon not running'));
    });

    test('gork autostart installs the hooks idempotently', () async {
      final ctlHome = Directory.systemTemp.createTempSync('gork-cli-auto');
      addTearDown(() => ctlHome.deleteSync(recursive: true));
      final control = DaemonControl(env: {'HOME': ctlHome.path});
      final out = <String>[];
      final code = await runCli(['autostart'],
          config: makeConfig(), control: control, out: out.add,
          autostart: Autostart(env: {'HOME': ctlHome.path},
              probe: '/x/bin/gork'));
      expect(code, 0);
      final printed = out.join('\n');
      expect(printed, contains('boot script'));
      expect(printed, contains('profile hook'));
      expect(File('${ctlHome.path}/.termux/boot/gork-daemon.sh').existsSync(),
          isTrue);
      // Second run is idempotent.
      final out2 = <String>[];
      await runCli(['autostart'],
          config: makeConfig(), control: control, out: out2.add,
          autostart: Autostart(env: {'HOME': ctlHome.path},
              probe: '/x/bin/gork'));
      expect(out2.join('\n'), contains('already present'));
    });

    test('gork vault set/list/rm — the value comes from stdin, never argv',
        () async {
      final ctlHome = Directory.systemTemp.createTempSync('gork-cli-vault');
      addTearDown(() => ctlHome.deleteSync(recursive: true));
      final control = DaemonControl(env: {'HOME': ctlHome.path});
      final out = <String>[];
      final code = await runCli(['vault', 'set', 'gmail-login'],
          config: makeConfig(), control: control, out: out.add,
          readLine: () async => 'hunter2');
      expect(code, 0);
      final vaultFile = File(
          '${ctlHome.path}/.gork-daemon/vault.json');
      expect(vaultFile.existsSync(), isTrue);
      expect(vaultFile.readAsStringSync(), contains('gmail-login'));
      final printed = out.join('\n');
      expect(printed, contains('never echoed back'));

      final out2 = <String>[];
      final code2 = await runCli(['vault', 'list'],
          config: makeConfig(), control: control, out: out2.add);
      expect(code2, 0);
      expect(out2.join('\n'), contains('gmail-login'));
      expect(out2.join('\n'), contains('values never shown'));

      final out3 = <String>[];
      final code3 = await runCli(['vault', 'rm', 'gmail-login'],
          config: makeConfig(), control: control, out: out3.add);
      expect(code3, 0);
      expect(out3.join('\n'), contains('removed'));
    });

    test('gork browser open/read against a live daemon with a fake browser',
        () async {
      final cdp = FakeBrowserCdp();
      final browser = AgentBrowser(
        env: {'GORK_HOME': home.path, 'GORK_BROWSER': '/bin/true'},
        launcher: (exec, args, env) async => cdp,
      );
      final daemonServer = await shelf_io.serve(
        buildHandler(Daemon(FileTaskStore('${home.path}/tasks.json'),
            FakeLlm(), const NoopNotifier()),
            browser: browser),
        '127.0.0.1',
        0,
      );
      addTearDown(daemonServer.close);
      final client = DaemonClient(
        baseUrl: 'http://127.0.0.1:${daemonServer.port}',
        secret: '',
      );
      final out = <String>[];
      final code = await runCli(['browser', 'open', 'example.com'],
          config: makeConfig(), client: client, out: out.add);
      expect(code, 0);
      expect(out.join('\n'), contains('https://example.com'));
      final out2 = <String>[];
      final code2 = await runCli(['browser', 'read'],
          config: makeConfig(), client: client, out: out2.add);
      expect(code2, 0);
      expect(out2.join('\n'), contains('fake-page-text'));
    });

    test('tasks flow through the CLI surface', () async {
      final config = makeConfig();
      final server = await _serve(home);
      addTearDown(server.close);
      final client = DaemonClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        secret: '',
      );
      final out = <String>[];
      final code = await runCli(
        ['tasks', 'add', 'Standup', 'post today\'s standup'],
        config: config,
        client: client,
        out: out.add,
      );
      expect(code, 0);
      final code2 = await runCli(['tasks', 'list'],
          config: config, client: client, out: out.add);
      expect(code2, 0);
      expect(out.join('\n'), contains('Standup'));
    });
  });
}

class FakeBrowserCdp implements CdpConnection {
  @override
  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params,
      {String? sessionId}) async {
    switch (method) {
      case 'Target.createTarget':
        return {'targetId': 't'};
      case 'Target.attachToTarget':
        return {'sessionId': 's'};
      case 'Runtime.evaluate':
        return {'result': {'value': 'fake-page-text'}};
      default:
        return {};
    }
  }

  @override
  Future<Map<String, dynamic>> waitEvent(String method, String sessionId) async => {};

  @override
  Future<void> close() async {}
}

Future<HttpServer> _serve(Directory home) async {
  final daemon = Daemon(
    FileTaskStore('${home.path}/tasks.json'),
    FakeLlm(),
    const NoopNotifier(),
  );
  return shelf_io.serve(buildHandler(daemon), '127.0.0.1', 0);
}
