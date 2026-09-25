import 'dart:convert';

import 'llm_client.dart';

/// Gemini API (`models/{model}:streamGenerateContent`).
class GeminiClient extends LlmClient {
  GeminiClient({required super.apiKey, required super.model});

  static const _blockedFinishReasons = {
    'SAFETY',
    'RECITATION',
    'BLOCKLIST',
    'PROHIBITED_CONTENT',
    'SPII',
    'IMAGE_SAFETY',
  };

  @override
  String get providerName => 'Gemini';

  @override
  Uri endpoint() => Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/'
    '${Uri.encodeComponent(model)}:streamGenerateContent?alt=sse',
  );

  @override
  Map<String, String> headers() => {'x-goog-api-key': apiKey};

  @override
  Map<String, dynamic> body(LlmJsonRequest request) => {
    'systemInstruction': {
      'parts': [
        {'text': request.system},
      ],
    },
    'contents': [
      {
        'role': 'user',
        'parts': [for (final part in request.parts) _part(part)],
      },
    ],
    'generationConfig': {
      'responseMimeType': 'application/json',
      'responseJsonSchema': request.schema,
    },
  };

  Map<String, dynamic> _part(LlmPart part) => switch (part) {
    LlmText(:final text) => {'text': text},
    LlmImage(:final bytes, :final mediaType) => {
      'inlineData': {'mimeType': mediaType, 'data': base64Encode(bytes)},
    },
    LlmPdf(:final bytes) => {
      'inlineData': {'mimeType': 'application/pdf', 'data': base64Encode(bytes)},
    },
  };

  @override
  void handleEvent(Map<String, dynamic> event, LlmStreamState state) {
    final error = event['error'] as Map<String, dynamic>?;
    if (error != null) throw LlmException('Lỗi từ Gemini: ${error['message'] ?? error}');

    state.model = event['modelVersion'] as String? ?? state.model;

    final blockReason = (event['promptFeedback'] as Map<String, dynamic>?)?['blockReason'];
    if (blockReason != null) state.refusal = '($blockReason)';

    final candidates = event['candidates'] as List? ?? const [];
    if (candidates.isEmpty) return;
    final candidate = candidates.first as Map<String, dynamic>;

    final parts = (candidate['content'] as Map<String, dynamic>?)?['parts'] as List? ?? const [];
    for (final part in parts.cast<Map<String, dynamic>>()) {
      // Thought summaries are not part of the JSON answer.
      if (part['thought'] == true) continue;
      final text = part['text'];
      if (text is String) state.text.write(text);
    }

    final finishReason = candidate['finishReason'] as String?;
    if (finishReason == 'MAX_TOKENS') state.truncated = true;
    if (_blockedFinishReasons.contains(finishReason)) state.refusal = '($finishReason)';
  }
}
