import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reviewer/services/llm/anthropic_client.dart';
import 'package:reviewer/services/llm/gemini_client.dart';
import 'package:reviewer/services/llm/llm_client.dart';
import 'package:reviewer/services/llm/openai_client.dart';

final _request = LlmJsonRequest(
  system: 'sys',
  parts: [
    const LlmText('hello'),
    LlmImage(Uint8List.fromList([1, 2, 3]), 'image/png'),
    LlmPdf(Uint8List.fromList([4, 5]), filename: 'a.pdf'),
  ],
  schemaName: 'review',
  schema: const {'type': 'object'},
);

void main() {
  test('Anthropic request and stream events', () {
    final client = AnthropicClient(apiKey: 'k', model: 'claude-opus-5');
    final body = client.body(_request);
    final content = (body['messages'] as List).single['content'] as List;
    expect(content.map((c) => c['type']), ['text', 'image', 'document']);
    expect(body['fallbacks'], 'default');
    expect(client.headers()['anthropic-beta'], 'server-side-fallback-2026-07-01');
    expect(AnthropicClient(apiKey: 'k', model: 'claude-haiku-4-5').body(_request).containsKey('fallbacks'), isFalse);

    final state = LlmStreamState('claude-opus-5');
    client
      ..handleEvent({'type': 'message_start', 'message': {'model': 'claude-opus-4-8'}}, state)
      ..handleEvent({'type': 'content_block_delta', 'delta': {'type': 'thinking_delta', 'thinking': 'x'}}, state)
      ..handleEvent({'type': 'content_block_delta', 'delta': {'type': 'text_delta', 'text': '{"a":'}}, state)
      ..handleEvent({'type': 'content_block_delta', 'delta': {'type': 'text_delta', 'text': '1}'}}, state)
      ..handleEvent({'type': 'message_delta', 'delta': {'stop_reason': 'max_tokens'}}, state);
    expect(state.text.toString(), '{"a":1}');
    expect(state.model, 'claude-opus-4-8');
    expect(state.truncated, isTrue);
  });

  test('OpenAI request and stream events', () {
    final client = OpenAiClient(apiKey: 'k', model: 'gpt-x');
    final body = client.body(_request);
    final content = (body['input'] as List).single['content'] as List;
    expect(content.map((c) => c['type']), ['input_text', 'input_image', 'input_file']);
    expect(content[1]['image_url'], 'data:image/png;base64,AQID');
    expect(content[2]['file_data'], startsWith('data:application/pdf;base64,'));
    expect((body['text'] as Map)['format'], {
      'type': 'json_schema',
      'name': 'review',
      'schema': {'type': 'object'},
      'strict': true,
    });

    final state = LlmStreamState('gpt-x');
    client
      ..handleEvent({'type': 'response.output_text.delta', 'delta': '{}'}, state)
      ..handleEvent({'type': 'response.completed', 'response': {'model': 'gpt-x-2026'}}, state);
    expect(state.text.toString(), '{}');
    expect(state.model, 'gpt-x-2026');

    final refused = LlmStreamState('gpt-x');
    client.handleEvent({'type': 'response.refusal.delta', 'delta': 'no'}, refused);
    expect(refused.refusal, 'no');
    expect(
      () => client.handleEvent({'type': 'error', 'message': 'bad'}, refused),
      throwsA(isA<LlmException>()),
    );
  });

  test('Gemini request and stream events', () {
    final client = GeminiClient(apiKey: 'k', model: 'gemini-x');
    expect(client.endpoint().toString(), contains('models/gemini-x:streamGenerateContent?alt=sse'));
    final body = client.body(_request);
    final parts = (body['contents'] as List).single['parts'] as List;
    expect(parts[0], {'text': 'hello'});
    expect(parts[2]['inlineData']['mimeType'], 'application/pdf');
    expect(body['generationConfig']['responseJsonSchema'], {'type': 'object'});

    final state = LlmStreamState('gemini-x');
    client
      ..handleEvent({
        'modelVersion': 'gemini-x-001',
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'thinking…', 'thought': true},
                {'text': '{"a":1}'},
              ],
            },
          },
        ],
      }, state)
      ..handleEvent({
        'candidates': [
          {'finishReason': 'SAFETY'},
        ],
      }, state);
    expect(state.text.toString(), '{"a":1}');
    expect(state.model, 'gemini-x-001');
    expect(state.refusal, '(SAFETY)');
  });
}
