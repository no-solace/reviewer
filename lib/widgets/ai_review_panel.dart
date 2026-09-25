import 'package:flutter/material.dart';

import '../models/ai_settings.dart';
import '../models/document_ai_review.dart';
import '../models/document_section.dart';
import '../models/review_version.dart';
import '../models/section_review.dart';
import '../models/structure_template.dart';
import '../services/ai_review_store.dart';
import '../services/ai_settings_store.dart';
import '../services/document_ai_reviewer.dart';
import '../services/llm/llm_client.dart';
import '../services/review_store.dart';
import '../services/section_content_loader.dart';
import 'ai_settings_dialog.dart';
import 'review_status.dart';

/// Side panel that runs a whole-document AI check and lists its findings.
/// Keep it mounted while hidden (e.g. `Visibility(maintainState: true)`)
/// so a running check survives the panel being toggled.
class AiReviewPanel extends StatefulWidget {
  const AiReviewPanel({
    super.key,
    required this.version,
    required this.store,
    required this.filePath,
    required this.sections,
    required this.contentLoader,
    required this.template,
    required this.focusedSectionId,
    required this.onSectionTap,
    required this.onAddToNote,
    required this.onReviewReady,
    required this.onClose,
    this.onReviewLoaded,
    this.readOnly = false,
  });

  final ReviewVersion version;
  final ReviewStore store;
  final String filePath;
  final List<DocumentSection> sections;
  final SectionContentLoader contentLoader;
  final String? focusedSectionId;
  final bool readOnly;

  /// Called after a finished check is saved on this review version.
  final ValueChanged<DocumentAiReview> onReviewReady;

  /// Called when a previously saved check is found for this version.
  final VoidCallback? onReviewLoaded;

  /// The structure template chosen on the home page, or null for none.
  final StructureTemplate? template;
  final ValueChanged<DocumentSection> onSectionTap;

  /// Appends an issue's text to the given section's review note.
  final void Function(DocumentSection section, String text) onAddToNote;
  final VoidCallback onClose;

  @override
  State<AiReviewPanel> createState() => _AiReviewPanelState();
}

class _AiReviewPanelState extends State<AiReviewPanel> {
  final AiReviewStore _legacyStore = AiReviewStore();
  final AiSettingsStore _settingsStore = AiSettingsStore();
  final TextEditingController _instructionsController = TextEditingController();
  final ScrollController _resultsScroll = ScrollController();

  late final Map<String, DocumentSection> _sectionsById = {
    for (final section in _flatten(widget.sections)) section.id: section,
  };

  DocumentAiReview? _review;
  AiSettings? _settings;
  DocumentAiReviewer? _runningReviewer;
  String _status = '';
  String? _error;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _reloadSettings();
  }

  @override
  void didUpdateWidget(covariant AiReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusedSectionId != widget.focusedSectionId && !_showAll && _resultsScroll.hasClients) {
      _resultsScroll.jumpTo(0);
    }
  }

  Future<void> _loadSaved() async {
    final saved = await widget.store.loadAiReview(widget.version);
    final review = saved ?? await _legacyStore.load(widget.filePath);
    if (!mounted || review == null) return;
    setState(() => _review = review);
    if (saved == null && !widget.readOnly) {
      await widget.store.saveAiReview(widget.version, review);
    }
    if (review.sectionGrades.isNotEmpty || review.issues.isNotEmpty) {
      widget.onReviewLoaded?.call();
    }
  }

  Future<AiSettings> _reloadSettings() async {
    final settings = await _settingsStore.load();
    if (mounted) setState(() => _settings = settings);
    return settings;
  }

  Future<void> _editSettings() async {
    if (await showAiSettingsDialog(context) != null) await _reloadSettings();
  }

  @override
  void dispose() {
    _runningReviewer?.cancel();
    _instructionsController.dispose();
    _resultsScroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    var settings = await _reloadSettings();
    if (settings.apiKey.isEmpty) {
      if (!mounted) return;
      await _editSettings();
      settings = await _reloadSettings();
      if (settings.apiKey.isEmpty) {
        setState(() => _error = 'Chưa có API key cho ${settings.provider.label}.');
        return;
      }
    }

    final reviewer = DocumentAiReviewer(
      createLlmClient(settings),
      maxPdfBytes: settings.provider.maxPdfBytes,
    );
    setState(() {
      _runningReviewer = reviewer;
      _error = null;
      _status = '';
    });

    try {
      final review = await reviewer.review(
        filePath: widget.filePath,
        sections: widget.sections,
        contentLoader: widget.contentLoader,
        template: widget.template,
        extraInstructions: _instructionsController.text,
        onStatus: (status) {
          if (mounted) setState(() => _status = status);
        },
      );
      await widget.store.saveAiReview(widget.version, review);
      if (mounted) setState(() => _review = review);
      widget.onReviewReady(review);
    } on LlmException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Lỗi không mong đợi: $e');
    } finally {
      if (mounted) setState(() => _runningReviewer = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = _runningReviewer != null;
    final review = _review;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('AI kiểm tra tài liệu', style: theme.textTheme.titleMedium)),
              IconButton(
                tooltip: 'Cấu hình AI',
                icon: const Icon(Icons.settings),
                onPressed: running ? null : _editSettings,
              ),
              IconButton(tooltip: 'Đóng', icon: const Icon(Icons.close), onPressed: widget.onClose),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: _resultsScroll,
            padding: const EdgeInsets.all(16),
            children: [
              if (_settings != null)
                Text(
                  'AI: ${_settings!.provider.label} · ${_settings!.model}\n'
                  'Mẫu cấu trúc: ${widget.template?.name ?? 'không dùng (theo IEEE 830)'}',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _instructionsController,
                enabled: !running,
                decoration: const InputDecoration(
                  labelText: 'Yêu cầu riêng cho bài này (không bắt buộc)',
                  hintText: 'VD: đề bài yêu cầu ít nhất 10 use case và sơ đồ ERD',
                  border: OutlineInputBorder(),
                ),
                minLines: 1,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              if (running) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(_status),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _runningReviewer!.cancel,
                    icon: const Icon(Icons.stop),
                    label: const Text('Huỷ'),
                  ),
                ),
              ] else if (!widget.readOnly)
                FilledButton.icon(
                  onPressed: _run,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(review == null ? 'Chạy kiểm tra' : 'Chạy lại'),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (review == null && !running && _error == null) ...[
                const SizedBox(height: 16),
                Text(
                  'AI đọc toàn bộ tài liệu rồi chấm Đạt hoặc Chưa đạt cho từng mục, '
                  'ghi chú từng vấn đề vào đúng mục, và lưu kết quả cùng bản review này. '
                  'Khi lướt tài liệu, bảng này hiện đánh giá của mục đang xem.',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (review != null) ..._buildReview(context, review),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildReview(BuildContext context, DocumentAiReview review) {
    final theme = Theme.of(context);
    final issues = [...review.issues]..sort((a, b) => a.severity.index.compareTo(b.severity.index));
    final created = review.createdAt.toLocal();
    final date =
        '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year} '
        '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
    final passCount = review.sectionGrades.where((grade) => grade.status == AiGradeStatus.pass).length;
    final failCount = review.sectionGrades.where((grade) => grade.status == AiGradeStatus.fail).length;
    final focused = _sectionsById[widget.focusedSectionId];
    final focusedGrade = review.sectionGrades.where((grade) => grade.sectionId == widget.focusedSectionId).firstOrNull;
    final focusedIssues = [
      for (final issue in issues)
        if (issue.sectionId != null && issue.sectionId == widget.focusedSectionId) issue,
    ];

    final header = <Widget>[
      const SizedBox(height: 16),
      Text(
        'Kết quả lúc $date · ${review.model}'
        '${review.templateName == null ? '' : ' · mẫu "${review.templateName}"'}',
        style: theme.textTheme.bodySmall,
      ),
      if (review.sectionGrades.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('$passCount đạt · $failCount chưa đạt', style: theme.textTheme.titleSmall),
      ],
    ];

    if (!_showAll && focused != null) {
      return [
        ...header,
        _Heading('Đánh giá mục đang xem'),
        Text(focused.title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (focusedGrade == null)
          const Text('Mục này chưa có Đạt/Chưa đạt. Chạy lại để chấm toàn bộ tài liệu.')
        else ...[
          _GradeBanner(grade: focusedGrade),
          if (focusedGrade.note.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(focusedGrade.note),
          ],
        ],
        _Heading('Vấn đề của mục (${focusedIssues.length})'),
        if (focusedIssues.isEmpty) const Text('Không có vấn đề nào gắn với mục này.'),
        for (final issue in focusedIssues)
          _IssueCard(
            issue: issue,
            section: focused,
            onSectionTap: widget.onSectionTap,
            onAddToNote: widget.readOnly ? null : widget.onAddToNote,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => setState(() => _showAll = true), child: const Text('Xem toàn bộ kết quả')),
        ),
      ];
    }

    return [
      ...header,
      const SizedBox(height: 12),
      _Heading('Nhận xét tổng quan'),
      SelectableText(review.overallAssessment),
      if (review.strengths.isNotEmpty) ...[
        _Heading('Điểm tốt'),
        for (final strength in review.strengths) _Bullet(strength),
      ],
      if (review.missingSections.isNotEmpty) ...[
        _Heading('Mục còn thiếu (${review.missingSections.length})'),
        for (final missing in review.missingSections)
          _Bullet('${missing.name}: ${missing.reason}', bold: missing.name),
      ],
      _Heading('Vấn đề (${issues.length})'),
      if (issues.isEmpty) const Text('Không phát hiện vấn đề nào.'),
      for (final issue in issues)
        _IssueCard(
          issue: issue,
          section: _sectionsById[issue.sectionId],
          onSectionTap: widget.onSectionTap,
          onAddToNote: widget.readOnly ? null : widget.onAddToNote,
        ),
      if (focused != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _showAll = false),
            child: const Text('Theo mục đang xem'),
          ),
        ),
    ];
  }

  static List<DocumentSection> _flatten(List<DocumentSection> sections) {
    return [
      for (final section in sections) ...[section, ..._flatten(section.children)],
    ];
  }
}

class _GradeBanner extends StatelessWidget {
  const _GradeBanner({required this.grade});

  final AiSectionGrade grade;

  @override
  Widget build(BuildContext context) {
    final status = grade.status == AiGradeStatus.pass ? ReviewStatus.pass : ReviewStatus.fail;
    return Row(
      children: [
        Icon(status.icon, color: status.color, size: 20),
        const SizedBox(width: 8),
        Text(status.label, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: status.color)),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {this.bold});

  final String text;

  /// Optional leading part of [text] to render in bold.
  final String? bold;

  @override
  Widget build(BuildContext context) {
    final boldPart = bold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(
            child: boldPart != null && text.startsWith(boldPart)
                ? SelectableText.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: boldPart, style: const TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(text: text.substring(boldPart.length)),
                      ],
                    ),
                  )
                : SelectableText(text),
          ),
        ],
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({
    required this.issue,
    required this.section,
    required this.onSectionTap,
    required this.onAddToNote,
  });

  final AiIssue issue;
  final DocumentSection? section;
  final ValueChanged<DocumentSection> onSectionTap;
  final void Function(DocumentSection section, String text)? onAddToNote;

  static const _severityLabels = {
    AiIssueSeverity.high: 'Nghiêm trọng',
    AiIssueSeverity.medium: 'Trung bình',
    AiIssueSeverity.low: 'Nhỏ',
  };

  static const _categoryLabels = {
    AiIssueCategory.missingContent: 'Thiếu nội dung',
    AiIssueCategory.inconsistency: 'Mâu thuẫn',
    AiIssueCategory.ambiguity: 'Mơ hồ',
    AiIssueCategory.untestable: 'Không kiểm thử được',
    AiIssueCategory.diagram: 'Sơ đồ/hình',
    AiIssueCategory.other: 'Khác',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final severityColor = switch (issue.severity) {
      AiIssueSeverity.high => colorScheme.error,
      AiIssueSeverity.medium => Colors.orange.shade700,
      AiIssueSeverity.low => colorScheme.outline,
    };
    final section = this.section;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _severityLabels[issue.severity]!,
                  style: theme.textTheme.labelMedium?.copyWith(color: severityColor, fontWeight: FontWeight.bold),
                ),
                Text('· ${_categoryLabels[issue.category]!}', style: theme.textTheme.labelMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(issue.title, style: theme.textTheme.titleSmall),
            if (section != null)
              InkWell(
                onTap: () => onSectionTap(section),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '→ ${section.title}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            if (issue.evidence.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText(
                issue.evidence,
                style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
            if (issue.suggestion.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText('Gợi ý: ${issue.suggestion}'),
            ],
            if (section != null && onAddToNote != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => onAddToNote!(
                    section,
                    '${issue.title}${issue.suggestion.isEmpty ? '' : ' — ${issue.suggestion}'}',
                  ),
                  icon: const Icon(Icons.note_add_outlined, size: 18),
                  label: const Text('Thêm vào ghi chú'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
