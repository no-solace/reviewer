import 'dart:convert';

import 'llm_client.dart';

/// OpenAI Responses API (`POST /v1/responses`).
class OpenAiClient extends LlmClient {
  OpenAiClient({required super.apiKey, required super.model});

  @override
  String get providerName => 'OpenAI';

  @override
  Uri endpoint() => Uri.parse('https://api.openai.com/v1/responses');

  @override
  Map<String, String> headers() => {'Authorization': 'Bearer $apiKey'};

  @override
  Map<String, dynamic> body(LlmJsonRequest request) => {
    'model': model,
    'stream': true,
    'instructions': request.system,
    'input': [
      {
        'role': 'user',
        'content': [for (final part in request.parts) _content(part)],
      },
    ],
    'text': {
      'format': {
        'type': 'json_schema',
        'name': request.schemaName,
        'schema': request.schema,
        'strict': true,
      },
    },
  };

  Map<String, dynamic> _content(LlmPart part) => switch (part) {
    LlmText(:final text) => {'type': 'input_text', 'text': text},
    LlmImage(:final bytes, :final mediaType) => {
      'type': 'input_image',
      'image_url': 'data:$mediaType;base64,${base64Encode(bytes)}',
    },
    LlmPdf(:final bytes, :final filename) => {
      'type': 'input_file',
      'filename': filename,
      'file_data': 'data:application/pdf;base64,${base64Encode(bytes)}',
    },
  };

  @override
  void handleEvent(Map<String, dynamic> event, LlmStreamState state) {
    final response = event['response'] as Map<String, dynamic>?;
    switch (event['type']) {
      case 'response.created' || 'response.completed':
        state.model = response?['model'] as String? ?? state.model;
      case 'response.output_text.delta':
        state.text.write(event['delta'] as String);
      case 'response.refusal.delta':
        state.refusal = '${state.refusal ?? ''}${event['delta']}';
      case 'response.incomplete':
        final reason = (response?['incomplete_details'] as Map<String, dynamic>?)?['reason'];
        if (reason == 'content_filter') {
          state.refusal = '';
        } else {
          state.truncated = true;
        }
      case 'response.failed':
        final error = response?['error'] as Map<String, dynamic>? ?? const {};
        throw LlmException('Lỗi từ OpenAI: ${error['message'] ?? error}');
      case 'error':
        final error = event['error'] as Map<String, dynamic>? ?? event;
        throw LlmException('Lỗi từ OpenAI: ${error['message'] ?? error}');
    }
  }
}
