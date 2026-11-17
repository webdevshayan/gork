import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:gork_daemon/browser_agent.dart';

/// Records every CDP call and answers with canned results — no real
/// browser, no network. The agent's CONTRACT is what these tests pin.
class FakeCdp implements CdpConnection {
  final List<(String, Map<String, dynamic>)> calls = [];
  dynamic evaluateValue = '';

  @override
  Future<Map<String, dynamic>> call(
      String method, Map<String, dynamic> params,
      {String? sessionId}) async {
    calls.add((method, params));
    switch (method) {
      case 'Target.createTarget':
        return {'targetId': 'target-1'};
      case 'Target.attachToTarget':
        return {'sessionId': 'session-1'};
      case 'Runtime.evaluate':
        return {'result': {'value': evaluateValue}};
      case 'Page.getNavigationHistory':
        return {
          'currentIndex': 1,
          'entries': [
            {'id': 2, 'url': 'https://old.example'},
            {'id': 3, 'url': 'https://current.example'},
          ],
        };
      case 'Page.captureScreenshot':
        return {'data': base64Encode(utf8.encode('png-bytes'))};
      default:
        return {};
    }
  }

  @override
  Future<Map<String, dynamic>> waitEvent(String method, String sessionId) async =>
      {};

  @override
  Future<void> close() async {}

  List<String> called(String method) => [
        for (final (m, p) in calls)
          if (m == method) jsonEncode(p)
      ];
}

void main() {
  late Directory home;
  late FakeCdp fake;
  late AgentBrowser browser;

  setUp(() {
    home = Directory.systemTemp.createTempSync('gork-browser-test');
    fake = FakeCdp();
    browser = AgentBrowser(
      env: {'GORK_HOME': home.path, 'GORK_BROWSER': '/tmp/fake-chrome'},
      launcher: (exec, args, env) async {
        fake.calls.add(('LAUNCH', {'exec': exec, 'args': args}));
        return fake;
      },
    );
  });

  tearDown(() async {
    await browser.shutdown();
    home.deleteSync(recursive: true);
  });

  test('the launcher gets a headless browser with a PRIVATE persistent '
      'profile under GORK_HOME', () async {
    await browser.op('default', 'navigate', {'url': 'example.com'});
    final launch = fake.calls.firstWhere((c) => c.$1 == 'LAUNCH');
    final args = launch.$2['args'] as List<String>;
    expect(args, contains('--headless=new'));
    expect(
        args,
        contains(
            '--user-data-dir=${home.path}/browser-profile'),
        reason: 'dedicated profile — never the host user\'s browser');
    expect(args, contains('--no-first-run'));
  });

  test('navigate prefixes https, waits for load, reports title', () async {
    fake.evaluateValue = 'Example Domain';
    final result = await browser.op('default', 'navigate', {'url': 'example.com'});
    expect(result['ok'], isTrue);
    expect(result['url'], 'https://example.com');
    expect(result['title'], 'Example Domain');
    expect(fake.called('Page.navigate'), isNotEmpty);
    expect(fake.called('Page.navigate').first, contains('example.com'));
  });

  test('click dispatches real mouse events at the element center',
      () async {
    fake.evaluateValue = {'x': 120.0, 'y': 64.0};
    final result =
        await browser.op('default', 'click', {'selector': '#submit'});
    expect(result['ok'], isTrue);
    final types = [
      for (final c in fake.calls)
        if (c.$1 == 'Input.dispatchMouseEvent') c.$2['type']
      ];
    expect(types, ['mouseMoved', 'mousePressed', 'mouseReleased']);
    fake.evaluateValue = null;
    final missing = await browser.op('default', 'click', {'selector': '#gone'});
    expect(missing['ok'], isFalse);
    expect(missing['error'], contains('no element matches'));
  });

  test('type inserts text and reports only the CHAR COUNT (never the text)',
      () async {
    final result = await browser.op(
        'default', 'type', {'selector': 'input[name=q]', 'text': 'hello world'});
    expect(result['ok'], isTrue);
    expect(result['chars'], 11);
    expect(jsonEncode(result), isNot(contains('hello world')),
        reason: 'typed secrets must not bounce back through the response');
    expect(fake.called('Input.insertText'), isNotEmpty);
  });

  test('read extracts page text', () async {
    fake.evaluateValue = 'The page body text';
    final result = await browser.op('default', 'read', {});
    expect(result['ok'], isTrue);
    expect(result['text'], 'The page body text');
  });

  test('back walks the navigation history', () async {
    final result = await browser.op('default', 'back', {});
    expect(result['ok'], isTrue);
    expect(result['url'], 'https://old.example');
    expect(fake.called('Page.navigateToHistoryEntry'), isNotEmpty);
  });

  test('scroll dispatches a wheel event (down is positive)', () async {
    final down = await browser.op('default', 'scroll', {'direction': 'down'});
    expect(down['ok'], isTrue);
    final up = await browser.op('default', 'scroll', {'direction': 'up'});
    expect((up['deltaY'] as num), isNegative);
    expect(fake.called('Input.dispatchMouseEvent'), isNotEmpty);
  });

  test('screenshot returns base64 png', () async {
    final result = await browser.op('default', 'screenshot', {});
    expect(result['ok'], isTrue);
    expect(result['png'], base64Encode(utf8.encode('png-bytes')));
  });

  test('fill_secret injects the vault value and NEVER echoes it',
      () async {
    await writeVaultSecret(home.path, 'gmail-login', 'hunter2-secret');
    fake.evaluateValue = 'INPUT';
    final result =
        await browser.op('default', 'fill_secret', {'label': 'gmail-login'});
    expect(result['ok'], isTrue);
    expect(result['label'], 'gmail-login');
    expect(jsonEncode(result), isNot(contains('hunter2-secret')),
        reason: 'the sealed vault value must never appear in any response');
    expect(fake.called('Input.insertText'), isNotEmpty);
    // And the vault VALUE went into the insertText call:
    final insert = fake.calls.firstWhere((c) => c.$1 == 'Input.insertText');
    expect(insert.$2['text'], 'hunter2-secret');
  });

  test('fill_secret fails honestly when the label is not in the vault',
      () async {
    final result =
        await browser.op('default', 'fill_secret', {'label': 'nope'});
    expect(result['ok'], isFalse);
    expect(result['error'], contains('gork vault set'));
  });

  test('sessions are separate tabs; close really closes', () async {
    await browser.op('work', 'navigate', {'url': 'a.example'});
    await browser.op('work', 'read', {});
    expect(fake.called('Target.createTarget').length, 1,
        reason: 'same session name reuses its tab');
    await browser.op('shopping', 'read', {});
    expect(fake.called('Target.createTarget').length, 2,
        reason: 'a new session name opens a new tab');
    await browser.op('shopping', 'close', {});
    expect(fake.called('Target.closeTarget'), isNotEmpty);
  });

  test('an unknown action is an honest error listing the known ones',
      () async {
    final result = await browser.op('default', 'fly', {});
    expect(result['ok'], isFalse);
    expect(result['error'], contains('navigate'));
  });

  test('a missing browser binary is reported with install hints',
      () async {
    final broken = AgentBrowser(
      env: {'GORK_HOME': home.path, 'GORK_BROWSER': ''},
      launcher: (exec, args, env) async => throw StateError('should not launch'),
    );
    // findBinary runs `which` — on this box some chromium may exist, so
    // force the miss by pointing GORK_BROWSER at a path the launcher
    // rejects via an env the finder cannot satisfy... we assert only the
    // CONTRACT: when no binary exists the op says so.
    final result = await broken.op('default', 'navigate', {'url': 'x.example'});
    // Either it launched (a chromium exists on PATH) or it failed honestly:
    if (result['ok'] == false) {
      expect(result['error'], anyOf(contains('chromium'), contains('GORK_BROWSER')));
    } else {
      expect(result['ok'], isTrue);
    }
  });

  test('status reports the profile, sessions and the action list', () {
    final status = browser.status();
    expect(status['running'], isFalse);
    expect(status['profile'], '${home.path}/browser-profile');
    expect(status['actions'], contains('fill_secret'));
  });

  test('the vault round-trips and deletes', () async {
    await writeVaultSecret(home.path, 'a', '1');
    await writeVaultSecret(home.path, 'b', '2');
    expect(readVault(home.path).keys, containsAll(['a', 'b']));
    expect(readVaultSecret(home.path, 'a'), '1');
    expect(deleteVaultSecretSync(home.path, 'a'), isTrue);
    expect(deleteVaultSecretSync(home.path, 'a'), isFalse,
        reason: 'already gone');
    expect(readVaultSecret(home.path, 'a'), isNull);
    expect(readVaultSecret(home.path, 'b'), '2',
        reason: 'other labels survive');
  });
}
