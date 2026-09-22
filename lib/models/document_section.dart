/// A single node in a document's structural outline (a heading/section).
class DocumentSection {
  const DocumentSection({
    required this.id,
    required this.title,
    required this.level,
    this.pageNumber,
    this.paragraphIndex,
    this.contentEndPageNumber,
    this.contentEndParagraphIndex,
    this.children = const [],
  });

  /// Stable position-based key (e.g. "0", "0.1", "0.2", "1"), assigned in
  /// document order when the outline is built. Used to key review marks.
  final String id;

  /// Heading text.
  final String title;

  /// 1-based depth in the outline (1 = top-level heading).
  final int level;

  /// Destination page for PDF sources. Null for DOCX sources.
  final int? pageNumber;

  /// Index of the paragraph the heading starts at, for DOCX sources.
  /// Null for PDF sources.
  final int? paragraphIndex;

  /// Exclusive upper bound (page number) of this section's own content,
  /// i.e. the page the next heading (of any level) starts at, or one past
  /// the last page if this is the final heading. PDF sources only.
  final int? contentEndPageNumber;

  /// Exclusive upper bound (paragraph index) of this section's own content,
  /// i.e. the paragraph the next heading (of any level) starts at, or the
  /// total paragraph count if this is the final heading. DOCX sources only.
  final int? contentEndParagraphIndex;

  final List<DocumentSection> children;
}

/// The result of analyzing a document's structure.
class DocumentOutline {
  const DocumentOutline({required this.sections, this.warning});

  final List<DocumentSection> sections;

  /// Set when the structure could not be fully determined, e.g. a PDF
  /// with no embedded bookmarks/table of contents.
  final String? warning;
}
