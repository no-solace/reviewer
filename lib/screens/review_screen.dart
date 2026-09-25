import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/document_section.dart';
import '../models/section_content.dart';
import '../models/section_review.dart';
import '../models/structure_template.dart';
import '../services/document_structure_service.dart';
import '../services/review_store.dart';
import '../services/section_content_loader.dart';
import '../widgets/ai_review_panel.dart';
import '../widgets/outline_tree.dart';
import '../widgets/section_review_panel.dart';

/// Main review screen for one document: an outline tree on the left, and
/// the selected section's content + pass/fail controls on the right.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.file, this.template});

  final PlatformFile file;

  /// Structure template the AI check compares the document against.
  final StructureTemplate? template;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final String _path = widget.file.path!;
  late final Future<DocumentOutline> _outlineFuture = DocumentStructureService().analyze(_path);
  late final SectionContentLoader _contentLoader = createSectionContentLoader(_path);
  final ReviewStore _reviewStore = ReviewStore();
  final Map<String, Future<SectionContent>> _contentCache = {};

  Map<String, SectionReview> _reviews = {};
  DocumentSection? _selected;
  bool _aiPanelOpen = false;

  /// Bumped when a note is changed from outside [SectionReviewPanel] (e.g.
  /// "Thêm vào ghi chú" in the AI panel) so the panel is rebuilt with a
  /// fresh note controller.
  int _noteRevision = 0;

  @override
  void initState() {
    super.initState();
    _reviewStore.load(_path).then((reviews) {
      if (!mounted) return;
      setState(() => _reviews = reviews);
    });
  }

  @override
  void dispose() {
    _contentLoader.dispose();
    super.dispose();
  }

  void _selectSection(DocumentSection section) {
    setState(() => _selected = section);
    _contentCache.putIfAbsent(section.id, () => _contentLoader.load(section));
  }

  void _updateReview(DocumentSection section, SectionReview review) {
    setState(() => _reviews = {..._reviews, section.id: review});
    _reviewStore.save(_path, _reviews);
  }

  void _addToNote(DocumentSection section, String text) {
    final review = _reviews[section.id] ?? const SectionReview();
    final note = review.note.trim().isEmpty ? '- $text' : '${review.note.trimRight()}\n- $text';
    _updateReview(section, review.copyWith(note: note));
    setState(() => _noteRevision++);
    _selectSection(section);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã thêm vào ghi chú của "${section.title}".')),
    );
  }

  List<DocumentSection> _flatten(List<DocumentSection> sections) {
    return [
      for (final section in sections) ...[section, ..._flatten(section.children)],
    ];
  }

  String _describeError(Object? error) {
    if (error is FormatException) return error.message;
    return 'Không thể phân tích tài liệu: $error';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonalIcon(
              onPressed: () => setState(() => _aiPanelOpen = !_aiPanelOpen),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI kiểm tra'),
            ),
          ),
        ],
      ),
      body: FutureBuilder<DocumentOutline>(
        future: _outlineFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorNotice(message: _describeError(snapshot.error));
          }

          final outline = snapshot.data!;
          if (outline.sections.isEmpty) {
            return _ErrorNotice(
              message: outline.warning ?? 'Không tìm thấy cấu trúc nào trong tài liệu.',
            );
          }

          final flat = _flatten(outline.sections);
          final reviewedCount = flat
              .where((s) => (_reviews[s.id]?.status ?? ReviewStatus.unreviewed) != ReviewStatus.unreviewed)
              .length;
          final selected = _selected;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (outline.warning != null) _WarningBanner(message: outline.warning!),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: flat.isEmpty ? 0 : reviewedCount / flat.length,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('$reviewedCount/${flat.length} mục đã chấm'),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 320,
                      child: OutlineTree(
                        sections: outline.sections,
                        selectedId: selected?.id,
                        reviewState: _reviews,
                        onSectionSelected: _selectSection,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: SectionReviewPanel(
                        key: ValueKey('${selected?.id}#$_noteRevision'),
                        section: selected,
                        contentFuture: selected == null ? null : _contentCache[selected.id],
                        review: selected == null
                            ? const SectionReview()
                            : (_reviews[selected.id] ?? const SectionReview()),
                        onReviewChanged: selected == null
                            ? (_) {}
                            : (review) => _updateReview(selected, review),
                      ),
                    ),
                    Visibility(
                      visible: _aiPanelOpen,
                      maintainState: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const VerticalDivider(width: 1),
                          SizedBox(
                            width: 420,
                            child: AiReviewPanel(
                              filePath: _path,
                              sections: outline.sections,
                              contentLoader: _contentLoader,
                              template: widget.template,
                              onSectionTap: _selectSection,
                              onAddToNote: _addToNote,
                              onClose: () => setState(() => _aiPanelOpen = false),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.info_outline, color: colorScheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: colorScheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 36),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
