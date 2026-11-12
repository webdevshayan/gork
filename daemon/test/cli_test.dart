import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import 'package:gork_daemon/cli_support.dart';
import 'package:gork_daemon/server.dart';
import 'package:gork_daemon/scheduler.dart';

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

Future<HttpServer> _serve(Directory home) async {
  final daemon = Daemon(
    FileTaskStore('${home.path}/tasks.json'),
    FakeLlm(),
    const NoopNotifier(),
  );
  return shelf_io.serve(buildHandler(daemon), '127.0.0.1', 0);
}
