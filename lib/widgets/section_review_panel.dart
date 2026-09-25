import 'package:flutter/material.dart';

import '../models/document_section.dart';
import '../models/section_review.dart';
import 'review_status.dart';

/// Pass/fail controls for the section currently in view. Give this widget a
/// `key` derived from the section id so switching sections gets a fresh
/// [TextEditingController].
class SectionReviewPanel extends StatefulWidget {
  const SectionReviewPanel({
    super.key,
    required this.section,
    required this.review,
    required this.onReviewChanged,
    this.readOnly = false,
  });

  final DocumentSection? section;
  final SectionReview review;
  final ValueChanged<SectionReview> onReviewChanged;
  final bool readOnly;

  @override
  State<SectionReviewPanel> createState() => _SectionReviewPanelState();
}

class _SectionReviewPanelState extends State<SectionReviewPanel> {
  late final TextEditingController _noteController = TextEditingController(
    text: widget.review.note,
  );

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    if (section == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Cuộn tới một mục hoặc chọn mục ở bên trái để chấm.'),
      );
    }

    final status = widget.review.status;
    return Material(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(status.icon, size: 18, color: status.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đang chấm: ${section.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<ReviewStatus>(
              showSelectedIcon: false,
              segments: [
                for (final value in ReviewStatus.values)
                  ButtonSegment(
                    value: value,
                    label: Text(value.label),
                    icon: Icon(value.icon),
                  ),
              ],
              selected: {status},
              onSelectionChanged: widget.readOnly
                  ? null
                  : (selection) {
                      widget.onReviewChanged(widget.review.copyWith(status: selection.first));
                    },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              readOnly: widget.readOnly,
              decoration: InputDecoration(
                labelText: widget.readOnly ? 'Ghi chú của bản này' : 'Thêm ghi chú cho mục này',
                hintText: widget.readOnly ? null : 'Nội dung hiện ở lề phải, cạnh mục đang chọn',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              minLines: 1,
              maxLines: 3,
              onChanged: widget.readOnly
                  ? null
                  : (value) => widget.onReviewChanged(widget.review.copyWith(note: value)),
            ),
          ],
        ),
      ),
    );
  }
}
