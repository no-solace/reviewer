import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/ai_settings.dart';
import 'anthropic_client.dart';
import 'gemini_client.dart';
import 'openai_client.dart';

/// Thrown for any failed AI request, with a message ready to show the
/// lecturer.
class LlmException implements Exception {
  const LlmException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// One piece of the user message, in provider-neutral form.
sealed class LlmPart {
  const LlmPart();
}

class LlmText extends LlmPart {
  const LlmText(this.text);

  final String text;
}

class LlmImage extends LlmPart {
  const LlmImage(this.bytes, this.mediaType);

  final Uint8List bytes;

  /// `image/png`, `image/jpeg`, `image/gif` or `image/webp`.
  final String mediaType;
}

class LlmPdf extends LlmPart {
  const LlmPdf(this.bytes, {this.filename = 'document.pdf'});

  final Uint8List bytes;
  final String filename;
}

/// A single-turn request whose answer must be JSON matching [schema].
class LlmJsonRequest {
  const LlmJsonRequest({
    required this.system,
    required this.parts,
    required this.schemaName,
    required this.schema,
  });

  final String system;
  final List<LlmPart> parts;
  final String schemaName;

  /// JSON Schema (objects use `additionalProperties: false` and list every
  /// property in `required`, which all three providers accept).
  final Map<String, dynamic> schema;
}

class LlmResponse {
  const LlmResponse({required this.text, required this.model});

  /// The JSON text of the answer.
  final String text;

  /// The model that actually answered, as reported by the provider.
  final String model;
}

/// Mutable state a provider fills in while parsing its SSE stream.
class LlmStreamState {
  LlmStreamState(this.model);

  final StringBuffer text = StringBuffer();
  String model;
  bool truncated = false;

  /// Set when the provider declined to answer (safety filter, refusal).
  String? refusal;
}

/// Base for the provider clients: every provider is called over raw HTTP
/// (none of them has an official Dart SDK) and always streamed (SSE), since
/// a whole-document review can run for minutes. Subclasses supply the
/// endpoint, headers, request body and how to read each stream event.
abstract class LlmClient {
  LlmClient({required this.apiKey, required this.model});

  final String apiKey;
  final String model;

  HttpClient? _http;
  bool _cancelled = false;

  /// Shown in error messages, e.g. "Claude".
  String get providerName;

  Uri endpoint();

  Map<String, String> headers();

  Map<String, dynamic> body(LlmJsonRequest request);

  /// Reads one decoded `data:` payload of the SSE stream into [state].
  /// Throws [LlmException] for an in-stream error event.
  void handleEvent(Map<String, dynamic> event, LlmStreamState state);

  /// Runs [request]. [onProgress] is called with the number of answer
  /// characters received so far (models may think silently first).
  Future<LlmResponse> generateJson(
    LlmJsonRequest request, {
    void Function(int outputChars)? onProgress,
  }) async {
    _cancelled = false;
    final http = _http = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final httpRequest = await http.postUrl(endpoint());
      httpRequest.headers.contentType = ContentType.json;
      headers().forEach(httpRequest.headers.set);
      httpRequest.add(utf8.encode(jsonEncode(body(request))));

      final response = await httpRequest.close();
      if (response.statusCode != 200) {
        final errorBody = await response.transform(utf8.decoder).join();
        throw _errorFor(response.statusCode, errorBody);
      }

      final state = LlmStreamState(model);
      await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        final before = state.text.length;
        handleEvent(jsonDecode(data) as Map<String, dynamic>, state);
        if (state.text.length != before) onProgress?.call(state.text.length);
      }

      if (_cancelled) throw const LlmException('Đã huỷ.');
      if (state.refusal != null) {
        throw LlmException('$providerName từ chối xử lý tài liệu này. ${state.refusal}'.trim());
      }
      if (state.truncated) {
        throw const LlmException(
          'Kết quả quá dài và bị cắt giữa chừng. Hãy thử lại hoặc thu hẹp yêu cầu riêng.',
        );
      }
      return LlmResponse(text: state.text.toString(), model: state.model);
    } on SocketException catch (e) {
      if (_cancelled) throw const LlmException('Đã huỷ.');
      throw LlmException('Không kết nối được tới $providerName: ${e.message}');
    } on HttpException catch (e) {
      // Also raised when [cancel] force-closes the connection mid-stream.
      if (_cancelled) throw const LlmException('Đã huỷ.');
      throw LlmException('Kết nối tới $providerName bị gián đoạn: ${e.message}');
    } finally {
      _http?.close(force: true);
      _http = null;
    }
  }

  /// Aborts an in-flight [generateJson] call; it then throws "Đã huỷ.".
  void cancel() {
    _cancelled = true;
    _http?.close(force: true);
  }

  LlmException _errorFor(int statusCode, String body) {
    // All three providers report errors as {"error": {"message": ...}};
    // Gemini's streaming endpoint may wrap that in a one-element list.
    String? apiMessage;
    try {
      var json = jsonDecode(body);
      if (json is List && json.isNotEmpty) json = json.first;
      apiMessage = ((json as Map<String, dynamic>)['error'] as Map<String, dynamic>?)?['message'] as String?;
    } catch (_) {
      apiMessage = null;
    }

    final message = switch (statusCode) {
      401 || 403 => 'API key $providerName không hợp lệ hoặc không có quyền dùng model "$model". '
          'Kiểm tra lại trong Cấu hình AI.',
      404 => 'Không tìm thấy model "$model" của $providerName. Kiểm tra tên model trong Cấu hình AI.',
      413 => 'Tài liệu quá lớn để gửi trong một lần.',
      429 => 'Vượt giới hạn tần suất hoặc hạn mức của $providerName. Vui lòng thử lại sau.',
      500 || 502 || 503 || 529 => '$providerName đang quá tải hoặc gặp sự cố. Vui lòng thử lại sau.',
      _ => '$providerName trả lỗi $statusCode.',
    };
    return LlmException(
      apiMessage == null ? message : '$message\n($apiMessage)',
      statusCode: statusCode,
    );
  }
}

LlmClient createLlmClient(AiSettings settings) {
  final apiKey = settings.apiKey;
  final model = settings.model;
  return switch (settings.provider) {
    AiProvider.anthropic => AnthropicClient(apiKey: apiKey, model: model),
    AiProvider.openai => OpenAiClient(apiKey: apiKey, model: model),
    AiProvider.gemini => GeminiClient(apiKey: apiKey, model: model),
  };
}
