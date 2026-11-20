import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:http/http.dart' as http;
import 'package:gork/services/locator.dart';
import 'package:gork/services/browser_service.dart';
import 'package:gork/services/chat_service.dart';
import 'package:gork/services/llm_client.dart';
import 'package:gork/providers/providers.dart';
import 'package:gork/services/panels_store.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/tool_registry.dart';

/// Movement 70 fakes — the browser that answers every op, and the chat
/// that records the vision call.
class FakeBrowser extends BrowserService {
  FakeBrowser() : super(prefs: null, store: null);

  @override
  bool get configured => true;

  @override
  Future<Map<String, dynamic>?> op(String action,
      {String session = 'default',
      Map<String, dynamic> args = const {}}) async {
    if (action == 'screenshot') {
      return {
        'ok': true,
        'result': {'base64': 'ZmFrZS1wbmc='}
      };
    }
    return {'ok': true, 'result': {'action': action}};
  }

  @override
  Future<String> shell(String command, {int timeout = 60}) async =>
      'exit 0\nshell-ran: $command';
}

class FakeChat extends ChatService {
  FakeChat() : super(vault: _NullVault());

  List<ChatMessage> lastMessages = const [];

  @override
  Future<bool> hasKey(String providerId) async =>
      providerId == kProviders.first.id;

  @override
  Future<LlmReply> chat(
      {required String providerId,
      required List<ChatMessage> messages,
      String? model,
      String? baseURL,
      String? defaultModel,
      List<ToolDef>? tools,
      int maxTokens = 1024}) async {
    lastMessages = messages;
    return const LlmReply(
        content: 'page: one email field, one slider puzzle',
        model: 'fake-model');
  }
}

class _NullVault implements KeyVault {
  @override
  Future<String?> getKey(String providerId) async => null;
  @override
  Future<void> setKey(String providerId, String apiKey) async {}
  @override
  Future<void> clearKey(String providerId) async {}
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
    );
  });

  test('remember + list_memory affect the real memory store', () async {
    final registry = buildAppToolRegistry();

    final r1 = await registry.execute('remember', {'fact': 'likes tea'});
    expect(r1, 'remembered: likes tea');
    expect(Locator.memory.all(), ['likes tea']);

    final r2 = await registry.execute('list_memory', {});
    expect(r2, contains('likes tea'));
  });

  test('create_project, create_task, create_panel, save_vault_entry', () async {
    final registry = buildAppToolRegistry();

    await registry.execute('create_project', {'title': 'Move flat', 'notes': 'list'});
    expect(Locator.projects.all().single.title, 'Move flat');

    await registry.execute('create_task', {
      'title': 'News',
      'prompt': 'summarize news',
      'repeatMinutes': 120
    });
    expect(Locator.tasks.all().single.repeatMinutes, 120);

    await registry.execute('create_panel', {'title': 'Water', 'value': '6/8'});
    expect(Locator.panels.all().any((p) => p.title == 'Water'), isTrue);

    await registry.execute('save_vault_entry', {'title': 'Mail', 'secret': 'pw'});
    expect(await Locator.vault.all().then((e) => e.single.secret), 'pw');
  });

  test('unknown tool and empty args return safe error text', () async {
    final registry = buildAppToolRegistry();
    expect(await registry.execute('nope', {}), contains('unknown tool'));
    expect(await registry.execute('remember', {'fact': '  '}), contains('error'));
  });

  test('panel created via tool shows on Panels screen data', () async {
    final registry = buildAppToolRegistry();
    await registry.execute('create_panel', {'title': 'From agent'});
    final panels = Locator.panels.all();
    expect(panels.map((p) => p.title), contains('From agent'));
    expect(panels.first.source, PanelSource.weather); // seeded panel intact
  });

  test('describe: screenshot → vision → literal text for the AI', () async {
    final browser = FakeBrowser();
    final chat = FakeChat();
    final registry = ToolRegistry(
      memory: Locator.memory,
      projects: Locator.projects,
      tasks: Locator.tasks,
      panels: Locator.panels,
      vault: Locator.vault,
      weather: Locator.weather,
      browser: browser,
      chat: chat,
    );

    final out = await registry
        .execute('browser', {'action': 'describe', 'session': 's9'});
    expect(out, contains('slider puzzle'));
    final sent = chat.lastMessages.single;
    expect(sent.images, isNotNull);
    expect(sent.images!.single.base64Data, 'ZmFrZS1wbmc=');
    expect(sent.content, contains('Do not guess'));
  });

  test('describe without a chat client answers honestly', () async {
    final browser = FakeBrowser();
    final registry = ToolRegistry(
      memory: Locator.memory,
      projects: Locator.projects,
      tasks: Locator.tasks,
      panels: Locator.panels,
      vault: Locator.vault,
      weather: Locator.weather,
      browser: browser,
    );
    final out = await registry.execute('browser', {'action': 'describe'});
    expect(out, startsWith('error:'));
    expect(out, contains('vision'));
  });

  test('vps_shell passes the command through to the service', () async {
    final browser = FakeBrowser();
    final registry = ToolRegistry(
      memory: Locator.memory,
      projects: Locator.projects,
      tasks: Locator.tasks,
      panels: Locator.panels,
      vault: Locator.vault,
      weather: Locator.weather,
      browser: browser,
    );
    final out = await registry
        .execute('vps_shell', {'command': 'apt-get -y install chromium'});
    expect(out, contains('shell-ran: apt-get -y install chromium'));
  });

  test('browser enum carries every Movement 70 verb', () async {
    final registry = buildAppToolRegistry();
    final browserDef = registry.defs.firstWhere((d) => d.name == 'browser');
    final schema = browserDef.parametersSchema;
    final enum_ = (schema['properties']['action']['enum'] as List).cast<String>();
    for (final verb in [
      'navigate', 'click', 'type', 'read', 'back', 'scroll', 'screenshot',
      'fill_secret', 'drag', 'slide', 'wait', 'press', 'eval', 'describe'
    ]) {
      expect(enum_, contains(verb), reason: verb);
    }
    expect(registry.defs.any((d) => d.name == 'vps_shell'), isTrue);
  });
}
