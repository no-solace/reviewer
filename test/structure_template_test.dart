import 'package:flutter_test/flutter_test.dart';
import 'package:reviewer/models/ai_settings.dart';
import 'package:reviewer/models/structure_template.dart';

void main() {
  group('StructureTemplate.parseSections', () {
    test('nests by indentation and reads optional marks and guidance', () {
      final sections = StructureTemplate.parseSections('''
// ghi chú bị bỏ qua
1. Giới thiệu
  1.1 Mục đích
\t? 1.2 Tài liệu tham khảo

2. Yêu cầu chức năng | Mỗi yêu cầu có mã FR-xx
    Use case
''');

      expect(sections, hasLength(2));
      expect(sections[0].title, '1. Giới thiệu');
      expect(sections[0].children.map((s) => s.title), ['1.1 Mục đích', '1.2 Tài liệu tham khảo']);
      expect(sections[0].children[1].required, isFalse);
      expect(sections[1].guidance, 'Mỗi yêu cầu có mã FR-xx');
      expect(sections[1].children.single.title, 'Use case');
    });

    test('text format round-trips', () {
      const template = StructureTemplate.defaultTemplate;
      final reparsed = StructureTemplate.parseSections(template.sectionsText);
      expect(
        template.copyWith(sections: reparsed).toJson(),
        template.toJson(),
      );
    });

    test('prompt text marks optional sections and guidance', () {
      final prompt = StructureTemplate.defaultTemplate.toPromptText();
      expect(prompt, contains('- Tài liệu tham khảo (tuỳ chọn)'));
      expect(prompt, contains('- Yêu cầu chức năng — yêu cầu: Mỗi yêu cầu có mã định danh'));
    });
  });

  test('AiSettings keeps per-provider keys/models and falls back to default model', () {
    const settings = AiSettings(
      provider: AiProvider.gemini,
      apiKeys: {AiProvider.gemini: 'g-key', AiProvider.openai: 'o-key'},
      models: {AiProvider.openai: 'custom-model'},
    );
    final restored = AiSettings.fromJson(settings.toJson());
    expect(restored.provider, AiProvider.gemini);
    expect(restored.apiKey, 'g-key');
    expect(restored.model, AiProvider.gemini.defaultModel);
    expect(restored.modelFor(AiProvider.openai), 'custom-model');
  });
}
