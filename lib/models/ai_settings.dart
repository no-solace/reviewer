/// AI providers the document check can run on.
enum AiProvider {
  anthropic(
    label: 'Anthropic (Claude)',
    defaultModel: 'claude-opus-5',
    envVar: 'ANTHROPIC_API_KEY',
    keyHint: 'sk-ant-…',
    keyUrl: 'console.anthropic.com → API Keys',
    maxPdfBytes: 32 * 1024 * 1024,
  ),
  openai(
    label: 'OpenAI (GPT)',
    defaultModel: 'gpt-6-astra',
    envVar: 'OPENAI_API_KEY',
    keyHint: 'sk-…',
    keyUrl: 'platform.openai.com → API keys',
    maxPdfBytes: 32 * 1024 * 1024,
  ),
  gemini(
    label: 'Google Gemini',
    defaultModel: 'gemini-3.8-flash',
    envVar: 'GEMINI_API_KEY',
    keyHint: 'AIza…',
    keyUrl: 'aistudio.google.com → Get API key',
    // Inline (base64) request data is capped at 20 MB.
    maxPdfBytes: 20 * 1024 * 1024,
  );

  const AiProvider({
    required this.label,
    required this.defaultModel,
    required this.envVar,
    required this.keyHint,
    required this.keyUrl,
    required this.maxPdfBytes,
  });

  final String label;
  final String defaultModel;

  /// Environment variable used as the API key when none has been saved.
  final String envVar;
  final String keyHint;

  /// Where the lecturer creates a key, shown in the settings dialog.
  final String keyUrl;

  /// Largest PDF sent inline in one request.
  final int maxPdfBytes;
}

/// The lecturer's AI configuration: which provider is active, plus an API
/// key and model per provider (so switching back and forth keeps each one).
class AiSettings {
  const AiSettings({
    this.provider = AiProvider.anthropic,
    this.apiKeys = const {},
    this.models = const {},
  });

  final AiProvider provider;
  final Map<AiProvider, String> apiKeys;
  final Map<AiProvider, String> models;

  String apiKeyFor(AiProvider provider) => apiKeys[provider]?.trim() ?? '';

  String modelFor(AiProvider provider) {
    final model = models[provider]?.trim() ?? '';
    return model.isEmpty ? provider.defaultModel : model;
  }

  String get apiKey => apiKeyFor(provider);

  String get model => modelFor(provider);

  AiSettings copyWith({
    AiProvider? provider,
    Map<AiProvider, String>? apiKeys,
    Map<AiProvider, String>? models,
  }) {
    return AiSettings(
      provider: provider ?? this.provider,
      apiKeys: apiKeys ?? this.apiKeys,
      models: models ?? this.models,
    );
  }

  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'apiKeys': {for (final e in apiKeys.entries) e.key.name: e.value},
    'models': {for (final e in models.entries) e.key.name: e.value},
  };

  factory AiSettings.fromJson(Map<String, dynamic> json) {
    Map<AiProvider, String> byProvider(Object? raw) {
      final map = raw as Map<String, dynamic>? ?? const {};
      return {
        for (final provider in AiProvider.values)
          if (map[provider.name] is String) provider: map[provider.name] as String,
      };
    }

    return AiSettings(
      provider: AiProvider.values.firstWhere(
        (p) => p.name == json['provider'],
        orElse: () => AiProvider.anthropic,
      ),
      apiKeys: byProvider(json['apiKeys']),
      models: byProvider(json['models']),
    );
  }
}
