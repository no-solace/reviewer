enum ReviewStatus { unreviewed, pass, fail }

class SectionReview {
  const SectionReview({this.status = ReviewStatus.unreviewed, this.note = ''});

  final ReviewStatus status;
  final String note;

  SectionReview copyWith({ReviewStatus? status, String? note}) {
    return SectionReview(status: status ?? this.status, note: note ?? this.note);
  }

  Map<String, dynamic> toJson() => {'status': status.name, 'note': note};

  factory SectionReview.fromJson(Map<String, dynamic> json) {
    return SectionReview(
      status: ReviewStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ReviewStatus.unreviewed,
      ),
      note: json['note'] as String? ?? '',
    );
  }
}
