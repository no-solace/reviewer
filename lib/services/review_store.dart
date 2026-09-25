import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/review_version.dart';
import '../models/section_review.dart';

/// Saves each review pass in the app's own data directory: a copy of the
/// document plus its marks and notes. The original file is never modified.
class ReviewStore {
  ReviewStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;

  /// Stable folder name for every revision of the same file name.
  static String documentKeyFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot <= 0 ? fileName : fileName.substring(0, dot);
    final extension = dot <= 0 ? '' : fileName.substring(dot + 1);
    final normalized = '${stem}_$extension'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final trimmed = normalized.replaceAll(RegExp(r'^_+|_+$'), '');
    return trimmed.isEmpty ? 'document' : trimmed;
  }

  Future<List<StoredReview>> listVersions({
    required String fileName,
    String? legacySourcePath,
  }) async {
    final root = await _root();
    final folder = Directory(_join(root.path, documentKeyFor(fileName)));
    final indexFile = File(_join(folder.path, 'index.json'));

    if (!await indexFile.exists() && legacySourcePath != null) {
      await _importLegacy(fileName: fileName, sourcePath: legacySourcePath, folder: folder);
    }
    if (!await indexFile.exists()) return [];

    final index = jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>;
    final entries = (index['versions'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final stored = <StoredReview>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final id = entry['id'] as String;
      final extension = entry['extension'] as String? ?? 'docx';
      final savedPath = _documentPath(folder.path, id, extension);
      final version = ReviewVersion.fromJson(entry, savedPath: savedPath);
      final reviews = await _readReviews(File(_reviewPath(folder.path, id)));
      stored.add(
        StoredReview(
          version: version,
          number: i + 1,
          passCount: reviews.values.where((review) => review.status == ReviewStatus.pass).length,
          failCount: reviews.values.where((review) => review.status == ReviewStatus.fail).length,
          noteCount: reviews.values.where((review) => review.note.trim().isNotEmpty).length,
        ),
      );
    }
    return stored;
  }

  /// Copies [sourcePath] and starts an empty review. Older versions stay put.
  Future<ReviewVersion> startNewVersion({
    required String sourcePath,
    required String fileName,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FormatException('Không tìm thấy file để lưu bản review.');
    }

    final root = await _root();
    final folder = Directory(_join(root.path, documentKeyFor(fileName)));
    final indexFile = File(_join(folder.path, 'index.json'));
    final existing = await indexFile.exists()
        ? jsonDecode(await indexFile.readAsString()) as Map<String, dynamic>
        : <String, dynamic>{'fileName': fileName, 'versions': <dynamic>[]};
    final versions = (existing['versions'] as List<dynamic>? ?? []).toList();

    final id = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final dot = fileName.lastIndexOf('.');
    final extension = dot <= 0 ? 'bin' : fileName.substring(dot + 1).toLowerCase();
    final saved = File(_documentPath(folder.path, id, extension));
    await saved.parent.create(recursive: true);
    await source.copy(saved.path);
    await File(_reviewPath(folder.path, id)).writeAsString(jsonEncode({'sections': <String, dynamic>{}}));

    final createdAt = DateTime.now().toUtc();
    versions.add({
      'id': id,
      'fileName': fileName,
      'extension': extension,
      'createdAt': createdAt.toIso8601String(),
    });
    existing['fileName'] = fileName;
    existing['versions'] = versions;
    await indexFile.create(recursive: true);
    await indexFile.writeAsString(jsonEncode(existing));

    return ReviewVersion(id: id, fileName: fileName, savedPath: saved.path, createdAt: createdAt);
  }

  Future<Map<String, SectionReview>> loadVersion(ReviewVersion version) async {
    final root = await _root();
    final folder = _join(root.path, documentKeyFor(version.fileName));
    return _readReviews(File(_reviewPath(folder, version.id)));
  }

  Future<void> saveVersion(ReviewVersion version, Map<String, SectionReview> reviews) async {
    final root = await _root();
    final folder = _join(root.path, documentKeyFor(version.fileName));
    final file = File(_reviewPath(folder, version.id));
    await file.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'sections': reviews.map((id, review) => MapEntry(id, review.toJson()))}),
    );
  }

  Future<void> _importLegacy({
    required String fileName,
    required String sourcePath,
    required Directory folder,
  }) async {
    final legacy = File(_join((await _root()).path, _legacyName(sourcePath)));
    if (!await legacy.exists() || !await File(sourcePath).exists()) return;

    final version = await startNewVersion(sourcePath: sourcePath, fileName: fileName);
    try {
      final json = jsonDecode(await legacy.readAsString()) as Map<String, dynamic>;
      final sections = json['sections'] as Map<String, dynamic>? ?? {};
      final reviews = sections.map(
        (id, value) => MapEntry(id, SectionReview.fromJson(value as Map<String, dynamic>)),
      );
      await saveVersion(version, reviews);
    } catch (_) {
      // Keep the snapshot even if the old marks file cannot be read.
    }
  }

  Future<Map<String, SectionReview>> _readReviews(File file) async {
    if (!await file.exists()) return {};
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final sections = json['sections'] as Map<String, dynamic>? ?? {};
    return sections.map(
      (id, value) => MapEntry(id, SectionReview.fromJson(value as Map<String, dynamic>)),
    );
  }

  String _legacyName(String documentPath) {
    return '${documentPath.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.json';
  }

  String _documentPath(String folder, String id, String extension) {
    return _join(_join(_join(folder, 'versions'), id), 'document.$extension');
  }

  String _reviewPath(String folder, String id) {
    return _join(_join(_join(folder, 'versions'), id), 'review.json');
  }

  Future<Directory> _root() async {
    final override = _rootOverride;
    if (override != null) return override;
    final support = await getApplicationSupportDirectory();
    return Directory(_join(support.path, 'reviews'));
  }

  String _join(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) return '$parent$child';
    return '$parent${Platform.pathSeparator}$child';
  }
}
