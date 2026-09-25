/// One saved review of a document: a copy of the file as it was reviewed,
/// plus the pass/fail marks and notes from that pass.
class ReviewVersion {
  const ReviewVersion({
    required this.id,
    required this.fileName,
    required this.savedPath,
    required this.createdAt,
  });

  final String id;
  final String fileName;

  /// Copy of the document kept with this review, independent of the original.
  final String savedPath;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory ReviewVersion.fromJson(Map<String, dynamic> json, {required String savedPath}) {
    return ReviewVersion(
      id: json['id'] as String,
      fileName: json['fileName'] as String? ?? '',
      savedPath: savedPath,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// A stored version plus the totals shown in the history list.
class StoredReview {
  const StoredReview({
    required this.version,
    required this.number,
    required this.passCount,
    required this.failCount,
    required this.noteCount,
    this.hasAiReview = false,
  });

  final ReviewVersion version;

  /// 1-based order, oldest first. "Bản 1" stays "Bản 1" after newer passes.
  final int number;
  final int passCount;
  final int failCount;
  final int noteCount;

  /// True when this version has a saved AI document check.
  final bool hasAiReview;
}
