import 'package:flutter/material.dart';

import '../models/document_section.dart';
import '../models/section_review.dart';
import 'review_status.dart';

/// Heading tree with a pinned summary of unreviewed, passed, and failed sections.
class OutlineTree extends StatefulWidget {
  const OutlineTree({
    super.key,
    required this.sections,
    this.selectedId,
    this.reviewState = const {},
    this.onSectionSelected,
  });

  final List<DocumentSection> sections;
  final String? selectedId;
  final Map<String, SectionReview> reviewState;
  final ValueChanged<DocumentSection>? onSectionSelected;

  @override
  State<OutlineTree> createState() => _OutlineTreeState();
}

class _Counts {
  int unreviewed = 0;
  int pass = 0;
  int fail = 0;

  int get total => unreviewed + pass + fail;

  void add(ReviewStatus status) {
    switch (status) {
      case ReviewStatus.unreviewed:
        unreviewed++;
      case ReviewStatus.pass:
        pass++;
      case ReviewStatus.fail:
        fail++;
    }
  }

  void include(_Counts other) {
    unreviewed += other.unreviewed;
    pass += other.pass;
    fail += other.fail;
  }
}

class _OutlineTreeState extends State<OutlineTree> {
  final Set<String> _expandedIds = {};
  bool _expandedInitialized = false;
  ReviewStatus? _statusFilter;

  @override
  void didUpdateWidget(covariant OutlineTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sections != widget.sections) {
      _expandedIds.clear();
      _expandedInitialized = false;
      _statusFilter = null;
    }
  }

  void _initExpanded() {
    if (_expandedInitialized) return;
    _expandedInitialized = true;
    for (final section in widget.sections) {
      if (section.level == 1) _expandedIds.add(section.id);
    }
  }

  ReviewStatus _statusOf(DocumentSection section) {
    return widget.reviewState[section.id]?.status ?? ReviewStatus.unreviewed;
  }

  _Counts _subtreeCounts(DocumentSection section) {
    final counts = _Counts()..add(_statusOf(section));
    for (final child in section.children) {
      counts.include(_subtreeCounts(child));
    }
    return counts;
  }

  _Counts _descendantCounts(DocumentSection section) {
    final counts = _Counts();
    for (final child in section.children) {
      counts.include(_subtreeCounts(child));
    }
    return counts;
  }

  bool _containsStatus(DocumentSection section, ReviewStatus status) {
    if (_statusOf(section) == status) return true;
    for (final child in section.children) {
      if (_containsStatus(child, status)) return true;
    }
    return false;
  }

  _Counts _totals() {
    final counts = _Counts();
    for (final section in widget.sections) {
      counts.include(_subtreeCounts(section));
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    _initExpanded();
    final totals = _totals();
    final reviewed = totals.pass + totals.fail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryHeader(
          totals: totals,
          reviewed: reviewed,
          filter: _statusFilter,
          onFilterChanged: (status) => setState(() => _statusFilter = status),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [for (final section in widget.sections) _buildTile(section)],
          ),
        ),
      ],
    );
  }

  Widget _buildTile(DocumentSection section) {
    final filter = _statusFilter;
    if (filter != null && !_containsStatus(section, filter)) {
      return const SizedBox.shrink();
    }

    final visibleChildren = [
      for (final child in section.children)
        if (filter == null || _containsStatus(child, filter)) child,
    ];
    final expanded = filter != null
        ? visibleChildren.isNotEmpty
        : _expandedIds.contains(section.id);
    final descendants = section.children.isEmpty ? null : _descendantCounts(section);

    final tile = _SectionTile(
      section: section,
      expanded: expanded,
      selected: section.id == widget.selectedId,
      status: _statusOf(section),
      descendants: descendants,
      onToggleExpand: section.children.isEmpty || filter != null
          ? null
          : () => setState(() {
              expanded ? _expandedIds.remove(section.id) : _expandedIds.add(section.id);
            }),
      onSelect: () => widget.onSectionSelected?.call(section),
    );

    if (visibleChildren.isEmpty || !expanded) return tile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [tile, for (final child in visibleChildren) _buildTile(child)],
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.totals,
    required this.reviewed,
    required this.filter,
    required this.onFilterChanged,
  });

  final _Counts totals;
  final int reviewed;
  final ReviewStatus? filter;
  final ValueChanged<ReviewStatus?> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tiến độ chấm', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _StatButton(
            status: ReviewStatus.unreviewed,
            count: totals.unreviewed,
            selected: filter == ReviewStatus.unreviewed,
            onTap: () => onFilterChanged(
              filter == ReviewStatus.unreviewed ? null : ReviewStatus.unreviewed,
            ),
          ),
          _StatButton(
            status: ReviewStatus.pass,
            count: totals.pass,
            selected: filter == ReviewStatus.pass,
            onTap: () => onFilterChanged(filter == ReviewStatus.pass ? null : ReviewStatus.pass),
          ),
          _StatButton(
            status: ReviewStatus.fail,
            count: totals.fail,
            selected: filter == ReviewStatus.fail,
            onTap: () => onFilterChanged(filter == ReviewStatus.fail ? null : ReviewStatus.fail),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: totals.total == 0 ? 0 : reviewed / totals.total,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            filter == null
                ? '$reviewed/${totals.total} mục đã chấm'
                : 'Đang lọc: ${filter!.label}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _StatButton extends StatelessWidget {
  const _StatButton({
    required this.status,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final ReviewStatus status;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? color.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? color : color.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(status.icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(status.label)),
                Text(
                  '$count',
                  key: ValueKey('review-count-${status.name}'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.expanded,
    required this.selected,
    required this.status,
    required this.descendants,
    required this.onToggleExpand,
    required this.onSelect,
  });

  final DocumentSection section;
  final bool expanded;
  final bool selected;
  final ReviewStatus status;
  final _Counts? descendants;
  final VoidCallback? onToggleExpand;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = section.pageNumber == null ? null : 'Trang ${section.pageNumber}';

    return Material(
      color: selected ? colorScheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: EdgeInsets.only(left: 12.0 * (section.level - 1), top: 2, bottom: 2, right: 8),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: onToggleExpand == null
                    ? null
                    : IconButton(
                        icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 20),
                        onPressed: onToggleExpand,
                        visualDensity: VisualDensity.compact,
                      ),
              ),
              Icon(status.icon, size: 16, color: status.color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(section.title, style: Theme.of(context).textTheme.bodyMedium),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (descendants != null && descendants!.total > 0)
                Tooltip(
                  message:
                      'Trong nhánh: ${descendants!.unreviewed} chưa chấm, ${descendants!.pass} đạt, ${descendants!.fail} chưa đạt',
                  child: _BranchCounts(counts: descendants!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BranchCounts extends StatelessWidget {
  const _BranchCounts({required this.counts});

  final _Counts counts;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CountChip(count: counts.unreviewed, color: ReviewStatus.unreviewed.color),
        _CountChip(count: counts.pass, color: ReviewStatus.pass.color),
        _CountChip(count: counts.fail, color: ReviewStatus.fail.color),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: count == 0 ? Colors.transparent : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: count == 0 ? color.withValues(alpha: 0.35) : color,
        ),
      ),
    );
  }
}
