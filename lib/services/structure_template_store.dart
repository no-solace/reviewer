import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/structure_template.dart';

/// The lecturer's saved structure templates and which one is selected for
/// new reviews.
class StructureTemplateLibrary {
  const StructureTemplateLibrary({required this.templates, this.selectedId});

  final List<StructureTemplate> templates;

  /// Null means "no template" — the AI falls back to a generic outline.
  final String? selectedId;

  StructureTemplate? get selected {
    for (final t in templates) {
      if (t.id == selectedId) return t;
    }
    return null;
  }
}

/// Persists [StructureTemplateLibrary] as JSON in the app's data directory.
/// Seeds [StructureTemplate.defaultTemplate] (selected) on first use.
class StructureTemplateStore {
  Future<StructureTemplateLibrary> load() async {
    final file = await _file();
    if (!await file.exists()) {
      return StructureTemplateLibrary(
        templates: const [StructureTemplate.defaultTemplate],
        selectedId: StructureTemplate.defaultTemplate.id,
      );
    }

    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return StructureTemplateLibrary(
      templates: [
        for (final t in json['templates'] as List? ?? const [])
          StructureTemplate.fromJson(t as Map<String, dynamic>),
      ],
      selectedId: json['selectedId'] as String?,
    );
  }

  Future<void> save(StructureTemplateLibrary library) async {
    final file = await _file();
    await file.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'templates': [for (final t in library.templates) t.toJson()],
        'selectedId': library.selectedId,
      }),
    );
  }

  Future<File> _file() async {
    final appSupportDir = await getApplicationSupportDirectory();
    return File('${appSupportDir.path}/structure_templates.json');
  }
}
