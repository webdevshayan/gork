/// Provider abstraction — BYOK (Bring Your Own Key).
///
/// We never hardcode a provider. Most providers speak the OpenAI-compatible
/// format, so ONE HTTP client talks to all of them with a different baseURL
/// and headers. Anthropic has its own header style.
enum ProviderAuth { bearer, anthropic }

class ProviderEntry {
  final String id;
  final String name;
  final String baseURL;
  final ProviderAuth auth;
  final String defaultModel;

  /// True when the user supplies baseURL + model themselves
  /// (the "openai-compatible" row).
  final bool isCustom;

  const ProviderEntry({
    required this.id,
    required this.name,
    required this.baseURL,
    required this.auth,
    required this.defaultModel,
    this.isCustom = false,
  });
}

const List<ProviderEntry> kProviders = [
  ProviderEntry(
    id: 'openai',
    name: 'OpenAI',
    baseURL: 'https://api.openai.com/v1',
    auth: ProviderAuth.bearer,
    defaultModel: 'gpt-4o-mini',
  ),
  ProviderEntry(
    id: 'openrouter',
    name: 'OpenRouter',
    baseURL: 'https://openrouter.ai/api/v1',
    auth: ProviderAuth.bearer,
    defaultModel: 'openrouter/auto',
  ),
  ProviderEntry(
    id: 'gemini',
    name: 'Gemini',
    baseURL: 'https://generativelanguage.googleapis.com/v1beta/openai',
    auth: ProviderAuth.bearer,
    defaultModel: 'gemini-2.0-flash',
  ),
  ProviderEntry(
    id: 'anthropic',
    name: 'Anthropic',
    baseURL: 'https://api.anthropic.com/v1',
    auth: ProviderAuth.anthropic,
    defaultModel: 'claude-sonnet-4',
  ),
  ProviderEntry(
    id: 'openai-compatible',
    name: 'Custom (OpenAI-compatible)',
    baseURL: '',
    auth: ProviderAuth.bearer,
    defaultModel: '',
    isCustom: true,
  ),
];

ProviderEntry? providerById(String id) {
  for (final p in kProviders) {
    if (p.id == id) return p;
  }
  return null;
}

/// Resolve a provider, filling in user-supplied baseURL/model for the
/// custom OpenAI-compatible entry.
ProviderEntry resolveProvider(String id, {String? baseURL, String? defaultModel}) {
  final base = providerById(id);
  if (base == null) {
    throw ArgumentError('Unknown provider id: $id');
  }
  if (base.isCustom) {
    return ProviderEntry(
      id: base.id,
      name: base.name,
      baseURL: baseURL ?? base.baseURL,
      auth: base.auth,
      defaultModel: defaultModel ?? base.defaultModel,
      isCustom: true,
    );
  }
  return base;
}
