import 'dart:async';

import '../providers/providers.dart';
import 'llm_client.dart';
import 'secure_store.dart';

/// Unified chat entry point for the whole app: resolves the provider and the
/// on-device API key, then calls LlmClient. Keys never leave the device.
class ChatService {
  final KeyVault _vault;
  final LlmClient _client;

  ChatService({required KeyVault vault, LlmClient? client})
      : _vault = vault,
        _client = client ?? LlmClient();

  /// True when a key is saved on-device for this provider.
  Future<bool> hasKey(String providerId) async {
    final key = await _vault.getKey(providerId);
    return key != null && key.isNotEmpty;
  }

  Future<void> saveKey(String providerId, String apiKey) =>
      _vault.setKey(providerId, apiKey);

  Future<void> clearKey(String providerId) => _vault.clearKey(providerId);

  /// One chat round-trip.
  Future<LlmReply> chat({
    required String providerId,
    required List<ChatMessage> messages,
    String? model,
    String? baseURL,
    String? defaultModel,
    List<ToolDef>? tools,
    int maxTokens = 1024,
  }) async {
    final key = await _vault.getKey(providerId);
    if (key == null || key.isEmpty) {
      throw const LlmException(
          'No API key saved for this provider. Add one in Settings.');
    }
    final provider = resolveProvider(providerId,
        baseURL: baseURL, defaultModel: defaultModel);
    return _client.complete(
      provider: provider,
      apiKey: key,
      messages: messages,
      model: model,
      tools: tools,
      maxTokens: maxTokens,
    );
  }

  /// One tiny API call for the "Test Connection" button.
  /// Returns null on success, or a human-readable error.
  Future<String?> testConnection({
    required String providerId,
    String? model,
    String? baseURL,
    String? defaultModel,
  }) async {
    try {
      await chat(
        providerId: providerId,
        model: model,
        baseURL: baseURL,
        defaultModel: defaultModel,
        messages: const [ChatMessage('user', 'Reply with the single word: ok')],
        maxTokens: 16,
      );
      return null;
    } on LlmException catch (e) {
      return e.message;
    } on TimeoutException {
      return 'Connection timed out after 15 seconds.';
    } catch (e) {
      return e.toString();
    }
  }
}
