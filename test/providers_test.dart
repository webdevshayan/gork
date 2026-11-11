import 'package:flutter_test/flutter_test.dart';

import 'package:gork/providers/providers.dart';

void main() {
  test('provider table matches the BYOK spec exactly', () {
    expect(kProviders.length, 5);

    expect(providerById('openai')!.baseURL, 'https://api.openai.com/v1');
    expect(providerById('openai')!.defaultModel, 'gpt-4o-mini');
    expect(providerById('openai')!.auth, ProviderAuth.bearer);

    expect(providerById('openrouter')!.baseURL, 'https://openrouter.ai/api/v1');
    expect(providerById('openrouter')!.defaultModel, 'openrouter/auto');

    expect(
      providerById('gemini')!.baseURL,
      'https://generativelanguage.googleapis.com/v1beta/openai',
    );
    expect(providerById('gemini')!.defaultModel, 'gemini-2.0-flash');

    expect(providerById('anthropic')!.baseURL, 'https://api.anthropic.com/v1');
    expect(providerById('anthropic')!.defaultModel, 'claude-sonnet-4');
    expect(providerById('anthropic')!.auth, ProviderAuth.anthropic);

    expect(providerById('openai-compatible')!.isCustom, isTrue);
    expect(providerById('openai-compatible')!.auth, ProviderAuth.bearer);
  });

  test('resolveProvider fills user-supplied values for the custom entry', () {
    final p = resolveProvider('openai-compatible',
        baseURL: 'http://192.168.1.10:1234/v1', defaultModel: 'my-model');
    expect(p.baseURL, 'http://192.168.1.10:1234/v1');
    expect(p.defaultModel, 'my-model');
    expect(p.auth, ProviderAuth.bearer);
  });

  test('resolveProvider ignores user values for built-in providers', () {
    final p = resolveProvider('openai', baseURL: 'http://evil', defaultModel: 'x');
    expect(p.baseURL, 'https://api.openai.com/v1');
    expect(p.defaultModel, 'gpt-4o-mini');
  });

  test('unknown provider id throws', () {
    expect(() => resolveProvider('nope'), throwsArgumentError);
    expect(providerById('nope'), isNull);
  });
}
