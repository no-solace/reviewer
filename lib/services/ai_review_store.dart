import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/document_ai_review.dart';

/// Persists the latest AI whole-document review per document, alongside
/// [ReviewStore]'s marks in the app's own data directory, keyed by the
/// document's absolute path.
class AiReviewStore {
  Future<DocumentAiReview?> load(String documentPath) async {
    final file = await _fileFor(documentPath);
    if (!await file.exists()) return null;
    return DocumentAiReview.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<void> save(String documentPath, DocumentAiReview review) async {
    final file = await _fileFor(documentPath);
    await file.create(recursive: true);
    await file.writeAsString(jsonEncode(review.toJson()));
  }

  Future<File> _fileFor(String documentPath) async {
    final appSupportDir = await getApplicationSupportDirectory();
    final sanitized = documentPath.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return File('${appSupportDir.path}/ai_reviews/$sanitized.json');
  }
}
