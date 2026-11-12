import 'dart:convert';

import 'package:test/test.dart';
import 'package:shelf/shelf.dart';

import 'package:gork_daemon/server.dart';
import 'package:gork_daemon/scheduler.dart';

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

  test('buildHandler with secret rejects requests without the header',
      () async {
    final handler = buildHandler(makeDaemon(), secret: 's3cret');
    final res = await handler(_req('GET', '/health'));
    expect(res.statusCode, 401);
  });

  test('buildHandler with secret accepts the right header', () async {
    final handler = buildHandler(makeDaemon(), secret: 's3cret');
    final res = await handler(
        _req('GET', '/health', headers: {'x-gork-secret': 's3cret'}));
    expect(res.statusCode, 200);
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
}
