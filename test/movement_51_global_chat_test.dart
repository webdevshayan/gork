import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/screens/chat_screen.dart';
import 'package:gork/services/agent_service.dart';
import 'package:gork/services/chat_service.dart';
import 'package:gork/services/history_store.dart';
import 'package:gork/services/llm_client.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/memory_rooms.dart';
import 'package:gork/services/panels_store.dart';
import 'package:gork/services/projects_store.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/tasks_store.dart';
import 'package:gork/services/tool_registry.dart';
import 'package:gork/services/vault_store.dart';
import 'package:gork/services/weather_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 51 — the Chat tab IS one global chat (never deleted, full
/// top-to-bottom context) and the room-based memory system: rooms hold
/// blocks, blocks are sub-categorized, and the agent gets the full room
/// map in its system prompt while retrieve/mutate/add travel in ONE call.

class _BlockedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient();
}

class _BlockedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in widget tests');
}

/// Serves canned routes and records every request — stands in for both the
/// fake VPS (memory endpoints) and the fake LLM (chat/completions).
class _StubClient extends http.BaseClient {
  final List<String> urls = [];
  final List<String> bodies = [];
  final Map<String, String> routes;

  _StubClient(this.routes);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    urls.add(request.url.toString());
    bodies.add(request is http.Request ? request.body : '');
    for (final entry in routes.entries) {
      if (request.url.toString().contains(entry.key)) {
        return http.StreamedResponse(
            Stream.value(utf8.encode(entry.value)), 200,
            headers: {'content-type': 'application/json'});
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 404);
  }
}

ToolRegistry _registry({MemoryRoomsService? memoryRooms}) => ToolRegistry(
      memory: Locator.memory,
      projects: ProjectsStore(Locator.prefs),
      tasks: TasksStore(Locator.prefs),
      panels: PanelsStore(Locator.prefs),
      vault: VaultStore(Locator.store),
      weather: WeatherService(http.Client()),
      memoryRooms: memoryRooms,
    );

void main() {
  setUpAll(() {
    HttpOverrides.global = _BlockedOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  Future<void> pumpShell(WidgetTester tester,
      {required http.Client fakeChat}) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore()..write('apikey.openai', 'sk-test'),
      chat: ChatService(
        vault: KeyVault(InMemorySecureStore()..write('apikey.openai', 'sk-test')),
        client: LlmClient(client: fakeChat),
      ),
    );
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();
  }

  test('the global chat survives delete() and clear()', () async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
        prefs: await SharedPreferences.getInstance(),
        store: InMemorySecureStore());
    final now = DateTime.now().millisecondsSinceEpoch;
    await Locator.history.save(Conversation(
      id: kGlobalChatId,
      title: 'Hark',
      providerId: 'openai',
      updatedAt: now,
      messages: [ChatTurn('user', 'the full story of everything', time: now)],
    ));
    await Locator.history.save(Conversation(
      id: 'th9',
      title: 'Temp thread',
      providerId: 'openai',
      updatedAt: now,
      messages: const [],
    ));

    await Locator.history.delete(kGlobalChatId);
    expect(Locator.history.byId(kGlobalChatId), isNotNull,
        reason: 'the global chat never gets deleted');
    await Locator.history.delete('th9');
    expect(Locator.history.byId('th9'), isNull,
        reason: 'ordinary threads still delete fine');

    await Locator.history.clear();
    expect(Locator.history.byId(kGlobalChatId), isNotNull,
        reason: 'the global chat even survives clear-all');
    expect(Locator.history.byId('th9'), isNull);
  });

  test('memory_op tool: add + retrieve travel in ONE call', () async {
    final vps = _StubClient({
      '/v1/memory/op': jsonEncode({
        'results': [
          {'ok': true, 'id': 'b1'},
          {'ok': true, 'blocks': []},
        ],
        'map': {'rooms': []},
      }),
    });
    SharedPreferences.setMockInitialValues({'vps.url': 'https://vps.example'});
    final prefs = await SharedPreferences.getInstance();
    final rooms = MemoryRoomsService(
        client: vps,
        prefs: prefs,
        store: InMemorySecureStore()..write('vps.token', 'tok'));

    final out = await rooms.execute({
      'ops': [
        {
          'kind': 'add',
          'room': 'Work',
          'title': 'Taleem ERP',
          'category': 'projects',
          'content': 'ships Friday'
        },
        {'kind': 'retrieve', 'room': 'Work'},
      ],
    });
    expect(out, contains('"results"'));
    expect(vps.urls.single, contains('/v1/memory/op'),
        reason: 'everything happens in ONE call');
    final sent = jsonDecode(vps.bodies.single) as Map<String, dynamic>;
    expect((sent['ops'] as List).length, 2);
    expect(sent['ops'][0]['kind'], 'add');
    expect(sent['ops'][1]['kind'], 'retrieve');
  });

  test('memory_op without a VPS answers honestly', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final rooms = MemoryRoomsService(
        client: _StubClient({}), prefs: prefs, store: InMemorySecureStore());
    final out = await rooms.execute({
      'ops': [
        {'kind': 'retrieve', 'room': 'Work'},
      ],
    });
    expect(out, startsWith('error:'));
    expect(out, contains('VPS'));
  });

  test('the agent prompt carries the full room map', () async {
    final llm = _StubClient({
      '/chat/completions': jsonEncode({
        'choices': [
          {'message': {'role': 'assistant', 'content': 'ok'}},
        ],
      }),
    });
    final vps = _StubClient({
      '/v1/memory/map': jsonEncode({
        'rooms': [
          {
            'room': 'Work',
            'blocks': [
              {
                'id': 'b1',
                'title': 'Taleem ERP',
                'category': 'projects',
                'chars': 120,
                'updated_at': 1
              },
            ],
          },
          {'room': 'Personal', 'blocks': []},
        ],
      }),
    });

    SharedPreferences.setMockInitialValues({'vps.url': 'https://vps.example'});
    final prefs = await SharedPreferences.getInstance();
    final rooms = MemoryRoomsService(
        client: vps,
        prefs: prefs,
        store: InMemorySecureStore()..write('vps.token', 'tok'));

    final chat = ChatService(
      vault: KeyVault(InMemorySecureStore()..write('apikey.openai', 'sk-test')),
      client: LlmClient(client: llm),
    );
    final agent = AgentService(chat, _registry(memoryRooms: rooms),
        Locator.memory, memoryRooms: rooms);
    await agent.run(providerId: 'openai', userText: 'hi');

    final chatIdx = llm.urls.indexWhere((u) => u.contains('/chat/completions'));
    expect(chatIdx, isNot(-1));
    // The system message rides as JSON — parse it instead of grepping the
    // raw escaped body.
    final payload =
        jsonDecode(llm.bodies[chatIdx]) as Map<String, dynamic>;
    final systemSeen =
        (payload['messages'].first as Map<String, dynamic>)['content'] as String;
    expect(systemSeen, contains('Room "Work"'),
        reason: 'the agent always knows which rooms exist');
    expect(systemSeen, contains('"Taleem ERP" (projects, 120 chars'),
        reason: 'the agent knows which blocks are in each room');
    expect(systemSeen, contains('Room "Personal"'));
    expect(systemSeen, contains('memory_op'),
        reason: 'the one-call tool is named in the prompt');
  });

  testWidgets('the Chat tab is the global chat and the input lands in it',
      (tester) async {
    await pumpShell(
      tester,
      fakeChat: MockClient((request) async => http.Response(
            jsonEncode({
              'choices': [
                {'message': {'content': 'mock reply'}},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          )),
    );
    await tester.tap(find.byKey(const ValueKey('tab-chat')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget,
        reason: 'the chat tab shows the conversation itself');

    // Type and send from the shell input bar.
    await tester.enterText(
        find.byKey(const ValueKey('input-bar')), 'remember this forever');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send-button')));
    await tester.pumpAndSettle();

    final global = Locator.history.byId(kGlobalChatId);
    expect(global, isNotNull);
    expect(global!.messages.any((m) => m.content == 'remember this forever'),
        isTrue, reason: 'the message landed in the global conversation');
  });
}
