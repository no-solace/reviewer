import 'dart:typed_data';
import 'dart:ui' as ui;

/// The text, tables, and images belonging directly to one [DocumentSection]
/// (not its subsections), in document order.
class SectionContent {
  const SectionContent({this.pieces = const []});

  final List<ContentPiece> pieces;

  List<String> get paragraphs => [
    for (final piece in pieces)
      if (piece.text != null) piece.text!,
  ];

  List<SectionImage> get images => [
    for (final piece in pieces)
      if (piece.image != null) piece.image!,
  ];
}

/// One block of section content, in the order it appears in the file.
class ContentPiece {
  const ContentPiece.text(this.text) : image = null, table = null;

  const ContentPiece.image(this.image) : text = null, table = null;

  const ContentPiece.table(this.table) : text = null, image = null;

  final String? text;
  final SectionImage? image;

  /// Rows of cells. The first row is the header.
  final List<List<String>>? table;
}

/// Either raw image bytes (DOCX embedded images) or an already-decoded
/// image (PDF page renders, which `pdfrx` hands back as `dart:ui.Image`).
class SectionImage {
  const SectionImage.bytes(Uint8List this.bytes) : uiImage = null, caption = null;

  const SectionImage.rendered(ui.Image this.uiImage, {this.caption}) : bytes = null;

  final Uint8List? bytes;
  final ui.Image? uiImage;

  /// Extra context shown under the image, e.g. "Trang 3" for a PDF page
  /// render (since it isn't a true embedded image, unlike DOCX).
  final String? caption;
}
