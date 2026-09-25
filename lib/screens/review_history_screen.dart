import 'package:flutter/material.dart';

import '../models/review_version.dart';
import '../models/structure_template.dart';
import '../services/review_store.dart';
import 'review_screen.dart';

/// Lets the user start a review of the file they just picked, or open an
/// older saved pass (document copy, marks, and notes) for reference.
class ReviewHistoryScreen extends StatefulWidget {
  const ReviewHistoryScreen({
    super.key,
    required this.fileName,
    required this.sourcePath,
    this.store,
    this.template,
  });

  final String fileName;
  final String sourcePath;
  final ReviewStore? store;
  final StructureTemplate? template;

  @override
  State<ReviewHistoryScreen> createState() => _ReviewHistoryScreenState();
}

class _ReviewHistoryScreenState extends State<ReviewHistoryScreen> {
  late final ReviewStore _store = widget.store ?? ReviewStore();
  late Future<List<StoredReview>> _versionsFuture = _load();

  Future<List<StoredReview>> _load() {
    return _store.listVersions(fileName: widget.fileName, legacySourcePath: widget.sourcePath);
  }

  void _reload() {
    setState(() => _versionsFuture = _load());
  }

  Future<void> _open(StoredReview item, {required bool readOnly}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReviewScreen(
          version: item.version,
          versionNumber: item.number,
          sourcePath: widget.sourcePath,
          readOnly: readOnly,
          store: _store,
          template: widget.template,
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _startNew(int nextNumber) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final version = await _store.startNewVersion(
        sourcePath: widget.sourcePath,
        fileName: widget.fileName,
      );
      if (!mounted) return;
      navigator.pop();
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (context) => ReviewScreen(
            version: version,
            versionNumber: nextNumber,
            sourcePath: widget.sourcePath,
            store: _store,
            template: widget.template,
          ),
        ),
      );
      if (mounted) _reload();
    } catch (error) {
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('Không lưu được bản review: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.fileName)),
      body: FutureBuilder<List<StoredReview>>(
        future: _versionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Không đọc được các bản review: ${snapshot.error}'));
          }

          final versions = snapshot.data ?? const <StoredReview>[];
          final newestFirst = versions.reversed.toList();
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Các bản review', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Mỗi bản giữ lại đúng file đã chấm, cùng ghi chú và đánh giá. '
                'Xem bản cũ để rút kinh nghiệm, hoặc review bản mới khi tài liệu đã được sửa.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => _startNew(versions.length + 1),
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Review bản mới'),
                ),
              ),
              const SizedBox(height: 16),
              for (final item in newestFirst)
                _VersionCard(
                  item: item,
                  isLatest: item.number == versions.length,
                  onOpen: () => _open(item, readOnly: item.number != versions.length),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.item, required this.isLatest, required this.onOpen});

  final StoredReview item;
  final bool isLatest;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final created = item.version.createdAt.toLocal();
    final date =
        '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year} '
        '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bản ${item.number}', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(date, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    '${item.passCount} đạt · ${item.failCount} chưa đạt · ${item.noteCount} ghi chú${item.hasAiReview ? ' · AI' : ''}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            isLatest
                ? FilledButton(onPressed: onOpen, child: const Text('Tiếp tục'))
                : OutlinedButton(onPressed: onOpen, child: const Text('Xem lại')),
          ],
        ),
      ),
    );
  }
}
