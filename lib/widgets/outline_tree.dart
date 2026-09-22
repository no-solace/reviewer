import 'package:flutter/material.dart';

import '../models/document_section.dart';
import '../models/section_review.dart';

/// Renders a document's heading structure as a selectable, expandable tree.
/// Each tile shows a small colored dot for its review status.
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

class _OutlineTreeState extends State<OutlineTree> {
  final Set<String> _expandedIds = {};
  bool _expandedInitialized = false;

  @override
  void didUpdateWidget(covariant OutlineTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sections != widget.sections) {
      _expandedIds.clear();
      _expandedInitialized = false;
    }
  }

  void _initExpanded() {
    if (_expandedInitialized) return;
    _expandedInitialized = true;
    for (final section in widget.sections) {
      if (section.level == 1) _expandedIds.add(section.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    _initExpanded();
    return ListView(
      children: [for (final section in widget.sections) _buildTile(section)],
    );
  }

  Widget _buildTile(DocumentSection section) {
    final expanded = _expandedIds.contains(section.id);
    final tile = _SectionTile(
      section: section,
      expanded: expanded,
      selected: section.id == widget.selectedId,
      status: widget.reviewState[section.id]?.status ?? ReviewStatus.unreviewed,
      onToggleExpand: section.children.isEmpty
          ? null
          : () => setState(() {
              expanded ? _expandedIds.remove(section.id) : _expandedIds.add(section.id);
            }),
      onSelect: () => widget.onSectionSelected?.call(section),
    );

    if (section.children.isEmpty || !expanded) return tile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [tile, for (final child in section.children) _buildTile(child)],
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.expanded,
    required this.selected,
    required this.status,
    required this.onToggleExpand,
    required this.onSelect,
  });

  final DocumentSection section;
  final bool expanded;
  final bool selected;
  final ReviewStatus status;
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
          padding: EdgeInsets.only(left: 16.0 * (section.level - 1), top: 4, bottom: 4, right: 8),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: onToggleExpand == null
                    ? null
                    : IconButton(
                        icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
                        onPressed: onToggleExpand,
                        visualDensity: VisualDensity.compact,
                      ),
              ),
              _StatusDot(status: status),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final ReviewStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      ReviewStatus.pass => (Icons.check_circle, Colors.green),
      ReviewStatus.fail => (Icons.cancel, Colors.red),
      ReviewStatus.unreviewed => (Icons.circle_outlined, Theme.of(context).colorScheme.outline),
    };
    return Icon(icon, size: 16, color: color);
  }
}
