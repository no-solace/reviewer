import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/section_review.dart';

/// Persists per-section pass/fail marks and notes to a JSON file in the
/// app's own data directory (not next to the reviewed document, so it never
/// touches a student's file or fails on a read-only/network folder), keyed
/// by the document's absolute path.
class ReviewStore {
  Future<Map<String, SectionReview>> load(String documentPath) async {
    final file = await _fileFor(documentPath);
    if (!await file.exists()) return {};

    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final sections = json['sections'] as Map<String, dynamic>? ?? {};
    return sections.map(
      (id, value) => MapEntry(id, SectionReview.fromJson(value as Map<String, dynamic>)),
    );
  }

  Future<void> save(String documentPath, Map<String, SectionReview> reviews) async {
    final file = await _fileFor(documentPath);
    await file.create(recursive: true);
    final json = {'sections': reviews.map((id, review) => MapEntry(id, review.toJson()))};
    await file.writeAsString(jsonEncode(json));
  }

  Future<File> _fileFor(String documentPath) async {
    final appSupportDir = await getApplicationSupportDirectory();
    final sanitized = documentPath.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return File('${appSupportDir.path}/reviews/$sanitized.json');
  }
}
