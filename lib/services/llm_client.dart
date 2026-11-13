import 'dart:convert';

import 'package:http/http.dart' as http;

import '../providers/providers.dart';

/// An image riding inside a message, for vision-capable providers.
/// [mediaType] is a concrete MIME type (image/jpeg, image/png, image/webp,
/// image/gif); [base64Data] is the raw base64 payload without the data-URI
/// prefix.
class ChatImage {
  final String mediaType;
  final String base64Data;

  const ChatImage(this.mediaType, this.base64Data);
}

/// A single chat message. role: system | user | assistant | tool.
class ChatMessage {
  final String role;
  final String content;

  /// For assistant messages carrying tool calls (OpenAI protocol).
  final List<ToolCall>? toolCalls;

  /// For tool-result messages (role == 'tool').
  final String? toolCallId;

  /// Images attached to this message (user turns). When present, the
  /// message serializes as multimodal content parts instead of a plain
  /// string; providers that cannot see images error visibly, which is the
  /// honest outcome.
  final List<ChatImage>? images;

  const ChatMessage(this.role, this.content,
      {this.toolCalls, this.toolCallId, this.images});

  Map<String, dynamic> toOpenAiJson() {
    final map = <String, dynamic>{'role': role};
    if (images != null && images!.isNotEmpty) {
      map['content'] = [
        {'type': 'text', 'text': content},
        for (final img in images!)
          {
            'type': 'image_url',
            'image_url': {'url': 'data:${img.mediaType};base64,${img.base64Data}'},
          },
      ];
    } else {
      map['content'] = content;
    }
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      map['tool_calls'] = [
        for (final c in toolCalls!)
          {
            'id': c.id,
            'type': 'function',
            'function': {'name': c.name, 'arguments': c.argumentsJson},
          }
      ];
    }
    if (toolCallId != null) map['tool_call_id'] = toolCallId;
    return map;
  }

  /// Anthropic content blocks: image blocks first, then text.
  List<Map<String, dynamic>> _anthropicContent() {
    return [
      for (final img in images ?? const <ChatImage>[])
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': img.mediaType,
            'data': img.base64Data,
          },
        },
      {'type': 'text', 'text': content},
    ];
  }

  Map<String, dynamic> toAnthropicJson() => {
        'role': role,
        'content': (images != null && images!.isNotEmpty)
            ? _anthropicContent()
            : content,
      };
}

/// A tool the model may call (function calling).
class ToolDef {
  final String name;
  final String description;
  final Map<String, dynamic> parametersSchema;

  const ToolDef(this.name, this.description, this.parametersSchema);

  Map<String, dynamic> toOpenAiJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parametersSchema,
        },
      };

  Map<String, dynamic> toAnthropicJson() => {
        'name': name,
        'description': description,
        'input_schema': parametersSchema,
      };
}

/// A tool call requested by the model.
class ToolCall {
  final String id;
  final String name;
  final String argumentsJson;

  const ToolCall(this.id, this.name, this.argumentsJson);

  Map<String, dynamic> get arguments =>
      argumentsJson.isEmpty ? {} : jsonDecode(argumentsJson) as Map<String, dynamic>;
}

/// The model's reply: text content plus any requested tool calls.
class LlmReply {
  final String content;
  final List<ToolCall> toolCalls;
  final String model;

  const LlmReply({
    required this.content,
    this.toolCalls = const [],
    required this.model,
  });

  bool get wantsTool => toolCalls.isNotEmpty;
}

class LlmException implements Exception {
  final int? status;
  final String message;

  const LlmException(this.message, {this.status});

  @override
  String toString() =>
      status == null ? 'LlmException: $message' : 'LlmException ${status}: $message';
}

/// ONE HTTP client for every provider. Only baseURL, headers and (for
/// Anthropic) the body shape differ.
class LlmClient {
  final http.Client _http;

  LlmClient({http.Client? client}) : _http = client ?? http.Client();

  Map<String, String> _headers(ProviderEntry provider, String apiKey) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    switch (provider.auth) {
      case ProviderAuth.bearer:
        headers['Authorization'] = 'Bearer $apiKey';
        if (provider.id == 'openrouter') {
          headers['HTTP-Referer'] = 'https://github.com/webdevshayan/gork';
          headers['X-Title'] = 'gork';
        }
        break;
      case ProviderAuth.anthropic:
        headers['x-api-key'] = apiKey;
        headers['anthropic-version'] = '2023-06-01';
        break;
    }
    return headers;
  }

  Future<LlmReply> complete({
    required ProviderEntry provider,
    required String apiKey,
    required List<ChatMessage> messages,
    String? model,
    List<ToolDef>? tools,
    int maxTokens = 1024,
  }) async {
    if (apiKey.isEmpty) {
      throw const LlmException('No API key provided');
    }
    final m = (model == null || model.isEmpty) ? provider.defaultModel : model;
    if (m.isEmpty) {
      throw LlmException('No model configured for provider ${provider.id}');
    }
    switch (provider.auth) {
      case ProviderAuth.bearer:
        return _completeOpenAiCompatible(provider, apiKey, messages, m, tools);
      case ProviderAuth.anthropic:
        return _completeAnthropic(provider, apiKey, messages, m, tools, maxTokens);
    }
  }

  // --- OpenAI-compatible format (openai, openrouter, gemini, custom) ---

  Future<LlmReply> _completeOpenAiCompatible(
    ProviderEntry provider,
    String apiKey,
    List<ChatMessage> messages,
    String model,
    List<ToolDef>? tools,
  ) async {
    if (provider.baseURL.isEmpty) {
      throw LlmException(
          'Provider ${provider.id} needs a baseURL (configure it in Settings)');
    }
    final body = <String, dynamic>{
      'model': model,
      'messages': [for (final m in messages) m.toOpenAiJson()],
    };
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = [for (final t in tools) t.toOpenAiJson()];
    }

    final url = '${provider.baseURL}/chat/completions';
    final response = await _request(url, provider, apiKey, body);
    if (response.statusCode != 200) {
      throw LlmException(_briefError(response.body),
          status: response.statusCode);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw const LlmException('Provider returned no choices');
    }
    final message = choices[0]['message'] as Map<String, dynamic>;
    final content = (message['content'] as String?) ?? '';
    final toolCalls = <ToolCall>[];
    final rawCalls = message['tool_calls'] as List?;
    if (rawCalls != null) {
      for (final c in rawCalls) {
        final call = c as Map<String, dynamic>;
        final fn = call['function'] as Map<String, dynamic>;
        toolCalls.add(ToolCall(
          (call['id'] as String?) ?? '',
          fn['name'] as String,
          (fn['arguments'] as String?) ?? '{}',
        ));
      }
    }
    return LlmReply(
      content: content,
      toolCalls: toolCalls,
      model: (data['model'] as String?) ?? model,
    );
  }

  // --- Anthropic format ---

  Future<LlmReply> _completeAnthropic(
    ProviderEntry provider,
    String apiKey,
    List<ChatMessage> messages,
    String model,
    List<ToolDef>? tools,
    int maxTokens,
  ) async {
    final systemLines = <String>[];
    final turns = <ChatMessage>[];
    for (final m in messages) {
      if (m.role == 'system') {
        systemLines.add(m.content);
      } else {
        turns.add(m);
      }
    }

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'messages': [for (final m in turns) m.toAnthropicJson()],
    };
    if (systemLines.isNotEmpty) {
      body['system'] = systemLines.join('\n\n');
    }
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = [for (final t in tools) t.toAnthropicJson()];
    }

    final url = '${provider.baseURL}/messages';
    final response = await _request(url, provider, apiKey, body);
    if (response.statusCode != 200) {
      throw LlmException(_briefError(response.body),
          status: response.statusCode);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final contentBlocks = data['content'] as List? ?? [];
    final text = StringBuffer();
    final toolCalls = <ToolCall>[];
    for (final block in contentBlocks) {
      final b = block as Map<String, dynamic>;
      if (b['type'] == 'text') {
        text.write(b['text'] as String? ?? '');
      } else if (b['type'] == 'tool_use') {
        toolCalls.add(ToolCall(
          (b['id'] as String?) ?? '',
          b['name'] as String,
          jsonEncode(b['input'] ?? {}),
        ));
      }
    }
    return LlmReply(
      content: text.toString(),
      toolCalls: toolCalls,
      model: (data['model'] as String?) ?? model,
    );
  }

  Future<http.Response> _request(
    String url,
    ProviderEntry provider,
    String apiKey,
    Map<String, dynamic> body,
  ) {
    return _http.post(
      Uri.parse(url),
      headers: _headers(provider, apiKey),
      body: jsonEncode(body),
    );
  }

  String _briefError(String body) {
    final trimmed = body.trim();
    if (trimmed.length > 300) trimmed.substring(0, 300);
    return trimmed.isEmpty ? 'Unknown provider error' : trimmed;
  }
}
