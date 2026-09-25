enum AiIssueSeverity { high, medium, low }

enum AiIssueCategory { missingContent, inconsistency, ambiguity, untestable, diagram, other }

/// A standard requirement-document section the AI found absent or too thin.
class AiMissingSection {
  const AiMissingSection({required this.name, required this.reason});

  final String name;
  final String reason;

  Map<String, dynamic> toJson() => {'name': name, 'reason': reason};

  factory AiMissingSection.fromJson(Map<String, dynamic> json) {
    return AiMissingSection(
      name: json['name'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }
}

/// One problem the AI found, optionally anchored to a [DocumentSection.id].
class AiIssue {
  const AiIssue({
    required this.sectionId,
    required this.category,
    required this.severity,
    required this.title,
    required this.evidence,
    required this.suggestion,
  });

  /// Id of the outline section this issue belongs to, or null when it
  /// concerns the document as a whole.
  final String? sectionId;
  final AiIssueCategory category;
  final AiIssueSeverity severity;
  final String title;
  final String evidence;
  final String suggestion;

  Map<String, dynamic> toJson() => {
    'sectionId': sectionId ?? '',
    'category': category.name,
    'severity': severity.name,
    'title': title,
    'evidence': evidence,
    'suggestion': suggestion,
  };

  factory AiIssue.fromJson(Map<String, dynamic> json) {
    final sectionId = json['sectionId'] as String? ?? '';
    return AiIssue(
      sectionId: sectionId.isEmpty ? null : sectionId,
      category: AiIssueCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => AiIssueCategory.other,
      ),
      severity: AiIssueSeverity.values.firstWhere(
        (s) => s.name == json['severity'],
        orElse: () => AiIssueSeverity.medium,
      ),
      title: json['title'] as String? ?? '',
      evidence: json['evidence'] as String? ?? '',
      suggestion: json['suggestion'] as String? ?? '',
    );
  }
}

/// Result of one whole-document AI check.
class DocumentAiReview {
  const DocumentAiReview({
    required this.overallAssessment,
    required this.strengths,
    required this.missingSections,
    required this.issues,
    required this.createdAt,
    required this.model,
    this.templateName,
  });

  final String overallAssessment;
  final List<String> strengths;
  final List<AiMissingSection> missingSections;
  final List<AiIssue> issues;
  final DateTime createdAt;

  /// The model that actually produced the review (may differ from the one
  /// requested if the API fell back to another model).
  final String model;

  /// Name of the structure template the document was checked against, or
  /// null when none was selected.
  final String? templateName;

  Map<String, dynamic> toJson() => {
    'overallAssessment': overallAssessment,
    'strengths': strengths,
    'missingSections': [for (final m in missingSections) m.toJson()],
    'issues': [for (final i in issues) i.toJson()],
    'createdAt': createdAt.toIso8601String(),
    'model': model,
    if (templateName != null) 'templateName': templateName,
  };

  /// Parses both a stored review and the raw structured output from the model
  /// (which has no `createdAt`/`model`; pass them in as fallbacks).
  factory DocumentAiReview.fromJson(
    Map<String, dynamic> json, {
    DateTime? createdAt,
    String? model,
  }) {
    return DocumentAiReview(
      overallAssessment: json['overallAssessment'] as String? ?? '',
      strengths: [for (final s in json['strengths'] as List? ?? const []) s as String],
      missingSections: [
        for (final m in json['missingSections'] as List? ?? const [])
          AiMissingSection.fromJson(m as Map<String, dynamic>),
      ],
      issues: [
        for (final i in json['issues'] as List? ?? const [])
          AiIssue.fromJson(i as Map<String, dynamic>),
      ],
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? createdAt ?? DateTime.now(),
      model: json['model'] as String? ?? model ?? '',
      templateName: json['templateName'] as String?,
    );
  }
}
