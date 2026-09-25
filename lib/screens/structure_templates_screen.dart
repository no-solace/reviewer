import 'package:flutter/material.dart';

import '../models/structure_template.dart';
import '../services/structure_template_store.dart';

/// Lets the lecturer create, edit, duplicate and delete structure
/// templates. Changes are saved as they are typed.
class StructureTemplatesScreen extends StatefulWidget {
  const StructureTemplatesScreen({super.key});

  @override
  State<StructureTemplatesScreen> createState() => _StructureTemplatesScreenState();
}

class _StructureTemplatesScreenState extends State<StructureTemplatesScreen> {
  final StructureTemplateStore _store = StructureTemplateStore();
  StructureTemplateLibrary? _library;
  String? _editingId;

  /// Serializes writes so quick successive edits never interleave.
  Future<void> _pendingSave = Future.value();

  @override
  void initState() {
    super.initState();
    _store.load().then((library) {
      if (!mounted) return;
      setState(() {
        _library = library;
        _editingId = library.selected?.id ?? library.templates.firstOrNull?.id;
      });
    });
  }

  void _update(List<StructureTemplate> templates, {String? editingId}) {
    final library = StructureTemplateLibrary(templates: templates, selectedId: _library!.selectedId);
    setState(() {
      _library = library;
      if (editingId != null) _editingId = editingId;
    });
    _pendingSave = _pendingSave.then((_) => _store.save(library));
  }

  String _newId() => 'tpl-${DateTime.now().microsecondsSinceEpoch}';

  void _add() {
    final template = StructureTemplate(
      id: _newId(),
      name: 'Mẫu mới',
      sections: StructureTemplate.parseSections('Giới thiệu\nYêu cầu chức năng\nYêu cầu phi chức năng'),
    );
    _update([..._library!.templates, template], editingId: template.id);
  }

  void _duplicate(StructureTemplate source) {
    final copy = StructureTemplate(
      id: _newId(),
      name: '${source.name} (bản sao)',
      description: source.description,
      sections: source.sections,
    );
    _update([..._library!.templates, copy], editingId: copy.id);
  }

  Future<void> _delete(StructureTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá mẫu?'),
        content: Text('Mẫu "${template.name}" sẽ bị xoá vĩnh viễn.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Xoá')),
        ],
      ),
    );
    if (confirmed != true) return;

    final remaining = [..._library!.templates]..removeWhere((t) => t.id == template.id);
    _update(remaining, editingId: remaining.firstOrNull?.id ?? '');
  }

  void _replace(StructureTemplate updated) {
    _update([
      for (final t in _library!.templates) t.id == updated.id ? updated : t,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final library = _library;
    StructureTemplate? editing;
    for (final t in library?.templates ?? const <StructureTemplate>[]) {
      if (t.id == _editingId) editing = t;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mẫu cấu trúc tài liệu')),
      body: library == null
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 280,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ListView(
                          children: [
                            for (final t in library.templates)
                              ListTile(
                                title: Text(t.name),
                                subtitle: t.id == library.selectedId ? const Text('Đang dùng') : null,
                                selected: t.id == _editingId,
                                onTap: () => setState(() => _editingId = t.id),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (action) =>
                                      action == 'duplicate' ? _duplicate(t) : _delete(t),
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(value: 'duplicate', child: Text('Nhân bản')),
                                    PopupMenuItem(value: 'delete', child: Text('Xoá')),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: FilledButton.tonalIcon(
                          onPressed: _add,
                          icon: const Icon(Icons.add),
                          label: const Text('Thêm mẫu mới'),
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: editing == null
                      ? const Center(child: Text('Chọn hoặc tạo một mẫu ở bên trái.'))
                      : _TemplateEditor(
                          key: ValueKey(editing.id),
                          template: editing,
                          onChanged: _replace,
                        ),
                ),
              ],
            ),
    );
  }
}

class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({super.key, required this.template, required this.onChanged});

  final StructureTemplate template;
  final ValueChanged<StructureTemplate> onChanged;

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.template.name);
  late final TextEditingController _description = TextEditingController(text: widget.template.description);
  late final TextEditingController _sections = TextEditingController(text: widget.template.sectionsText);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _sections.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      widget.template.copyWith(
        name: _name.text.trim().isEmpty ? 'Mẫu không tên' : _name.text.trim(),
        description: _description.text.trim(),
        sections: StructureTemplate.parseSections(_sections.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Tên mẫu', border: OutlineInputBorder()),
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Mô tả / ghi chú cho AI (không bắt buộc)',
              hintText: 'VD: Đồ án môn Nhập môn CNPM, nhóm 3–5 sinh viên',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _emit(),
          ),
          const SizedBox(height: 12),
          Text(
            'Mỗi dòng là một mục. Thụt lề (2 dấu cách) để tạo mục con. '
            'Bắt đầu bằng "?" nếu mục không bắt buộc. Sau dấu "|" ghi yêu cầu nội dung của mục.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextField(
                    controller: _sections,
                    expands: true,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontFamily: 'Consolas', fontSize: 14),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Giới thiệu\n  Mục đích\n  ? Tài liệu tham khảo\n'
                          'Yêu cầu chức năng | Mỗi yêu cầu có mã FR-xx',
                    ),
                    onChanged: (_) => _emit(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Text('Xem trước', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        ..._preview(context, widget.template.sections, 0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _preview(BuildContext context, List<TemplateSection> sections, int depth) {
    final theme = Theme.of(context);
    return [
      for (final s in sections) ...[
        Padding(
          padding: EdgeInsets.only(left: depth * 20.0, bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    s.required ? Icons.check_box_outlined : Icons.check_box_outline_blank,
                    size: 16,
                    color: s.required ? theme.colorScheme.primary : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.required ? s.title : '${s.title} (tuỳ chọn)',
                      style: depth == 0 ? const TextStyle(fontWeight: FontWeight.w600) : null,
                    ),
                  ),
                ],
              ),
              if (s.guidance.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Text(s.guidance, style: theme.textTheme.bodySmall),
                ),
            ],
          ),
        ),
        ..._preview(context, s.children, depth + 1),
      ],
    ];
  }
}
