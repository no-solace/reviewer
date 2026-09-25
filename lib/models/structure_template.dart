/// One expected section in a [StructureTemplate].
class TemplateSection {
  const TemplateSection({
    required this.title,
    this.required = true,
    this.guidance = '',
    this.children = const [],
  });

  final String title;

  /// False for sections students may leave out (e.g. appendices).
  final bool required;

  /// What the section must contain, e.g. "mỗi yêu cầu có mã FR-xx".
  final String guidance;
  final List<TemplateSection> children;

  Map<String, dynamic> toJson() => {
    'title': title,
    'required': required,
    'guidance': guidance,
    'children': [for (final c in children) c.toJson()],
  };

  factory TemplateSection.fromJson(Map<String, dynamic> json) {
    return TemplateSection(
      title: json['title'] as String? ?? '',
      required: json['required'] as bool? ?? true,
      guidance: json['guidance'] as String? ?? '',
      children: [
        for (final c in json['children'] as List? ?? const [])
          TemplateSection.fromJson(c as Map<String, dynamic>),
      ],
    );
  }
}

/// The structure a lecturer expects students' requirement documents to
/// follow. The AI check compares documents against the selected template
/// instead of a generic IEEE 830 outline.
///
/// Templates are edited as indented text (see [parseSections]):
///
/// ```text
/// 1. Giới thiệu
///   1.1 Mục đích
///   ? 1.4 Tài liệu tham khảo
/// 3. Yêu cầu chức năng | Mỗi yêu cầu có mã FR-xx
/// ```
class StructureTemplate {
  const StructureTemplate({
    required this.id,
    required this.name,
    this.description = '',
    this.sections = const [],
  });

  final String id;
  final String name;

  /// Free-form notes for the AI, e.g. "đồ án môn Nhập môn CNPM".
  final String description;
  final List<TemplateSection> sections;

  StructureTemplate copyWith({String? name, String? description, List<TemplateSection>? sections}) {
    return StructureTemplate(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      sections: sections ?? this.sections,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'sections': [for (final s in sections) s.toJson()],
  };

  factory StructureTemplate.fromJson(Map<String, dynamic> json) {
    return StructureTemplate(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      sections: [
        for (final s in json['sections'] as List? ?? const [])
          TemplateSection.fromJson(s as Map<String, dynamic>),
      ],
    );
  }

  /// Serializes [sections] to the editable text format read by
  /// [parseSections].
  String get sectionsText {
    final buffer = StringBuffer();
    void write(List<TemplateSection> sections, int depth) {
      for (final s in sections) {
        buffer
          ..write('  ' * depth)
          ..write(s.required ? '' : '? ')
          ..write(s.title)
          ..writeln(s.guidance.isEmpty ? '' : ' | ${s.guidance}');
        write(s.children, depth + 1);
      }
    }

    write(sections, 0);
    return buffer.toString();
  }

  /// Parses the text format: one section per line; indentation (spaces or
  /// tabs) nests a line under the closest less-indented line above it; a
  /// leading `?` marks the section optional; text after ` | ` is guidance.
  /// Blank lines and lines starting with `//` are ignored.
  static List<TemplateSection> parseSections(String text) {
    final roots = <_Draft>[];
    final stack = <_Draft>[];

    for (final rawLine in text.split('\n')) {
      // A tab counts as one level (2 spaces), matching the editor's hint.
      final line = rawLine.replaceAll('\t', '  ').trimRight();
      var content = line.trimLeft();
      if (content.isEmpty || content.startsWith('//')) continue;
      final indent = line.length - content.length;

      var required = true;
      if (content.startsWith('?')) {
        required = false;
        content = content.substring(1).trimLeft();
      }
      var guidance = '';
      final separator = content.indexOf('|');
      if (separator >= 0) {
        guidance = content.substring(separator + 1).trim();
        content = content.substring(0, separator).trim();
      }
      if (content.isEmpty) continue;

      final draft = _Draft(indent, content, required, guidance);
      while (stack.isNotEmpty && stack.last.indent >= indent) {
        stack.removeLast();
      }
      (stack.isEmpty ? roots : stack.last.children).add(draft);
      stack.add(draft);
    }

    return [for (final d in roots) d.build()];
  }

  /// Renders the template for the AI prompt.
  String toPromptText() {
    final buffer = StringBuffer('Mẫu cấu trúc "$name"');
    if (description.trim().isNotEmpty) buffer.write(' — ${description.trim()}');
    buffer.writeln(':');
    void write(List<TemplateSection> sections, int depth) {
      for (final s in sections) {
        buffer
          ..write('  ' * depth)
          ..write('- ${s.title}')
          ..write(s.required ? '' : ' (tuỳ chọn)')
          ..writeln(s.guidance.isEmpty ? '' : ' — yêu cầu: ${s.guidance}');
        write(s.children, depth + 1);
      }
    }

    write(sections, 0);
    return buffer.toString();
  }

  static const defaultTemplate = StructureTemplate(
    id: 'default-srs',
    name: 'SRS cơ bản (IEEE 830)',
    description: 'Mẫu đặc tả yêu cầu phần mềm cho đồ án sinh viên.',
    sections: [
      TemplateSection(
        title: 'Giới thiệu',
        children: [
          TemplateSection(title: 'Mục đích'),
          TemplateSection(title: 'Phạm vi', guidance: 'Nêu rõ hệ thống làm gì và không làm gì'),
          TemplateSection(title: 'Thuật ngữ và từ viết tắt'),
          TemplateSection(title: 'Tài liệu tham khảo', required: false),
        ],
      ),
      TemplateSection(
        title: 'Mô tả tổng quan',
        children: [
          TemplateSection(title: 'Bối cảnh sản phẩm'),
          TemplateSection(title: 'Đối tượng người dùng', guidance: 'Liệt kê các actor/nhóm người dùng và đặc điểm'),
          TemplateSection(title: 'Ràng buộc'),
          TemplateSection(title: 'Giả định và phụ thuộc'),
        ],
      ),
      TemplateSection(
        title: 'Yêu cầu chức năng',
        guidance: 'Mỗi yêu cầu có mã định danh (VD: FR-01), mô tả rõ ràng và kiểm thử được',
        children: [
          TemplateSection(title: 'Sơ đồ use case'),
          TemplateSection(
            title: 'Đặc tả use case',
            guidance: 'Mỗi use case có actor, tiền điều kiện, luồng chính, luồng thay thế, hậu điều kiện',
          ),
        ],
      ),
      TemplateSection(
        title: 'Yêu cầu phi chức năng',
        guidance: 'Hiệu năng, bảo mật, khả dụng… với tiêu chí đo được',
      ),
      TemplateSection(title: 'Yêu cầu dữ liệu', guidance: 'Sơ đồ ERD hoặc sơ đồ lớp, mô tả các thực thể'),
      TemplateSection(title: 'Giao diện người dùng', guidance: 'Mockup/wireframe các màn hình chính'),
      TemplateSection(title: 'Phụ lục', required: false),
    ],
  );
}

class _Draft {
  _Draft(this.indent, this.title, this.required, this.guidance);

  final int indent;
  final String title;
  final bool required;
  final String guidance;
  final List<_Draft> children = [];

  TemplateSection build() => TemplateSection(
    title: title,
    required: required,
    guidance: guidance,
    children: [for (final c in children) c.build()],
  );
}
