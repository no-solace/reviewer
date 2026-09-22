import '../models/document_section.dart';
import 'document_structure_parser.dart';
import 'docx_structure_parser.dart';
import 'pdf_structure_parser.dart';

/// Picks the right [DocumentStructureParser] for a file based on its
/// extension and runs it.
class DocumentStructureService {
  DocumentStructureService({
    DocumentStructureParser? docxParser,
    DocumentStructureParser? pdfParser,
  }) : _docxParser = docxParser ?? DocxStructureParser(),
       _pdfParser = pdfParser ?? PdfStructureParser();

  final DocumentStructureParser _docxParser;
  final DocumentStructureParser _pdfParser;

  Future<DocumentOutline> analyze(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    switch (extension) {
      case 'docx':
        return _docxParser.parse(filePath);
      case 'pdf':
        return _pdfParser.parse(filePath);
      case 'doc':
        throw const FormatException(
          'Định dạng .doc (Word cũ) chưa được hỗ trợ. Vui lòng lưu lại thành .docx hoặc PDF.',
        );
      default:
        throw FormatException('Định dạng .$extension không được hỗ trợ.');
    }
  }
}
