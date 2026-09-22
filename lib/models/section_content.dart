import 'dart:typed_data';
import 'dart:ui' as ui;

/// The text and images belonging directly to one [DocumentSection] (not its
/// subsections).
class SectionContent {
  const SectionContent({required this.paragraphs, required this.images});

  final List<String> paragraphs;
  final List<SectionImage> images;
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
