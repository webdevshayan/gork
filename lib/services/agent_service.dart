import '../providers/providers.dart';
import 'chat_service.dart';
import 'llm_client.dart';
import 'memory_store.dart';
import 'tool_registry.dart';

class AgentResult {
  final String content;
  final List<String> toolsUsed;

  const AgentResult(this.content, this.toolsUsed);
}

/// The agent loop: chat + tool calls. Up to 6 tool rounds per user message
/// (raised from 3 so multi-step jobs complete in one go), plus one final
/// iteration reserved for the answer itself.
///
/// The OpenAI-compatible protocol is used properly (assistant tool_calls +
/// tool role messages). For Anthropic, whose protocol differs, the tool
/// results are fed back as a user message — a pragmatic bridge documented in
/// the code so behavior is honest and testable.
class AgentService {
  final ChatService _chat;
  final ToolRegistry _registry;
  final MemoryStore _memory;

  AgentService(this._chat, this._registry, this._memory);

  Future<AgentResult> run({
    required String providerId,
    required String userText,
    List<ChatMessage> priorMessages = const [],
    int maxRounds = 6,
  }) async {
    final systemText = 'You are gork, the user\u2019s personal AI assistant '
        'running on their Android phone. Be direct and concrete. '
        'Use the provided tools when they help. '
        'Sensitive actions (vault writes, task scheduling) must be described '
        'clearly before calling them.${_memory.systemPromptBlock()}';

    var messages = <ChatMessage>[
      ChatMessage('system', systemText),
      ...priorMessages,
      ChatMessage('user', userText),
    ];

    final toolsUsed = <String>[];

    // maxRounds = tool rounds; one extra iteration is always reserved for
    // the final answer so the budget never eats the reply.
    for (var round = 0; round <= maxRounds; round++) {
      final reply = await _chat.chat(
        providerId: providerId,
        messages: messages,
        tools: _registry.defs,
      );

      if (!reply.wantsTool) {
        return AgentResult(reply.content, toolsUsed);
      }

      if (round == maxRounds) {
        break; // budget exhausted mid-tool-call — stop safely below
      }

      for (final call in reply.toolCalls) {
        toolsUsed.add(call.name);
      }

      final provider = resolveProvider(providerId);
      if (provider.auth == ProviderAuth.anthropic) {
        // Bridge: append results as a user message.
        final results = <String>[];
        for (final call in reply.toolCalls) {
          final result = await _registry.execute(call.name, call.arguments);
          results.add('Tool ${call.name} result: $result');
        }
        messages = [
          ...messages,
          ChatMessage('assistant', reply.content),
          ChatMessage('user', results.join('\n')),
        ];
      } else {
        // Proper OpenAI tool protocol.
        messages = [
          ...messages,
          ChatMessage('assistant', reply.content, toolCalls: reply.toolCalls),
        ];
        for (final call in reply.toolCalls) {
          final result = await _registry.execute(call.name, call.arguments);
          messages.add(ChatMessage('tool', result, toolCallId: call.id));
        }
      }
    }

    return AgentResult(
        'I stopped after $maxRounds tool rounds to stay safe.', toolsUsed);
  }

  /// First provider (in spec order) that has a key saved.
  Future<String?> providerWithKey() async {
    for (final p in kProviders) {
      if (await _chat.hasKey(p.id)) return p.id;
    }
    return null;
  }
}
