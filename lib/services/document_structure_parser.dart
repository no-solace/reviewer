import '../models/document_section.dart';

/// Reads a document from disk and derives its structural outline.
abstract class DocumentStructureParser {
  Future<DocumentOutline> parse(String filePath);
}
