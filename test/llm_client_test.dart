import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:gork/providers/providers.dart';
import 'package:gork/services/llm_client.dart';

ProviderEntry get _openai => providerById('openai')!;
ProviderEntry get _anthropic => providerById('anthropic')!;

void main() {
  group('OpenAI-compatible format', () {
    test('sends bearer auth, model and messages; parses content', () async {
      Uri? capturedUri;
      Map<String, String>? capturedHeaders;
      Map<String, dynamic>? capturedBody;

      final client = MockClient((request) async {
        capturedUri = request.url;
        capturedHeaders = request.headers;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'model': 'gpt-4o-mini',
            'choices': [
              {'message': {'role': 'assistant', 'content': 'Hello!'}}
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client2 = LlmClient(client: client);
      final reply = await client2.complete(
        provider: _openai,
        apiKey: 'sk-test',
        messages: const [
          ChatMessage('system', 'You are gork.'),
          ChatMessage('user', 'hi'),
        ],
      );

      expect(capturedUri.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(capturedHeaders!['Authorization'], 'Bearer sk-test');
      expect(capturedBody!['model'], 'gpt-4o-mini');
      expect((capturedBody!['messages'] as List).length, 2);
      expect(reply.content, 'Hello!');
      expect(reply.wantsTool, isFalse);
    });

    test('parses tool_calls into ToolCall objects', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'model': 'gpt-4o-mini',
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '',
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {
                        'name': 'get_weather',
                        'arguments': '{"city":"Karachi"}'
                      }
                    }
                  ]
                }
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final reply = await LlmClient(client: client).complete(
        provider: _openai,
        apiKey: 'sk-test',
        messages: const [ChatMessage('user', 'weather?')],
      );

      expect(reply.wantsTool, isTrue);
      expect(reply.toolCalls.first.name, 'get_weather');
      expect(reply.toolCalls.first.id, 'call_1');
      expect(reply.toolCalls.first.arguments['city'], 'Karachi');
    });

    test('sends tools when provided', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': 'ok'}}
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await LlmClient(client: client).complete(
        provider: _openai,
        apiKey: 'sk-test',
        messages: const [ChatMessage('user', 'hi')],
        tools: const [
          ToolDef('get_weather', 'Get current weather', {
            'type': 'object',
            'properties': {'city': {'type': 'string'}},
          })
        ],
      );

      final tools = capturedBody!['tools'] as List;
      expect(tools.first['type'], 'function');
      expect(tools.first['function']['name'], 'get_weather');
    });

    test('non-200 raises LlmException with status', () async {
      final client = MockClient((request) async {
        return http.Response('{"error":"bad key"}', 401);
      });

      expect(
        () => LlmClient(client: client).complete(
          provider: _openai,
          apiKey: 'wrong',
          messages: const [ChatMessage('user', 'hi')],
        ),
        throwsA(isA<LlmException>()),
      );
    });

    test('custom provider without baseURL raises', () async {
      final custom = resolveProvider('openai-compatible');
      expect(
        () => LlmClient(client: MockClient((r) async => http.Response('{}', 200)))
            .complete(
          provider: custom,
          apiKey: 'k',
          messages: const [ChatMessage('user', 'hi')],
        ),
        throwsA(isA<LlmException>()),
      );
    });
  });

  group('Anthropic format', () {
    test('sends x-api-key + version headers, extracts system, parses text',
        () async {
      Uri? capturedUri;
      Map<String, String>? capturedHeaders;
      Map<String, dynamic>? capturedBody;

      final client = MockClient((request) async {
        capturedUri = request.url;
        capturedHeaders = request.headers;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'model': 'claude-sonnet-4',
            'content': [
              {'type': 'text', 'text': 'Hi there!'}
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final reply = await LlmClient(client: client).complete(
        provider: _anthropic,
        apiKey: 'ak-test',
        messages: const [
          ChatMessage('system', 'You are gork.'),
          ChatMessage('user', 'hello'),
        ],
        maxTokens: 512,
      );

      expect(capturedUri.toString(), 'https://api.anthropic.com/v1/messages');
      expect(capturedHeaders!['x-api-key'], 'ak-test');
      expect(capturedHeaders!['anthropic-version'], '2023-06-01');
      expect(capturedBody!['system'], 'You are gork.');
      expect(capturedBody!['max_tokens'], 512);
      expect((capturedBody!['messages'] as List).first['role'], 'user');
      expect(reply.content, 'Hi there!');
    });

    test('parses tool_use blocks', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'model': 'claude-sonnet-4',
            'content': [
              {'type': 'tool_use', 'id': 'tu_1', 'name': 'add_memory',
               'input': {'fact': 'likes tea'}}
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final reply = await LlmClient(client: client).complete(
        provider: _anthropic,
        apiKey: 'ak-test',
        messages: const [ChatMessage('user', 'remember I like tea')],
      );

      expect(reply.wantsTool, isTrue);
      expect(reply.toolCalls.first.name, 'add_memory');
      expect(reply.toolCalls.first.arguments['fact'], 'likes tea');
    });

    test('sends anthropic-shaped tools', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'content': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await LlmClient(client: client).complete(
        provider: _anthropic,
        apiKey: 'ak-test',
        messages: const [ChatMessage('user', 'hi')],
        tools: const [
          ToolDef('get_weather', 'Get weather', {
            'type': 'object',
            'properties': {'city': {'type': 'string'}},
          })
        ],
      );

      final tools = capturedBody!['tools'] as List;
      expect(tools.first['name'], 'get_weather');
      expect(tools.first['input_schema'], isNotNull);
    });
  });

  group('multimodal messages (Movement 32 — images see)', () {
    test('OpenAI-compatible: images serialize as image_url content parts',
        () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'I see a red square.'},
                'index': 0,
              }
            ],
            'model': 'gpt-4o',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await LlmClient(client: client).complete(
        provider: _openai,
        apiKey: 'sk-test',
        messages: const [
          ChatMessage('user', 'what is in this picture?', images: [
            ChatImage('image/png', 'aGk='),
          ]),
        ],
      );

      final content = capturedBody!['messages'].first['content'] as List;
      expect(content, hasLength(2));
      expect(content[0]['type'], 'text');
      expect(content[0]['text'], 'what is in this picture?');
      expect(content[1]['type'], 'image_url');
      expect(content[1]['image_url']['url'], 'data:image/png;base64,aGk=');
    });

    test('plain string messages stay plain strings', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'ok'},
                'index': 0,
              }
            ],
            'model': 'gpt-4o',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await LlmClient(client: client).complete(
        provider: _openai,
        apiKey: 'sk-test',
        messages: const [ChatMessage('user', 'hello')],
      );

      expect(capturedBody!['messages'].first['content'], 'hello');
    });

    test('Anthropic: images serialize as base64 source blocks before text',
        () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'content': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await LlmClient(client: client).complete(
        provider: _anthropic,
        apiKey: 'ak-test',
        messages: const [
          ChatMessage('user', 'describe this', images: [
            ChatImage('image/jpeg', 'aGk='),
          ]),
        ],
      );

      final content = capturedBody!['messages'].first['content'] as List;
      expect(content, hasLength(2));
      expect(content[0]['type'], 'image');
      expect(content[0]['source']['type'], 'base64');
      expect(content[0]['source']['media_type'], 'image/jpeg');
      expect(content[0]['source']['data'], 'aGk=');
      expect(content[1]['type'], 'text');
      expect(content[1]['text'], 'describe this');
    });
  });
}
