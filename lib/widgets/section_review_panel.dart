import 'package:flutter/material.dart';

import '../models/document_section.dart';
import '../models/section_content.dart';
import '../models/section_review.dart';

/// Shows the selected section's text/images and lets the user set its
/// pass/fail status and note. Give this widget a `key` derived from the
/// section id so switching sections gets a fresh [TextEditingController].
class SectionReviewPanel extends StatefulWidget {
  const SectionReviewPanel({
    super.key,
    required this.section,
    required this.contentFuture,
    required this.review,
    required this.onReviewChanged,
  });

  final DocumentSection? section;
  final Future<SectionContent>? contentFuture;
  final SectionReview review;
  final ValueChanged<SectionReview> onReviewChanged;

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
      return const Center(child: Text('Chọn một mục ở bên trái để xem nội dung.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(section.title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Expanded(child: _ContentView(contentFuture: widget.contentFuture)),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<ReviewStatus>(
                segments: const [
                  ButtonSegment(
                    value: ReviewStatus.unreviewed,
                    label: Text('Chưa chấm'),
                    icon: Icon(Icons.circle_outlined),
                  ),
                  ButtonSegment(
                    value: ReviewStatus.pass,
                    label: Text('Đạt'),
                    icon: Icon(Icons.check_circle),
                  ),
                  ButtonSegment(
                    value: ReviewStatus.fail,
                    label: Text('Chưa đạt'),
                    icon: Icon(Icons.cancel),
                  ),
                ],
                selected: {widget.review.status},
                onSelectionChanged: (selection) {
                  widget.onReviewChanged(widget.review.copyWith(status: selection.first));
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú',
                  border: OutlineInputBorder(),
                ),
                minLines: 2,
                maxLines: 4,
                onChanged: (value) => widget.onReviewChanged(widget.review.copyWith(note: value)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContentView extends StatelessWidget {
  const _ContentView({required this.contentFuture});

  final Future<SectionContent>? contentFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SectionContent>(
      future: contentFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Không tải được nội dung: ${snapshot.error}'));
        }

        final content = snapshot.data!;
        if (content.paragraphs.isEmpty && content.images.isEmpty) {
          return const Center(
            child: Text('Mục này không có nội dung riêng (có thể chỉ là tiêu đề nhóm).'),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final paragraph in content.paragraphs)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(paragraph)),
            if (content.images.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final image in content.images) _SectionImageTile(image: image)],
              ),
            ],
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _SectionImageTile extends StatelessWidget {
  const _SectionImageTile({required this.image});

  final SectionImage image;

  @override
  Widget build(BuildContext context) {
    final picture = image.bytes != null
        ? Image.memory(image.bytes!, width: 240, fit: BoxFit.contain)
        : RawImage(image: image.uiImage, width: 240, fit: BoxFit.contain);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(4), child: picture),
        if (image.caption != null)
          Text(image.caption!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
