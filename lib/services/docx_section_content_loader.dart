import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/document_section.dart';
import '../models/section_content.dart';
import 'ooxml_utils.dart';
import 'section_content_loader.dart';

const _rasterImageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'bmp'};

/// Reads the `.docx` archive once and keeps the body blocks and image
/// relationships in memory so repeated [load] calls stay cheap.
class DocxSectionContentLoader implements SectionContentLoader {
  DocxSectionContentLoader(this.filePath);

  final String filePath;

  Future<void>? _loadFuture;
  Archive? _archive;
  List<XmlElement>? _bodyChildren;
  List<int>? _paragraphChildIndexes;
  Map<String, String>? _mediaTargetByRelId;

  Future<void> _ensureLoaded() {
    final pending = _loadFuture;
    if (pending != null) return pending;
    final future = _readArchive();
    _loadFuture = future;
    return future;
  }

  Future<void> _readArchive() async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      _archive = archive;

      final documentEntry = archive.findFile('word/document.xml');
      if (documentEntry == null) {
        throw const FormatException(
          'Không tìm thấy word/document.xml — file .docx có thể bị hỏng.',
        );
      }
      final documentXml = XmlDocument.parse(
        utf8.decode(documentEntry.content as List<int>),
      );
      final body = ooxmlChild(documentXml.rootElement, 'body');
      final children = body?.childElements.toList() ?? const <XmlElement>[];
      _bodyChildren = children;
      _paragraphChildIndexes = [
        for (var i = 0; i < children.length; i++)
          if (children[i].name.local == 'p') i,
      ];

      final relsEntry = archive.findFile('word/_rels/document.xml.rels');
      final relIds = <String, String>{};
      if (relsEntry != null) {
        final relsXml = XmlDocument.parse(utf8.decode(relsEntry.content as List<int>));
        for (final rel in ooxmlChildren(relsXml.rootElement, 'Relationship')) {
          final id = ooxmlAttr(rel, 'Id');
          final target = ooxmlAttr(rel, 'Target');
          if (id != null && target != null) relIds[id] = target;
        }
      }
      _mediaTargetByRelId = relIds;
    } catch (error) {
      _archive = null;
      _loadFuture = null;
      rethrow;
    }
  }

  @override
  Future<SectionContent> load(DocumentSection section) async {
    await _ensureLoaded();

    final start = section.paragraphIndex;
    final end = section.contentEndParagraphIndex;
    if (start == null || end == null) return const SectionContent();

    final children = _bodyChildren!;
    final paragraphChildIndexes = _paragraphChildIndexes!;
    if (start < 0 || start >= paragraphChildIndexes.length) {
      return const SectionContent();
    }

    final startChild = paragraphChildIndexes[start];
    final endChild = end >= 0 && end < paragraphChildIndexes.length
        ? paragraphChildIndexes[end]
        : children.length;

    final pieces = <ContentPiece>[];
    // The heading paragraph's text is the outline title. Images anchored in
    // that same paragraph still belong to this section.
    _appendParagraph(children[startChild], pieces, includeText: false);
    for (var i = startChild + 1; i < endChild; i++) {
      _appendBlock(children[i], pieces);
    }
    return SectionContent(pieces: pieces);
  }

  /// Tables sit between paragraphs in document order. A paragraph-only slice
  /// drops whole sections (use cases, actors, business rules, message lists).
  void _appendBlock(XmlElement block, List<ContentPiece> pieces) {
    switch (block.name.local) {
      case 'p':
        _appendParagraph(block, pieces, includeText: true);
      case 'tbl':
        final grid = _tableGrid(block);
        if (grid != null) pieces.add(ContentPiece.table(grid));
        _appendImages(block, pieces);
      case 'sdt':
        final content = ooxmlChild(block, 'sdtContent');
        if (content == null) return;
        for (final child in content.childElements) {
          _appendBlock(child, pieces);
        }
    }
  }

  /// Walks a paragraph in XML order so a caption and its drawing stay in the
  /// same sequence as in Word.
  void _appendParagraph(
    XmlElement paragraph,
    List<ContentPiece> pieces, {
    required bool includeText,
  }) {
    final buffer = StringBuffer();

    void flushText() {
      final text = buffer.toString().trim();
      buffer.clear();
      if (includeText && text.isNotEmpty) pieces.add(ContentPiece.text(text));
    }

    void walk(XmlElement element) {
      for (final child in element.childElements) {
        switch (child.name.local) {
          case 't':
            buffer.write(child.innerText);
          case 'tab':
            buffer.write('\t');
          case 'br':
          case 'cr':
            buffer.write('\n');
          case 'blip':
            flushText();
            final image = _imageForBlip(child);
            if (image != null) pieces.add(ContentPiece.image(image));
          default:
            walk(child);
        }
      }
    }

    walk(paragraph);
    flushText();
  }

  void _appendImages(XmlElement element, List<ContentPiece> pieces) {
    void walk(XmlElement node) {
      for (final child in node.childElements) {
        if (child.name.local == 'blip') {
          final image = _imageForBlip(child);
          if (image != null) pieces.add(ContentPiece.image(image));
        } else {
          walk(child);
        }
      }
    }

    walk(element);
  }

  String _cellText(XmlElement cell) {
    final parts = <String>[];
    for (final child in cell.childElements) {
      if (child.name.local != 'p') continue;
      final text = ooxmlDescendants(child, 't').map((e) => e.innerText).join().trim();
      if (text.isNotEmpty) parts.add(text);
    }
    return parts.join('\n');
  }

  List<List<String>>? _tableGrid(XmlElement table) {
    final rows = <List<String>>[];
    for (final row in ooxmlChildren(table, 'tr')) {
      final cells = [for (final cell in ooxmlChildren(row, 'tc')) _cellText(cell)];
      if (cells.any((cell) => cell.isNotEmpty)) rows.add(cells);
    }
    if (rows.isEmpty) return null;

    var width = 0;
    for (final row in rows) {
      if (row.length > width) width = row.length;
    }
    return [
      for (final row in rows) [...row, for (var i = row.length; i < width; i++) ''],
    ];
  }

  SectionImage? _imageForBlip(XmlElement blip) {
    final archive = _archive;
    final relIds = _mediaTargetByRelId;
    if (archive == null || relIds == null) return null;

    final relId = ooxmlAttr(blip, 'embed');
    final target = relId == null ? null : relIds[relId];
    if (target == null) return null;

    final extension = target.split('.').last.toLowerCase();
    if (!_rasterImageExtensions.contains(extension)) return null;

    final path = target.startsWith('/') ? target.substring(1) : 'word/$target';
    final bytes = archive.findFile(path)?.content;
    if (bytes == null) return null;
    return SectionImage.bytes(Uint8List.fromList(bytes));
  }

  @override
  Future<void> dispose() async {}
}
