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

/// Reads the `.docx` archive once and keeps the parsed paragraph list and
/// image relationships in memory so repeated [load] calls (one per section
/// the user clicks) are cheap.
class DocxSectionContentLoader implements SectionContentLoader {
  DocxSectionContentLoader(this.filePath);

  final String filePath;

  Archive? _archive;
  List<XmlElement>? _paragraphs;
  Map<String, String>? _mediaTargetByRelId;

  Future<void> _ensureLoaded() async {
    if (_archive != null) return;

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
    _paragraphs = body == null ? const [] : ooxmlChildren(body, 'p').toList();

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
  }

  @override
  Future<SectionContent> load(DocumentSection section) async {
    await _ensureLoaded();

    final start = section.paragraphIndex;
    final end = section.contentEndParagraphIndex;
    if (start == null || end == null) {
      return const SectionContent(paragraphs: [], images: []);
    }

    final paragraphs = _paragraphs!;
    final archive = _archive!;
    final relIds = _mediaTargetByRelId!;

    final texts = <String>[];
    final images = <SectionImage>[];

    for (var i = start + 1; i < end && i < paragraphs.length; i++) {
      final paragraph = paragraphs[i];

      final text = ooxmlDescendants(paragraph, 't').map((e) => e.innerText).join().trim();
      if (text.isNotEmpty) texts.add(text);

      for (final blip in ooxmlDescendants(paragraph, 'blip')) {
        final relId = ooxmlAttr(blip, 'embed');
        final target = relId == null ? null : relIds[relId];
        if (target == null) continue;

        final extension = target.split('.').last.toLowerCase();
        if (!_rasterImageExtensions.contains(extension)) continue;

        final path = target.startsWith('/') ? target.substring(1) : 'word/$target';
        final entry = archive.findFile(path);
        final bytes = entry?.content;
        if (bytes != null) {
          images.add(SectionImage.bytes(Uint8List.fromList(bytes)));
        }
      }
    }

    return SectionContent(paragraphs: texts, images: images);
  }

  @override
  Future<void> dispose() async {}
}
