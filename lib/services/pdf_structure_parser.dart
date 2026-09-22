import 'package:pdfrx/pdfrx.dart';

import '../models/document_section.dart';
import 'document_structure_parser.dart';

/// Derives an outline from a PDF's embedded bookmarks/table of contents.
/// Falls back to a flat per-page list when the PDF has no bookmarks (common
/// for scans or documents not exported with Word's Heading styles).
class PdfStructureParser implements DocumentStructureParser {
  @override
  Future<DocumentOutline> parse(String filePath) async {
    final document = await PdfDocument.openFile(filePath);
    try {
      final pageCount = document.pages.length;
      final outline = await document.loadOutline();
      if (outline.isEmpty) {
        return DocumentOutline(
          sections: [
            for (var i = 0; i < pageCount; i++)
              DocumentSection(
                id: '$i',
                title: 'Trang ${i + 1}',
                level: 1,
                pageNumber: i + 1,
                contentEndPageNumber: i + 2,
              ),
          ],
          warning: 'Không tìm thấy mục lục (bookmark) trong PDF này. Hiển thị theo từng trang.',
        );
      }

      final roots = _convertList(outline, null, 1);
      final flat = <_MutableSection>[];
      _flatten(roots, flat);
      for (var i = 0; i < flat.length; i++) {
        final nextPage = i + 1 < flat.length ? flat[i + 1].pageNumber : pageCount + 1;
        final minEnd = flat[i].pageNumber + 1;
        flat[i].contentEndPageNumber = nextPage > minEnd ? nextPage : minEnd;
      }

      return DocumentOutline(sections: roots.map((n) => n.toSection()).toList());
    } finally {
      await document.dispose();
    }
  }

  List<_MutableSection> _convertList(List<PdfOutlineNode> nodes, String? parentId, int level) {
    final result = <_MutableSection>[];
    for (var i = 0; i < nodes.length; i++) {
      final id = parentId == null ? '$i' : '$parentId.$i';
      final node = nodes[i];
      final section = _MutableSection(
        id: id,
        title: node.title,
        level: level,
        pageNumber: node.dest?.pageNumber ?? 1,
      );
      section.children.addAll(_convertList(node.children, id, level + 1));
      result.add(section);
    }
    return result;
  }

  void _flatten(List<_MutableSection> nodes, List<_MutableSection> out) {
    for (final node in nodes) {
      out.add(node);
      _flatten(node.children, out);
    }
  }
}

class _MutableSection {
  _MutableSection({required this.id, required this.title, required this.level, required this.pageNumber});

  final String id;
  final String title;
  final int level;
  final int pageNumber;
  int contentEndPageNumber = 0;
  final List<_MutableSection> children = [];

  DocumentSection toSection() => DocumentSection(
    id: id,
    title: title,
    level: level,
    pageNumber: pageNumber,
    contentEndPageNumber: contentEndPageNumber,
    children: children.map((c) => c.toSection()).toList(),
  );
}
