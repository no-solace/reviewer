import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../models/document_section.dart';
import '../models/section_content.dart';
import '../models/section_review.dart';
import 'review_status.dart';

/// Continuous, Word-like reading view. Sidebar selection scrolls to a heading,
/// and scrolling updates which section the review bar applies to.
class DocumentView extends StatefulWidget {
  const DocumentView({
    super.key,
    required this.sections,
    required this.selectedId,
    required this.reviews,
    required this.loadContent,
    required this.onSectionFocused,
    this.scrollRequest,
  });

  final List<DocumentSection> sections;
  final String? selectedId;
  final Map<String, SectionReview> reviews;
  final Future<SectionContent> Function(DocumentSection section) loadContent;
  final ValueChanged<DocumentSection> onSectionFocused;

  /// Set to a section id to jump there without rebuilding this view.
  final ValueNotifier<String?>? scrollRequest;

  @override
  State<DocumentView> createState() => _DocumentViewState();
}

class _DocumentViewState extends State<DocumentView> {
  static const _minZoom = 0.75;
  static const _maxZoom = 2.0;
  static const _noteGutter = 248.0;

  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  final ScrollController _horizontalController = ScrollController();

  double _zoom = 1;
  String? _reportedId;
  bool _programmaticScroll = false;
  Timer? _focusTimer;
  DocumentSection? _pendingFocus;
  late final ValueNotifier<String?> _highlight;

  @override
  void initState() {
    super.initState();
    _highlight = ValueNotifier(widget.selectedId);
    _reportedId = widget.selectedId;
    widget.scrollRequest?.addListener(_onScrollRequest);
    _itemPositionsListener.itemPositions.addListener(_onPositions);
  }

  @override
  void didUpdateWidget(covariant DocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scrollRequest != oldWidget.scrollRequest) {
      oldWidget.scrollRequest?.removeListener(_onScrollRequest);
      widget.scrollRequest?.addListener(_onScrollRequest);
    }
    final id = widget.selectedId;
    if (id != null && id != oldWidget.selectedId && id != _reportedId) {
      _scrollTo(id);
    }
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    widget.scrollRequest?.removeListener(_onScrollRequest);
    _itemPositionsListener.itemPositions.removeListener(_onPositions);
    _horizontalController.dispose();
    _highlight.dispose();
    super.dispose();
  }

  void _onScrollRequest() {
    final id = widget.scrollRequest?.value;
    if (id == null) return;
    _scrollTo(id);
  }

  void _onPositions() {
    if (_programmaticScroll || widget.sections.isEmpty) return;
    final positions = _itemPositionsListener.itemPositions.value;
    final visible = positions.where(
      (position) => position.itemTrailingEdge > 0.12 && position.itemLeadingEdge < 0.85,
    );
    if (visible.isEmpty) return;

    final top = visible.reduce(
      (a, b) => a.itemLeadingEdge < b.itemLeadingEdge ? a : b,
    );
    if (top.index < 0 || top.index >= widget.sections.length) return;
    final section = widget.sections[top.index];
    if (section.id == _reportedId) return;

    _reportedId = section.id;
    _highlight.value = section.id;
    _pendingFocus = section;
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 120), () {
      final pending = _pendingFocus;
      if (!mounted || pending == null || pending.id != _reportedId) return;
      widget.onSectionFocused(pending);
    });
  }

  void _scrollTo(String id, {bool retry = true}) {
    final index = widget.sections.indexWhere((section) => section.id == id);
    if (index < 0) return;
    _reportedId = id;
    _highlight.value = id;
    if (!_itemScrollController.isAttached) {
      if (!retry) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollTo(id, retry: false);
      });
      return;
    }
    _programmaticScroll = true;
    _itemScrollController.jumpTo(index: index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _programmaticScroll = false;
    });
  }

  void _setZoom(double zoom) {
    final next = zoom.clamp(_minZoom, _maxZoom);
    setState(() => _zoom = next);
    if (next <= 1 && _horizontalController.hasClients) {
      _horizontalController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE7E6E6),
      child: Column(
        children: [
          _ZoomBar(zoom: _zoom, minZoom: _minZoom, maxZoom: _maxZoom, onZoom: _setZoom),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final baseWidth = math.min(
                  780.0,
                  math.max(280.0, constraints.maxWidth - _noteGutter - 36),
                );
                final pageWidth = baseWidth * _zoom;
                final rowWidth = pageWidth + _noteGutter;
                final page = SizedBox(
                  width: rowWidth,
                  height: constraints.maxHeight,
                  child: ScrollablePositionedList.builder(
                    itemScrollController: _itemScrollController,
                    itemPositionsListener: _itemPositionsListener,
                    itemCount: widget.sections.length,
                    minCacheExtent: 4000.0,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    itemBuilder: (context, index) {
                      final section = widget.sections[index];
                      return RepaintBoundary(
                        child: _SectionBlock(
                          section: section,
                          highlight: _highlight,
                          review: widget.reviews[section.id] ?? const SectionReview(),
                          zoom: _zoom,
                          pageWidth: pageWidth,
                          contentWidth: pageWidth - 72,
                          contentFuture: widget.loadContent(section),
                          onSelect: () {
                            _reportedId = section.id;
                            _highlight.value = section.id;
                            widget.onSectionFocused(section);
                          },
                        ),
                      );
                    },
                  ),
                );

                if (rowWidth + 24 <= constraints.maxWidth) {
                  return Center(child: page);
                }

                return Scrollbar(
                  controller: _horizontalController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: rowWidth + 24,
                      height: constraints.maxHeight,
                      child: Center(child: page),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomBar extends StatelessWidget {
  const _ZoomBar({
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.onZoom,
  });

  final double zoom;
  final double minZoom;
  final double maxZoom;
  final ValueChanged<double> onZoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: const Color(0xFFF8F8F8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            const Icon(Icons.zoom_out, size: 18),
            IconButton(
              tooltip: 'Thu nhỏ',
              onPressed: zoom <= minZoom ? null : () => onZoom(zoom - 0.25),
              icon: const Icon(Icons.remove),
            ),
            TextButton(
              onPressed: () => onZoom(1),
              child: Text('${(zoom * 100).round()}%'),
            ),
            IconButton(
              tooltip: 'Phóng to',
              onPressed: zoom >= maxZoom ? null : () => onZoom(zoom + 0.25),
              icon: const Icon(Icons.add),
            ),
            const Icon(Icons.zoom_in, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nhấp đúp vào hình để phóng to và kiểm tra',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.section,
    required this.highlight,
    required this.review,
    required this.zoom,
    required this.pageWidth,
    required this.contentWidth,
    required this.contentFuture,
    required this.onSelect,
  });

  final DocumentSection section;
  final ValueListenable<String?> highlight;
  final SectionReview review;
  final double zoom;
  final double pageWidth;
  final double contentWidth;
  final Future<SectionContent> contentFuture;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final headingSize = switch (section.level) {
      1 => 26.0,
      2 => 22.0,
      3 => 18.0,
      _ => 16.0,
    };

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 36, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Icon(review.status.icon, size: 16, color: review.status.color),
              ),
              Expanded(
                child: Text(
                  section.title,
                  style: TextStyle(
                    fontFamily: 'Calibri',
                    fontSize: headingSize * zoom,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    color: const Color(0xFF2E75B6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<SectionContent>(
            future: contentFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              if (snapshot.hasError) {
                return Text('Không tải được nội dung: ${snapshot.error}');
              }
              final pieces = snapshot.data?.pieces ?? const <ContentPiece>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final piece in pieces) ...[
                    _PieceView(piece: piece, zoom: zoom, contentWidth: contentWidth),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onSelect,
      behavior: HitTestBehavior.translucent,
      child: ValueListenableBuilder<String?>(
        valueListenable: highlight,
        child: content,
        builder: (context, selectedId, content) {
          final selected = selectedId == section.id;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: pageWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFE8F1FA) : Colors.white,
                    border: Border(
                      left: BorderSide(
                        color: selected ? const Color(0xFF2E75B6) : Colors.transparent,
                        width: 4,
                      ),
                    ),
                  ),
                  child: content,
                ),
              ),
              SizedBox(
                width: _DocumentViewState._noteGutter,
                child: _MarginNote(review: review, selected: selected),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MarginNote extends StatelessWidget {
  const _MarginNote({required this.review, required this.selected});

  final SectionReview review;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final note = review.note.trim();
    if (note.isEmpty) return const SizedBox.shrink();

    final accent = selected ? const Color(0xFF2E75B6) : review.status.color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF0),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: selected ? accent : const Color(0xFFE4D7A8)),
          boxShadow: const [
            BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 1)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: accent, width: 4)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ghi chú',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accent,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: const TextStyle(
                      fontFamily: 'Calibri',
                      fontSize: 13,
                      height: 1.35,
                      color: Color(0xFF3E2723),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PieceView extends StatelessWidget {
  const _PieceView({required this.piece, required this.zoom, required this.contentWidth});

  final ContentPiece piece;
  final double zoom;
  final double contentWidth;

  @override
  Widget build(BuildContext context) {
    final table = piece.table;
    if (table != null) {
      return _WordTable(rows: table, zoom: zoom);
    }
    final image = piece.image;
    if (image != null) {
      return _DocumentImage(image: image, width: contentWidth, zoom: zoom);
    }
    return Text(
      piece.text ?? '',
      style: TextStyle(
        fontFamily: 'Calibri',
        fontSize: 15 * zoom,
        height: 1.4,
        color: const Color(0xFF212121),
      ),
    );
  }
}

class _WordTable extends StatelessWidget {
  const _WordTable({required this.rows, required this.zoom});

  final List<List<String>> rows;
  final double zoom;

  double _columnWidth(int column) {
    var longest = 0;
    for (final row in rows) {
      if (column < row.length && row[column].length > longest) {
        longest = row[column].length;
      }
    }
    return (longest * 7.2 * zoom).clamp(64 * zoom, 340 * zoom);
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final columnCount = rows.first.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(color: const Color(0xFF8FA4B8), width: 0.6),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        columnWidths: {
          for (var column = 0; column < columnCount; column++)
            column: FixedColumnWidth(_columnWidth(column)),
        },
        children: [
          for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
            TableRow(
              decoration: BoxDecoration(
                color: rowIndex == 0
                    ? const Color(0xFF2E75B6)
                    : (rowIndex.isEven ? const Color(0xFFF3F8FC) : Colors.white),
              ),
              children: [
                for (final cell in rows[rowIndex])
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      cell,
                      style: TextStyle(
                        fontFamily: 'Calibri',
                        fontSize: 13 * zoom,
                        height: 1.35,
                        fontWeight: rowIndex == 0 ? FontWeight.w700 : FontWeight.w400,
                        color: rowIndex == 0 ? Colors.white : const Color(0xFF212121),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DocumentImage extends StatelessWidget {
  const _DocumentImage({required this.image, required this.width, required this.zoom});

  final SectionImage image;
  final double width;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final displayWidth = width.clamp(120.0, 2400.0);
    final cacheWidth = (displayWidth * MediaQuery.devicePixelRatioOf(context)).round().clamp(1, 2200);

    final Widget picture = image.bytes != null
        ? Image.memory(
            image.bytes!,
            width: displayWidth,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            cacheWidth: cacheWidth,
          )
        : RawImage(image: image.uiImage, width: displayWidth, fit: BoxFit.contain);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            GestureDetector(
              onDoubleTap: () => _openViewer(context),
              child: picture,
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Material(
                color: Colors.white.withValues(alpha: 0.9),
                shape: const CircleBorder(),
                elevation: 1,
                child: IconButton(
                  tooltip: 'Phóng to',
                  onPressed: () => _openViewer(context),
                  icon: const Icon(Icons.zoom_in),
                ),
              ),
            ),
          ],
        ),
        if (image.caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              image.caption!,
              style: TextStyle(fontFamily: 'Calibri', fontSize: 12 * zoom, color: const Color(0xFF616161)),
            ),
          ),
      ],
    );
  }

  void _openViewer(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _ImageViewer(image: image),
    );
  }
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.image});

  final SectionImage image;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  final TransformationController _controller = TransformationController();
  final GlobalKey _viewportKey = GlobalKey();
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
    _loadSize();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransform);
    _controller.dispose();
    super.dispose();
  }

  void _onTransform() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSize() async {
    final rendered = widget.image.uiImage;
    Size? size;
    if (rendered != null) {
      size = Size(rendered.width.toDouble(), rendered.height.toDouble());
    } else if (widget.image.bytes != null) {
      final codec = await ui.instantiateImageCodec(widget.image.bytes!);
      final frame = await codec.getNextFrame();
      size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
      codec.dispose();
    }
    if (!mounted || size == null) return;
    setState(() => _imageSize = size);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  void _fit() {
    final imageSize = _imageSize;
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageSize == null || box == null || !box.hasSize) return;
    final fit = math.min(box.size.width / imageSize.width, box.size.height / imageSize.height);
    _applyScale(fit.clamp(0.05, 1));
  }

  void _zoomBy(double factor) {
    final next = (_controller.value.getMaxScaleOnAxis() * factor).clamp(0.05, 8.0);
    _applyScale(next);
  }

  void _applyScale(double scale) {
    final imageSize = _imageSize;
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageSize == null || box == null || !box.hasSize) {
      _controller.value = Matrix4.identity()..scaleByDouble(scale, scale, 1, 1);
      return;
    }
    final dx = (box.size.width - imageSize.width * scale) / 2;
    final dy = (box.size.height - imageSize.height * scale) / 2;
    _controller.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_controller.value.getMaxScaleOnAxis() * 100).round();
    final picture = widget.image.bytes != null
        ? Image.memory(widget.image.bytes!)
        : RawImage(image: widget.image.uiImage);

    return Dialog.fullscreen(
      backgroundColor: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  _zoomBy(event.scrollDelta.dy > 0 ? 0.9 : 1.1);
                }
              },
              child: SizedBox.expand(
                key: _viewportKey,
                child: InteractiveViewer(
                  transformationController: _controller,
                  constrained: false,
                  minScale: 0.05,
                  maxScale: 8,
                  boundaryMargin: const EdgeInsets.all(240),
                  child: picture,
                ),
              ),
            ),
          ),
          Material(
            color: const Color(0xFF2A2A2A),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Thu nhỏ',
                    color: Colors.white,
                    onPressed: () => _zoomBy(1 / 1.25),
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$percent%', style: const TextStyle(color: Colors.white)),
                  IconButton(
                    tooltip: 'Phóng to',
                    color: Colors.white,
                    onPressed: () => _zoomBy(1.25),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    tooltip: 'Vừa khung',
                    color: Colors.white,
                    onPressed: _fit,
                    icon: const Icon(Icons.fit_screen),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Đóng',
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
