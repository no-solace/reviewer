import '../models/document_section.dart';
import '../models/section_content.dart';
import 'docx_section_content_loader.dart';
import 'pdf_section_content_loader.dart';

/// Loads the text/images belonging to one section of an already-analyzed
/// document. One instance is kept open for the lifetime of a review session
/// (see [ReviewScreen]) so repeated section selections don't re-open the
/// underlying file each time.
abstract class SectionContentLoader {
  Future<SectionContent> load(DocumentSection section);

  Future<void> dispose();
}

SectionContentLoader createSectionContentLoader(String filePath) {
  final extension = filePath.split('.').last.toLowerCase();
  switch (extension) {
    case 'docx':
      return DocxSectionContentLoader(filePath);
    case 'pdf':
      return PdfSectionContentLoader(filePath);
    default:
      throw FormatException('Định dạng .$extension không được hỗ trợ.');
  }
}
