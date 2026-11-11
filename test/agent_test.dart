import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/services/agent_service.dart';
import 'package:gork/services/chat_service.dart';
import 'package:gork/services/llm_client.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/tool_registry.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
    );
  });

  ChatService _chatWith(List<MockAnswer> script) {
    final store = InMemorySecureStore()..write('apikey.openai', 'sk-test');
    var callIndex = 0;
    return ChatService(
      vault: KeyVault(store),
      client: LlmClient(
        client: MockClient((request) async {
          final answer = script[callIndex.clamp(0, script.length - 1)];
          callIndex++;
          return http.Response(
            jsonEncode(answer.body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
  }

  test('agent runs one tool round then answers with the tool result',
      () async {
    Locator.memory.remember('likes tea');

    final chat = _chatWith([
      MockAnswer({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'c1',
                  'type': 'function',
                  'function': {'name': 'list_memory', 'arguments': '{}'}
                }
              ]
            }
          }
        ],
      }),
      MockAnswer({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': 'You like tea.',
            }
          }
        ],
      }),
    ]);

    final agent = AgentService(chat, buildAppToolRegistry(), Locator.memory);
    final result = await agent.run(providerId: 'openai', userText: 'what do I like?');

    expect(result.toolsUsed, ['list_memory']);
    expect(result.content, 'You like tea.');
  });

  test('tool arguments actually hit real stores during the loop', () async {
    final chat = _chatWith([
      MockAnswer({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'c1',
                  'type': 'function',
                  'function': {
                    'name': 'remember',
                    'arguments': '{"fact":"lives in Karachi"}'
                  }
                }
              ]
            }
          }
        ],
      }),
      MockAnswer({
        'choices': [
          {
            'message': {'content': 'Noted.'}
          }
        ],
      }),
    ]);

    final agent = AgentService(chat, buildAppToolRegistry(), Locator.memory);
    await agent.run(providerId: 'openai', userText: 'remember I live in Karachi');

    expect(Locator.memory.all(), contains('lives in Karachi'));
  });

  test('assistant tool_calls are sent back in proper OpenAI protocol',
      () async {
    final bodies = <Map<String, dynamic>>[];
    final store = InMemorySecureStore()..write('apikey.openai', 'sk');
    var first = true;
    final chat = ChatService(
      vault: KeyVault(store),
      client: LlmClient(
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (first) {
            first = false;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': '',
                      'tool_calls': [
                        {
                          'id': 'cc',
                          'type': 'function',
                          'function': {'name': 'list_memory', 'arguments': '{}'}
                        }
                      ]
                    }
                  }
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'choices': [
                {'message': {'content': 'done'}}
              ]
            }),
            200,
          );
        }),
      ),
    );

    final agent = AgentService(chat, buildAppToolRegistry(), Locator.memory);
    await agent.run(providerId: 'openai', userText: 'memory?');

    // Second request must contain: original user, assistant with tool_calls,
    // and a tool-role message with the tool_call_id.
    final second = bodies[1]['messages'] as List;
    final roles = [for (final m in second) m['role']];
    expect(roles, containsAll(['user', 'assistant', 'tool']));
    final toolMsg = second.firstWhere((m) => m['role'] == 'tool');
    expect(toolMsg['tool_call_id'], 'cc');
    expect(toolMsg['content'], isNotNull);
  });
}

class MockAnswer {
  final Map<String, dynamic> body;
  const MockAnswer(this.body);
}
