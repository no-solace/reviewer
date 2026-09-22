import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/document_section.dart';
import 'document_structure_parser.dart';
import 'ooxml_utils.dart';

/// Derives a heading outline from a `.docx` (OOXML) file by reading the
/// `w:outlineLvl` that Word attaches to heading paragraphs/styles — this is
/// the same signal Word uses to build its own table of contents, so it works
/// regardless of the document's language or renamed styles.
class DocxStructureParser implements DocumentStructureParser {
  @override
  Future<DocumentOutline> parse(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final documentEntry = archive.findFile('word/document.xml');
    if (documentEntry == null) {
      throw const FormatException(
        'Không tìm thấy word/document.xml — file .docx có thể bị hỏng.',
      );
    }
    final documentXml = XmlDocument.parse(
      utf8.decode(documentEntry.content as List<int>),
    );

    final stylesEntry = archive.findFile('word/styles.xml');
    final outlineLevelsByStyle = stylesEntry == null
        ? <String, int>{}
        : _outlineLevelsByStyle(
            XmlDocument.parse(utf8.decode(stylesEntry.content as List<int>)),
          );

    final body = ooxmlChild(documentXml.rootElement, 'body');
    if (body == null) {
      throw const FormatException('Tài liệu .docx không hợp lệ: thiếu <w:body>.');
    }

    final headings = <_HeadingEntry>[];
    var paragraphIndex = 0;
    for (final paragraph in ooxmlChildren(body, 'p')) {
      final level = _headingLevel(paragraph, outlineLevelsByStyle);
      if (level != null) {
        final title = _text(paragraph).trim();
        if (title.isNotEmpty) {
          headings.add(
            _HeadingEntry(title: title, level: level + 1, paragraphIndex: paragraphIndex),
          );
        }
      }
      paragraphIndex++;
    }
    final totalParagraphs = paragraphIndex;

    if (headings.isEmpty) {
      return const DocumentOutline(
        sections: [],
        warning: 'Không tìm thấy heading nào trong tài liệu .docx.',
      );
    }

    for (var i = 0; i < headings.length; i++) {
      headings[i].contentEndParagraphIndex = i + 1 < headings.length
          ? headings[i + 1].paragraphIndex
          : totalParagraphs;
    }

    return DocumentOutline(sections: _buildTree(headings));
  }

  /// Resolves the 0-based outline level of [paragraph], preferring a direct
  /// override on the paragraph itself, then falling back to its style.
  int? _headingLevel(XmlElement paragraph, Map<String, int> outlineLevelsByStyle) {
    final pPr = ooxmlChild(paragraph, 'pPr');
    if (pPr == null) return null;

    final directOutline = ooxmlChild(pPr, 'outlineLvl');
    if (directOutline != null) {
      return int.tryParse(ooxmlAttr(directOutline, 'val') ?? '');
    }

    final styleEl = ooxmlChild(pPr, 'pStyle');
    final styleId = styleEl == null ? null : ooxmlAttr(styleEl, 'val');
    return styleId == null ? null : outlineLevelsByStyle[styleId];
  }

  /// Builds a styleId -> 0-based outline level map from `word/styles.xml`,
  /// resolving `w:basedOn` chains for custom styles derived from a heading.
  Map<String, int> _outlineLevelsByStyle(XmlDocument stylesXml) {
    final directLevel = <String, int>{};
    final basedOn = <String, String>{};

    for (final style in ooxmlChildren(stylesXml.rootElement, 'style')) {
      final id = ooxmlAttr(style, 'styleId');
      if (id == null) continue;

      final pPr = ooxmlChild(style, 'pPr');
      final outlineLvl = pPr == null ? null : ooxmlChild(pPr, 'outlineLvl');
      if (outlineLvl != null) {
        final level = int.tryParse(ooxmlAttr(outlineLvl, 'val') ?? '');
        if (level != null) directLevel[id] = level;
      }

      final basedOnEl = ooxmlChild(style, 'basedOn');
      final basedOnId = basedOnEl == null ? null : ooxmlAttr(basedOnEl, 'val');
      if (basedOnId != null) basedOn[id] = basedOnId;
    }

    int? resolve(String id, Set<String> seen) {
      if (!seen.add(id)) return null; // guard against a cyclic basedOn chain
      return directLevel[id] ?? (basedOn[id] != null ? resolve(basedOn[id]!, seen) : null);
    }

    final resolved = <String, int>{};
    for (final id in {...directLevel.keys, ...basedOn.keys}) {
      final level = resolve(id, <String>{});
      if (level != null) resolved[id] = level;
    }
    return resolved;
  }

  String _text(XmlElement paragraph) {
    return ooxmlDescendants(paragraph, 't').map((e) => e.innerText).join();
  }

  List<DocumentSection> _buildTree(List<_HeadingEntry> entries) {
    final roots = <_MutableSection>[];
    final stack = <_MutableSection>[];

    for (final entry in entries) {
      while (stack.isNotEmpty && stack.last.entry.level >= entry.level) {
        stack.removeLast();
      }
      final parent = stack.isEmpty ? null : stack.last;
      final id = parent == null ? '${roots.length}' : '${parent.id}.${parent.children.length}';
      final node = _MutableSection(entry, id);
      if (parent == null) {
        roots.add(node);
      } else {
        parent.children.add(node);
      }
      stack.add(node);
    }

    return roots.map((n) => n.toSection()).toList();
  }
}

class _HeadingEntry {
  _HeadingEntry({required this.title, required this.level, required this.paragraphIndex});

  final String title;
  final int level;
  final int paragraphIndex;
  int contentEndParagraphIndex = 0;
}

class _MutableSection {
  _MutableSection(this.entry, this.id);

  final _HeadingEntry entry;
  final String id;
  final List<_MutableSection> children = [];

  DocumentSection toSection() => DocumentSection(
    id: id,
    title: entry.title,
    level: entry.level,
    paragraphIndex: entry.paragraphIndex,
    contentEndParagraphIndex: entry.contentEndParagraphIndex,
    children: children.map((c) => c.toSection()).toList(),
  );
}
