import 'package:flutter/material.dart';

import '../models/document_ai_review.dart';
import '../models/document_section.dart';
import '../models/review_version.dart';
import '../models/section_content.dart';
import '../models/section_review.dart';
import '../models/structure_template.dart';
import '../services/document_structure_service.dart';
import '../services/review_store.dart';
import '../services/section_content_loader.dart';
import '../widgets/ai_review_panel.dart';
import '../widgets/document_view.dart';
import '../widgets/outline_tree.dart';
import '../widgets/section_review_panel.dart';
import 'review_history_screen.dart';

/// Main review screen for one saved version: an outline on the left, and a
/// continuous page on the right with pass/fail controls for the section in view.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.version,
    required this.versionNumber,
    required this.sourcePath,
    this.readOnly = false,
    this.store,
    this.template,
  });

  final ReviewVersion version;
  final int versionNumber;

  /// File the user picked this session, used when starting another version.
  final String sourcePath;
  final bool readOnly;
  final ReviewStore? store;

  /// Structure template the AI check compares the document against.
  final StructureTemplate? template;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final String _path = widget.version.savedPath;
  late final Future<DocumentOutline> _outlineFuture = DocumentStructureService().analyze(_path);
  late final SectionContentLoader _contentLoader = createSectionContentLoader(_path);
  late final ReviewStore _reviewStore = widget.store ?? ReviewStore();
  final Map<String, Future<SectionContent>> _contentCache = {};

  Map<String, SectionReview> _reviews = {};
  final ValueNotifier<DocumentSection?> _focused = ValueNotifier<DocumentSection?>(null);
  final ValueNotifier<String?> _scrollRequest = ValueNotifier<String?>(null);
  bool _aiPanelOpen = false;

  /// Bumped when a note is changed from outside [SectionReviewPanel] (e.g.
  /// "Thêm vào ghi chú" in the AI panel) so the panel is rebuilt with a
  /// fresh note controller.
  int _noteRevision = 0;

  @override
  void initState() {
    super.initState();
    _reviewStore.loadVersion(widget.version).then((reviews) {
      if (!mounted) return;
      setState(() => _reviews = reviews);
    });
  }

  @override
  void dispose() {
    _focused.dispose();
    _scrollRequest.dispose();
    _contentLoader.dispose();
    super.dispose();
  }

  void _focusFromScroll(DocumentSection section) {
    if (_focused.value?.id == section.id) return;
    _focused.value = section;
  }

  void _focusFromTree(DocumentSection section) {
    _focused.value = section;
    _scrollRequest.value = null;
    _scrollRequest.value = section.id;
  }

  Future<SectionContent> _loadContent(DocumentSection section) {
    return _contentCache.putIfAbsent(section.id, () => _contentLoader.load(section));
  }

  void _updateReview(DocumentSection section, SectionReview review) {
    if (widget.readOnly) return;
    setState(() => _reviews = {..._reviews, section.id: review});
    _reviewStore.saveVersion(widget.version, _reviews);
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReviewHistoryScreen(
          fileName: widget.version.fileName,
          sourcePath: widget.sourcePath,
          store: _reviewStore,
          template: widget.template,
        ),
      ),
    );
  }

  void _addToNote(DocumentSection section, String text) {
    if (widget.readOnly) return;
    final review = _reviews[section.id] ?? const SectionReview();
    final note = review.note.trim().isEmpty ? '- $text' : '${review.note.trimRight()}\n- $text';
    setState(() {
      _reviews = {..._reviews, section.id: review.copyWith(note: note)};
      _noteRevision++;
    });
    _reviewStore.saveVersion(widget.version, _reviews);
    _focusFromTree(section);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã thêm vào ghi chú của "${section.title}".')),
    );
  }

  void _applyAiReview(DocumentAiReview review) {
    if (widget.readOnly || review.sectionGrades.isEmpty) return;
    final next = Map<String, SectionReview>.from(_reviews);
    for (final grade in review.sectionGrades) {
      next[grade.sectionId] = SectionReview(
        status: grade.status == AiGradeStatus.pass ? ReviewStatus.pass : ReviewStatus.fail,
        note: sectionNoteFromGrade(grade, review.issues),
      );
    }
    setState(() {
      _reviews = next;
      _noteRevision++;
      _aiPanelOpen = true;
    });
    _reviewStore.saveVersion(widget.version, next);
    final pass = next.values.where((item) => item.status == ReviewStatus.pass).length;
    final fail = next.values.where((item) => item.status == ReviewStatus.fail).length;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã chấm $pass mục đạt, $fail mục chưa đạt và ghi chú vào từng mục.')),
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
        title: Text('${widget.version.fileName} · Bản ${widget.versionNumber}'),
        actions: [
          IconButton(
            tooltip: 'Các bản review',
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
          ),
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

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.readOnly)
                const _WarningBanner(
                  info: true,
                  message:
                      'Đang xem bản review cũ. Ghi chú và đánh giá được giữ nguyên để đối chiếu khi sửa tài liệu.',
                ),
              if (outline.warning != null) _WarningBanner(message: outline.warning!),
              Expanded(
                child: ValueListenableBuilder<DocumentSection?>(
                  valueListenable: _focused,
                  child: DocumentView(
                    sections: flat,
                    selectedId: null,
                    scrollRequest: _scrollRequest,
                    reviews: _reviews,
                    loadContent: _loadContent,
                    onSectionFocused: _focusFromScroll,
                  ),
                  builder: (context, selected, document) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 380,
                          child: OutlineTree(
                            sections: outline.sections,
                            selectedId: selected?.id,
                            reviewState: _reviews,
                            onSectionSelected: _focusFromTree,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(child: document!),
                              SectionReviewPanel(
                                key: ValueKey('${selected?.id}-$_noteRevision'),
                                section: selected,
                                readOnly: widget.readOnly,
                                review: selected == null
                                    ? const SectionReview()
                                    : (_reviews[selected.id] ?? const SectionReview()),
                                onReviewChanged: selected == null || widget.readOnly
                                    ? (_) {}
                                    : (review) => _updateReview(selected, review),
                              ),
                            ],
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
                                  version: widget.version,
                                  store: _reviewStore,
                                  readOnly: widget.readOnly,
                                  filePath: _path,
                                  sections: outline.sections,
                                  contentLoader: _contentLoader,
                                  template: widget.template,
                                  focusedSectionId: selected?.id,
                                  onSectionTap: _focusFromTree,
                                  onAddToNote: _addToNote,
                                  onReviewReady: _applyAiReview,
                                  onReviewLoaded: () {
                                    if (!_aiPanelOpen && mounted) setState(() => _aiPanelOpen = true);
                                  },
                                  onClose: () => setState(() => _aiPanelOpen = false),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
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
  const _WarningBanner({required this.message, this.info = false});

  final String message;
  final bool info;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = info ? const Color(0xFFFFF8E1) : colorScheme.errorContainer;
    final foreground = info ? const Color(0xFF5D4037) : colorScheme.onErrorContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: background,
      child: Row(
        children: [
          Icon(Icons.info_outline, color: foreground, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: foreground)),
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
