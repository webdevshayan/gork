import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The agent browser — a PRIVATE, PERSISTENT, LIGHTWEIGHT headless Chromium
/// driven over raw CDP (Chrome DevTools Protocol). No Playwright, no Node,
/// no Selenium: one Dart file, one WebSocket, one browser process.
///
///   PRIVATE    — a dedicated profile at $GORK_HOME/browser-profile (mode
///                0700), never the host user's browser profile; fill_secret
///                values come from the local sealed vault and are NEVER
///                echoed into any response.
///   PERSISTENT — cookies, localStorage and logins survive daemon restarts
///                because the profile directory does.
///   LIGHTWEIGHT— spawns only when the first op arrives, dies with the
///                daemon (or gork daemon stop), relaunches lazily.
///   HUMAN-LIKE — real input events (mouse press/release at element center,
///                text insertion), load-event waits, history navigation,
///                wheel scrolling, screenshots.
///
/// Every op returns {'ok': true, ...} or {'ok': false, 'error': ...} — the
/// AI reads it, so honesty is part of the protocol.
class AgentBrowser {
  AgentBrowser({
    Map<String, String>? env,
    this.launcher = launchRealBrowser,
    this.loadTimeout = const Duration(seconds: 15),
    this.settleDelay = const Duration(milliseconds: 300),
  })  : _env = env ?? Platform.environment;

  final Map<String, String> _env;
  final Future<CdpConnection> Function(String executable, List<String> args,
      Map<String, String> env) launcher;
  final Duration loadTimeout;
  final Duration settleDelay;

  CdpConnection? _browser;
  String? _binary;
  final Map<String, _Tab> _tabs = {};

  String get stateDir {
    final home = _env['GORK_HOME'] ?? '';
    return home.isEmpty ? '.gork-daemon' : home;
  }

  String get profileDir => '${stateDir}/browser-profile';

  /// The actions the phone's tool registry may send.
  static const List<String> actions = [
    'navigate',
    'click',
    'drag',
    'wait',
    'press',
    'type',
    'read',
    'back',
    'scroll',
    'screenshot',
    'fill_secret',
    'close',
    'eval',
  ];

  bool get isRunning => _browser != null;

  Map<String, dynamic> status() {
    final found = _binary ?? findBinary(_env);
    return {
      'running': isRunning,
      'binary': found ?? '(none found)',
      'profile': profileDir,
      'sessions': _tabs.keys.toList(),
      'actions': actions,
      'hint': found == null
          ? 'no Chromium-family browser found — install one: '
              'Debian/Ubuntu: apt install chromium · Termux: pkg install '
              'chromium (x11 repo) or set GORK_BROWSER=/path/to/chrome'
          : null,
    };
  }

  /// One browser op. [session] names a tab ('default' first).
  Future<Map<String, dynamic>> op(
    String session,
    String action,
    Map<String, dynamic> args,
  ) async {
    if (action == 'close') return _close(session);
    try {
      return await _dispatch(session, action, args);
    } catch (e) {
      // Movement 70 — the browser process can die under us (OOM, crash,
      // 'browser exited before the page loaded'). Revive once: drop the
      // dead connection and every stale tab, relaunch, replay the op.
      if (_browser != null) {
        try { await _browser!.close(); } catch (_) {}
        _browser = null;
        _tabs.clear();
        final out = await _dispatch(session, action, args);
        return out..['revived'] = true;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _dispatch(
      String session, String action, Map<String, dynamic> args) async {
    try {
      final tab = await _tab(session);
      switch (action) {
        case 'navigate':
          return await _navigate(tab, '${args['url'] ?? ''}');
        case 'click':
          return await _click(tab, '${args['selector'] ?? ''}');
        case 'drag':
          return await _drag(
              tab, '${args['selector'] ?? ''}', '${args['target'] ?? ''}');
        case 'type':
          return await _type(tab, '${args['selector'] ?? ''}',
              '${args['text'] ?? ''}');
        case 'read':
          return await _read(tab, args['selector'] as String?);
        case 'back':
          return await _back(tab);
        case 'scroll':
          return await _scroll(tab, args['direction'] == 'up' ? -600 : 600);
        case 'screenshot':
          return await _screenshot(tab);
        case 'fill_secret':
          return await _fillSecret(tab, '${args['label'] ?? ''}');
        case 'eval':
          return await _eval(tab, '${args['js'] ?? ''}');
        case 'wait':
          return await _wait(tab, args);
        case 'press':
          return await _press(tab, '${args['key'] ?? ''}', args);
        default:
          return {
            'ok': false,
            'error': 'unknown action "$action" — known: ${actions.join(", ")}'
          };
      }
    } on BrowserUnavailable catch (e) {
      return {'ok': false, 'error': e.message};
    } catch (e) {
      // Movement 70 — browser-death is NOT an op failure: let it escape
      // to op()'s revive wrapper (relaunch + replay once). Everything
      // else is an honest op error.
      final msg = '$e';
      final dead = e is StateError ||
          e is ProcessException ||
          e is WebSocketException ||
          msg.contains('Target closed') ||
          msg.contains('Connection closed') ||
          msg.contains('browser exited') ||
          msg.contains('Bad state');
      if (dead) rethrow;
      return {'ok': false, 'error': '$action failed: $e'};
    }
  }

  /// Movement 70 — WAIT: sleep ms, or poll until a selector exists or
  /// visible text contains [text]. 'the browser exited before the page
  /// loaded' class of bugs mostly die here: poll, don't guess.
  Future<Map<String, dynamic>> _wait(
      _Tab tab, Map<String, dynamic> args) async {
    final ms = (args['ms'] as num?)?.toInt() ?? 0;
    final selector = '${args['selector'] ?? ''}';
    final text = '${args['text'] ?? ''}';
    final deadline = DateTime.now()
        .add(Duration(milliseconds: ms > 0 ? ms : 10000));
    while (true) {
      if (ms > 0 && selector.isEmpty && text.isEmpty) {
        await Future<void>.delayed(
            Duration(milliseconds: ms.clamp(0, 60000)));
        return {'ok': true, 'action': 'wait', 'waited_ms': ms};
      }
      bool ready = false;
      if (selector.isNotEmpty) {
        final r = await tab.evaluateJson(
            '(function(){return !!document.querySelector('
            '${jsonEncode(selector)});})()');
        ready = r == true;
      } else if (text.isNotEmpty) {
        final r = await tab.evaluateJson(
            '(function(){return document.body && document.body.innerText'
            '.includes(${jsonEncode(text)});})()');
        ready = r == true;
      } else {
        ready = true;
      }
      if (ready) return {'ok': true, 'action': 'wait', 'found': true};
      if (DateTime.now().isAfter(deadline)) {
        return {'ok': false, 'error': 'wait timed out', 'found': false};
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  static const Map<String, int> _keyCodes = {
    'Enter': 13, 'Tab': 9, 'Escape': 27, 'Backspace': 8, 'Space': 32,
    'ArrowUp': 38, 'ArrowDown': 40, 'ArrowLeft': 37, 'ArrowRight': 39,
    'PageUp': 33, 'PageDown': 34, 'Home': 36, 'End': 35, 'Delete': 46,
  };

  /// Movement 70 — PRESS: real key events for forms that only react to
  /// keys (Enter to submit). Named keys from the map, rawKeyDown + keyUp.
  Future<Map<String, dynamic>> _press(
      _Tab tab, String key, Map<String, dynamic> args) async {
    if (key.isEmpty) return {'ok': false, 'error': 'key is required'};
    final vk = _keyCodes[key];
    if (vk == null) {
      return {'ok': false,
              'error': 'unknown key "$key" — known: ${_keyCodes.keys.join(", ")}'};
    }
    final base = {
      'key': key,
      'code': key == 'Space' ? 'Space' : key,
      'windowsVirtualKeyCode': vk,
      if ((args['modifiers'] as num?) != null)
        'modifiers': (args['modifiers'] as num).toInt(),
    };
    await tab.cdp.call('Input.dispatchKeyEvent',
        {'type': 'rawKeyDown', ...base}, sessionId: tab.sessionId);
    await tab.cdp.call('Input.dispatchKeyEvent',
        {'type': 'keyUp', ...base}, sessionId: tab.sessionId);
    await Future<void>.delayed(settleDelay);
    return {'ok': true, 'action': 'press', 'key': key};
  }

  // -- sessions ---------------------------------------------------------------

  Future<_Tab> _tab(String session) async {
    final name = session.isEmpty ? 'default' : session;
    final existing = _tabs[name];
    if (existing != null && _browser != null) return existing;
    final browser = await _ensure();
    final created = await browser.call('Target.createTarget', {'url': 'about:blank'});
    final targetId = created['targetId'] as String;
    final attached =
        await browser.call('Target.attachToTarget', {'targetId': targetId, 'flatten': true});
    final tab = _Tab(targetId, attached['sessionId'] as String, browser);
    _tabs[name] = tab;
    return tab;
  }

  Future<Map<String, dynamic>> _close(String session) async {
    final name = session.isEmpty ? 'default' : session;
    final tab = _tabs.remove(name);
    if (tab == null) return {'ok': true, 'closed': name, 'note': 'session was not open'};
    try {
      await tab.cdp.call('Target.closeTarget', {'targetId': tab.targetId});
    } catch (_) {}
    return {'ok': true, 'closed': name};
  }

  Future<CdpConnection> _ensure() async {
    if (_browser != null) return _browser!;
    final binary = findBinary(_env);
    if (binary == null) {
      throw BrowserUnavailable(status()['hint'] as String);
    }
    _binary = binary;
    final dir = Directory(profileDir)..createSync(recursive: true);
    try {
      Process.runSync('chmod', <String>['700', dir.path]);
    } catch (_) {}
    final args = [
      '--headless=new',
      '--remote-debugging-port=0',
      '--user-data-dir=$profileDir',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-gpu',
      '--disable-dev-shm-usage',
      '--mute-audio',
      '--disable-extensions',
      '--window-size=1280,900',
      'about:blank',
    ];
    final conn = await launcher(binary, args, _env);
    _browser = conn;
    return conn;
  }

  // -- actions ----------------------------------------------------------------

  Future<Map<String, dynamic>> _navigate(_Tab tab, String url) async {
    if (url.isEmpty) return {'ok': false, 'error': 'url is required'};
    final fixed = (url.startsWith('http://') || url.startsWith('https://') ||
            url.startsWith('file://') || url.startsWith('about:'))
        ? url
        : 'https://$url';
    await tab.cdp.call('Page.navigate', {'url': fixed},
        sessionId: tab.sessionId);
    await tab.waitForLoad(loadTimeout);
    await Future<void>.delayed(settleDelay);
    final title = await tab.evaluate('document.title');
    return {'ok': true, 'action': 'navigate', 'url': fixed, 'title': title};
  }

  Future<Map<String, dynamic>> _click(_Tab tab, String selector) async {
    if (selector.isEmpty) return {'ok': false, 'error': 'selector is required'};
    final rect = await tab.evaluateJson(
        '(function(){const el=document.querySelector(${jsonEncode(selector)});'
        'if(!el)return null;const r=el.getBoundingClientRect();'
        'return {x:r.x+r.width/2,y:r.y+r.height/2};})()');
    if (rect == null) {
      return {'ok': false, 'error': 'no element matches "$selector"'};
    }
    final x = (rect['x'] as num).toDouble();
    final y = (rect['y'] as num).toDouble();
    await tab.cdp.call('Input.dispatchMouseEvent',
        {'type': 'mouseMoved', 'x': x, 'y': y}, sessionId: tab.sessionId);
    await tab.cdp.call('Input.dispatchMouseEvent',
        {
          'type': 'mousePressed',
          'x': x,
          'y': y,
          'button': 'left',
          'clickCount': 1
        },
        sessionId: tab.sessionId);
    await tab.cdp.call('Input.dispatchMouseEvent',
        {
          'type': 'mouseReleased',
          'x': x,
          'y': y,
          'button': 'left',
          'clickCount': 1
        },
        sessionId: tab.sessionId);
    await Future<void>.delayed(settleDelay);
    return {'ok': true, 'action': 'click', 'selector': selector, 'x': x, 'y': y};
  }

  /// Movement 69.1 — DRAG: press at element A, sweep in interpolated
  /// moves, release at element B. This is the slider-captcha primitive —
  /// the same gesture a finger makes on "slide to complete the puzzle".
  Future<Map<String, dynamic>> _drag(
      _Tab tab, String selector, String target) async {
    if (selector.isEmpty || target.isEmpty) {
      return {'ok': false, 'error': 'selector and target are required'};
    }
    Future<Map<String, dynamic>?> center(String sel) async =>
        await tab.evaluateJson(
                '(function(){const el=document.querySelector(${jsonEncode(sel)});'
                'if(!el)return null;const r=el.getBoundingClientRect();'
                'return {x:r.x+r.width/2,y:r.y+r.height/2};})()')
            as Map<String, dynamic>?;
    final from = await center(selector);
    final to = await center(target);
    if (from == null) {
      return {'ok': false, 'error': 'no element matches "$selector"'};
    }
    if (to == null) {
      return {'ok': false, 'error': 'no element matches "$target"'};
    }
    final double x0 = (from['x'] as num).toDouble();
    final double y0 = (from['y'] as num).toDouble();
    final double x1 = (to['x'] as num).toDouble();
    final double y1 = (to['y'] as num).toDouble();
    Future<void> mouse(String type, double x, double y) =>
        tab.cdp.call('Input.dispatchMouseEvent',
            {'type': type, 'x': x, 'y': y, 'button': 'left', 'clickCount': 1},
            sessionId: tab.sessionId);
    await mouse('mouseMoved', x0, y0);
    await mouse('mousePressed', x0, y0);
    // ~24 interpolated moves — enough for slider physics to register,
    // slow enough to look like a finger sweep.
    const steps = 24;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      await mouse('mouseMoved',
          x0 + (x1 - x0) * t, y0 + (y1 - y0) * t);
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
    await mouse('mouseReleased', x1, y1);
    await Future<void>.delayed(settleDelay);
    return {
      'ok': true,
      'action': 'drag',
      'from': selector,
      'to': target,
    };
  }

  Future<Map<String, dynamic>> _type(
      _Tab tab, String selector, String text) async {
    if (text.isEmpty) return {'ok': false, 'error': 'text is required'};
    if (selector.isNotEmpty) {
      await tab.evaluate(
          '(function(){const el=document.querySelector(${jsonEncode(selector)});'
          'if(!el)return "no element";el.focus();el.click?.();return null;})()');
    }
    await tab.cdp.call('Input.insertText', {'text': text},
        sessionId: tab.sessionId);
    await Future<void>.delayed(settleDelay);
    return {'ok': true, 'action': 'type', 'selector': selector, 'chars': text.length};
  }

  Future<Map<String, dynamic>> _read(_Tab tab, String? selector) async {
    final expr = selector == null || selector.isEmpty
        ? 'document.body?.innerText ?? ""'
        : 'document.querySelector(${jsonEncode(selector)})?.innerText ?? ""';
    final text = await tab.evaluate(expr);
    final title = await tab.evaluate('document.title');
    final url = await tab.evaluate('location.href');
    final truncated = text.length > 8000 ? '${text.substring(0, 8000)}…' : text;
    return {
      'ok': true,
      'action': 'read',
      'url': url,
      'title': title,
      'chars': text.length,
      'text': truncated,
    };
  }

  Future<Map<String, dynamic>> _back(_Tab tab) async {
    final hist = await tab.cdp.call('Page.getNavigationHistory', {},
        sessionId: tab.sessionId);
    final index = hist['currentIndex'] as int? ?? 0;
    final entries = (hist['entries'] as List? ?? []);
    if (index <= 0 || entries.length < 2) {
      return {'ok': false, 'error': 'no history to go back to'};
    }
    final previous = entries[index - 1] as Map;
    await tab.cdp.call('Page.navigateToHistoryEntry',
        {'entryId': previous['id']}, sessionId: tab.sessionId);
    await tab.waitForLoad(loadTimeout);
    await Future<void>.delayed(settleDelay);
    return {'ok': true, 'action': 'back', 'url': previous['url']};
  }

  Future<Map<String, dynamic>> _scroll(_Tab tab, double deltaY) async {
    await tab.cdp.call('Input.dispatchMouseEvent',
        {'type': 'mouseWheel', 'x': 640, 'y': 450, 'deltaY': deltaY},
        sessionId: tab.sessionId);
    await Future<void>.delayed(settleDelay);
    return {'ok': true, 'action': 'scroll', 'deltaY': deltaY};
  }

  Future<Map<String, dynamic>> _screenshot(_Tab tab) async {
    final shot = await tab.cdp.call('Page.captureScreenshot',
        {'format': 'png'}, sessionId: tab.sessionId);
    final data = shot['data'] as String?;
    if (data == null) return {'ok': false, 'error': 'browser returned no image'};
    return {'ok': true, 'action': 'screenshot', 'format': 'png', 'png': data};
  }

  Future<Map<String, dynamic>> _fillSecret(_Tab tab, String label) async {
    if (label.isEmpty) return {'ok': false, 'error': 'label is required'};
    final value = readVaultSecret(stateDir, label);
    if (value == null) {
      return {
        'ok': false,
        'error': 'no vault entry for label "$label" — add it with: '
            'gork vault set $label   (value comes from stdin, never argv)'
      };
    }
    // Inject into the ACTIVE input only. The value never appears in this
    // response, in any log, or on any wire the AI can read back.
    final focused = await tab.evaluate(
        'document.activeElement?.tagName ?? "none"');
    await tab.cdp.call('Input.insertText', {'text': value},
        sessionId: tab.sessionId);
    return {
      'ok': true,
      'action': 'fill_secret',
      'label': label,
      'filledInto': focused,
    };
  }

  Future<Map<String, dynamic>> _eval(_Tab tab, String js) async {
    if (js.isEmpty) return {'ok': false, 'error': 'js is required'};
    final result = await tab.evaluateJson(js);
    return {'ok': true, 'action': 'eval', 'result': result};
  }

  /// Terminate the browser process (gork daemon stop / shutdown hooks).
  Future<void> shutdown() async {
    final browser = _browser;
    _browser = null;
    _tabs.clear();
    await browser?.close();
  }
}

class BrowserUnavailable implements Exception {
  BrowserUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

class _Tab {
  _Tab(this.targetId, this.sessionId, this.cdp);

  final String targetId;
  final String sessionId;
  final CdpConnection cdp;

  Future<void> waitForLoad(Duration timeout) async {
    try {
      await cdp
          .waitEvent('Page.loadEventFired', sessionId)
          .timeout(timeout, onTimeout: () => <String, dynamic>{});
    } catch (_) {
      // A page without a load event (about:blank, SPA quirks) — continue.
    }
  }

  Future<String> evaluate(String expression) async {
    final result = await cdp.call('Runtime.evaluate',
        {'expression': expression, 'returnByValue': true},
        sessionId: sessionId);
    return ((result['result'] as Map?)?['value'] ?? '').toString();
  }

  Future<dynamic> evaluateJson(String expression) async {
    final result = await cdp.call('Runtime.evaluate',
        {'expression': expression, 'returnByValue': true},
        sessionId: sessionId);
    return (result['result'] as Map?)?['value'];
  }
}

/// The CDP wire. One WebSocket to the browser endpoint; flattened sessions
/// mean every call may carry a sessionId (tab). [send] resolves with the
/// method's 'result' map.
abstract class CdpConnection {
  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params,
      {String? sessionId});
  Future<Map<String, dynamic>> waitEvent(String method, String sessionId);
  Future<void> close();
}

/// The production connection: spawns the browser, reads the DevTools
/// endpoint from stderr, opens the WebSocket.
Future<CdpConnection> launchRealBrowser(
    String executable, List<String> args, Map<String, String> env) async {
  final process = await Process.start(executable, args,
      environment: env, workingDirectory: Directory.systemTemp.path);
  final wsUrl = await _devtoolsUrl(process.stderr, const Duration(seconds: 20));
  return RealCdpConnection.connect(process, wsUrl);
}

Future<String> _devtoolsUrl(
    Stream<List<int>> stderr, Duration timeout) async {
  final completer = Completer<String>();
  final buffer = StringBuffer();
  final sub = stderr.transform(utf8.decoder).listen((chunk) {
    buffer.write(chunk);
    final match = RegExp(r'DevTools listening on (ws://\S+)')
        .firstMatch(buffer.toString());
    if (match != null && !completer.isCompleted) {
      completer.complete(match.group(1)!);
    }
  }, onDone: () {
    if (!completer.isCompleted) {
      completer.completeError(StateError('browser exited before DevTools URL'));
    }
  }, onError: (Object e) {
    if (!completer.isCompleted) completer.completeError(e);
  });
  try {
    return await completer.future.timeout(timeout);
  } finally {
    await sub.cancel();
  }
}

class RealCdpConnection implements CdpConnection {
  RealCdpConnection._(this._process, this._ws);

  final Process _process;
  final WebSocket _ws;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final Map<String, List<Completer<Map<String, dynamic>>>> _eventWaiters = {};
  int _nextId = 1;

  static Future<CdpConnection> connect(Process process, String wsUrl) async {
    final ws = await WebSocket.connect(wsUrl);
    final conn = RealCdpConnection._(process, ws);
    ws.listen(conn._onMessage,
        onDone: () => conn._failAll('browser closed the connection'),
        onError: (Object e) => conn._failAll('$e'));
    return conn;
  }

  void _onMessage(dynamic raw) {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    final id = message['id'] as int?;
    if (id != null) {
      final completer = _pending.remove(id);
      if (completer != null) {
        if (message['error'] != null) {
          completer.completeError(
              CdpError((message['error'] as Map)['message']?.toString() ??
                  'cdp error'));
        } else {
          completer
              .complete((message['result'] as Map?)?.cast<String, dynamic>() ?? {});
        }
      }
      return;
    }
    final method = message['method'] as String?;
    final sessionId = message['sessionId'] as String? ?? '';
    if (method != null) {
      final waiters = _eventWaiters.remove('$sessionId|$method');
      if (waiters != null) {
        for (final w in waiters) {
          w.complete((message['params'] as Map?)?.cast<String, dynamic>() ?? {});
        }
      }
    }
  }

  void _failAll(String why) {
    for (final completer in _pending.values) {
      completer.completeError(CdpError(why));
    }
    _pending.clear();
  }

  @override
  Future<Map<String, dynamic>> call(String method, Map<String, dynamic> params,
      {String? sessionId}) async {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _ws.add(jsonEncode({
      'id': id,
      'method': method,
      'params': params,
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
    }));
    return completer.future.timeout(const Duration(seconds: 30),
        onTimeout: () {
      _pending.remove(id);
      throw CdpError('$method timed out');
    });
  }

  @override
  Future<Map<String, dynamic>> waitEvent(String method, String sessionId) {
    final completer = Completer<Map<String, dynamic>>();
    _eventWaiters
        .putIfAbsent('$sessionId|$method', () => [])
        .add(completer);
    return completer.future.timeout(const Duration(seconds: 20),
        onTimeout: () {
      _eventWaiters['$sessionId|$method']?.remove(completer);
      throw CdpError('event $method timed out');
    });
  }

  @override
  Future<void> close() async {
    try {
      _process.kill();
    } catch (_) {}
    try {
      await _ws.close();
    } catch (_) {}
  }
}

class CdpError implements Exception {
  CdpError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Chromium-family binary lookup: GORK_BROWSER wins, then the usual names on
/// PATH (works in Termux, proot Debian, VPS — whatever installed them).
String? findBinary(Map<String, String> env) {
  final override = env['GORK_BROWSER'] ?? '';
  if (override.isNotEmpty) {
    return File(override).existsSync() ? override : override;
  }
  for (final name in [
    'chromium',
    'chromium-browser',
    'google-chrome',
    'google-chrome-stable',
    'chrome',
  ]) {
    if (_which(name)) return name;
  }
  return null;
}

bool _which(String name) {
  final result = Process.runSync('which', <String>[name]);
  return result.exitCode == 0;
}

// -- the sealed vault ---------------------------------------------------------

/// $GORK_HOME/vault.json — 0600, values only reachable to the daemon's own
/// process and the `gork vault` CLI on the same box. fill_secret reads it;
/// the values never travel back through any API response.
String vaultPath(String stateDir) => '$stateDir/vault.json';

Map<String, String> readVault(String stateDir) {
  final file = File(vaultPath(stateDir));
  if (!file.existsSync()) return {};
  try {
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return {for (final e in decoded.entries) e.key: e.value.toString()};
  } catch (_) {
    return {};
  }
}

String? readVaultSecret(String stateDir, String label) =>
    readVault(stateDir)[label];

Future<void> writeVaultSecret(String stateDir, String label, String value) async {
  if (label.isEmpty || label.contains('/')) {
    throw ArgumentError('label must be non-empty and path-free');
  }
  final vault = readVault(stateDir)..[label] = value;
  final file = File(vaultPath(stateDir));
  await file.create(recursive: true);
  await file.writeAsString(jsonEncode(vault));
  try {
    await Process.run('chmod', <String>['600', file.path]);
  } catch (_) {}
}

Future<bool> deleteVaultSecret(String stateDir, String label) async {
  final vault = readVault(stateDir);
  final removed = vault.remove(label) != null;
  if (removed) {
    await File(vaultPath(stateDir))
        .writeAsString(jsonEncode(vault));
  }
  return removed;
}

/// Sync twin for the CLI paths (process-local file ops, no awaits needed).
bool deleteVaultSecretSync(String stateDir, String label) {
  final vault = readVault(stateDir);
  final removed = vault.remove(label) != null;
  if (removed) {
    File(vaultPath(stateDir)).writeAsStringSync(jsonEncode(vault));
  }
  return removed;
}
