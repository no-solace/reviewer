import 'dart:convert';

import 'llm_client.dart';

/// Claude Messages API (`POST /v1/messages`).
class AnthropicClient extends LlmClient {
  AnthropicClient({required super.apiKey, required super.model});

  @override
  String get providerName => 'Claude';

  @override
  Uri endpoint() => Uri.parse('https://api.anthropic.com/v1/messages');

  /// `fallbacks: "default"` lets the API re-run a request that the model's
  /// safety classifiers decline on another model, server-side, instead of
  /// returning the refusal. Only offered on the newest models.
  bool get _supportsFallbacks => model.startsWith('claude-opus-5') || model.startsWith('claude-fable-5');

  @override
  Map<String, String> headers() => {
    'x-api-key': apiKey,
    'anthropic-version': '2023-06-01',
    if (_supportsFallbacks) 'anthropic-beta': 'server-side-fallback-2026-07-01',
  };

  @override
  Map<String, dynamic> body(LlmJsonRequest request) => {
    'model': model,
    'max_tokens': 64000,
    'stream': true,
    if (_supportsFallbacks) 'fallbacks': 'default',
    'thinking': {'type': 'adaptive'},
    'output_config': {
      'effort': 'high',
      'format': {'type': 'json_schema', 'schema': request.schema},
    },
    'system': request.system,
    'messages': [
      {
        'role': 'user',
        'content': [for (final part in request.parts) _content(part)],
      },
    ],
  };

  Map<String, dynamic> _content(LlmPart part) => switch (part) {
    LlmText(:final text) => {'type': 'text', 'text': text},
    LlmImage(:final bytes, :final mediaType) => {
      'type': 'image',
      'source': {'type': 'base64', 'media_type': mediaType, 'data': base64Encode(bytes)},
    },
    LlmPdf(:final bytes) => {
      'type': 'document',
      'source': {'type': 'base64', 'media_type': 'application/pdf', 'data': base64Encode(bytes)},
    },
  };

  @override
  void handleEvent(Map<String, dynamic> event, LlmStreamState state) {
    switch (event['type']) {
      case 'message_start':
        state.model = (event['message'] as Map<String, dynamic>)['model'] as String? ?? state.model;
      case 'content_block_delta':
        final delta = event['delta'] as Map<String, dynamic>;
        if (delta['type'] == 'text_delta') state.text.write(delta['text'] as String);
      case 'message_delta':
        switch ((event['delta'] as Map<String, dynamic>)['stop_reason']) {
          case 'max_tokens':
            state.truncated = true;
          case 'refusal':
            state.refusal = '';
        }
      case 'error':
        final error = event['error'] as Map<String, dynamic>? ?? const {};
        throw LlmException('Lỗi từ Claude: ${error['message'] ?? error}');
    }
  }
}
