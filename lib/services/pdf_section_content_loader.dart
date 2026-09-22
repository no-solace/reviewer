import 'package:pdfrx/pdfrx.dart';

import '../models/document_section.dart';
import '../models/section_content.dart';
import 'section_content_loader.dart';

/// Keeps a single [PdfDocument] open for the lifetime of a review session so
/// selecting sections doesn't reopen the PDF each time.
///
/// `pdfrx` has no API to pull out individual embedded images, so a
/// section's "images" are full-page renders of the pages it spans — see
/// [SectionImage.caption] for the page number shown alongside each one.
class PdfSectionContentLoader implements SectionContentLoader {
  PdfSectionContentLoader(this.filePath);

  final String filePath;
  PdfDocument? _document;

  Future<PdfDocument> _ensureOpen() async {
    return _document ??= await PdfDocument.openFile(filePath);
  }

  @override
  Future<SectionContent> load(DocumentSection section) async {
    final document = await _ensureOpen();

    final start = section.pageNumber;
    final end = section.contentEndPageNumber;
    if (start == null || end == null) {
      return const SectionContent(paragraphs: [], images: []);
    }

    final texts = <String>[];
    final images = <SectionImage>[];

    for (var pageNumber = start; pageNumber < end && pageNumber <= document.pages.length; pageNumber++) {
      final page = document.pages[pageNumber - 1];

      final rawText = await page.loadText();
      final text = rawText?.fullText.trim() ?? '';
      if (text.isNotEmpty) texts.add(text);

      final rendered = await page.render();
      if (rendered != null) {
        final uiImage = await rendered.createImage();
        rendered.dispose();
        images.add(SectionImage.rendered(uiImage, caption: 'Trang $pageNumber'));
      }
    }

    return SectionContent(paragraphs: texts, images: images);
  }

  @override
  Future<void> dispose() async {
    await _document?.dispose();
    _document = null;
  }
}
