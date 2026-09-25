import 'package:flutter_test/flutter_test.dart';
import 'package:reviewer/models/document_ai_review.dart';
import 'package:reviewer/models/document_section.dart';

void main() {
  test('parses Claude structured output and round-trips through storage', () {
    final raw = {
      'overallAssessment': 'Tài liệu khá đầy đủ.',
      'strengths': ['Có use case rõ ràng'],
      'missingSections': [
        {'name': 'Yêu cầu phi chức năng', 'reason': 'Không có mục nào.'},
      ],
      'issues': [
        {
          'sectionId': '0.1',
          'category': 'ambiguity',
          'severity': 'high',
          'title': 'Yêu cầu "hệ thống chạy nhanh" không đo được',
          'evidence': '"Hệ thống phải chạy nhanh"',
          'suggestion': 'Nêu thời gian phản hồi cụ thể.',
        },
        {
          'sectionId': '',
          'category': 'unknown-category',
          'severity': 'low',
          'title': 'Lỗi chính tả',
          'evidence': '',
          'suggestion': '',
        },
      ],
    };

    final review = DocumentAiReview.fromJson(raw, createdAt: DateTime.utc(2026, 9, 25), model: 'claude-opus-5');
    expect(review.issues.first.sectionId, '0.1');
    expect(review.issues.first.category, AiIssueCategory.ambiguity);
    expect(review.issues.first.severity, AiIssueSeverity.high);
    expect(review.issues.last.sectionId, isNull);
    expect(review.issues.last.category, AiIssueCategory.other);

    final restored = DocumentAiReview.fromJson(review.toJson());
    expect(restored.model, 'claude-opus-5');
    expect(restored.createdAt, DateTime.utc(2026, 9, 25));
    expect(restored.missingSections.single.name, 'Yêu cầu phi chức năng');
    expect(restored.issues.last.sectionId, isNull);
    expect(restored.sectionGrades, isEmpty);
  });

  test('grades every section and writes each problem into the note', () {
    const sections = [
      DocumentSection(
        id: '0',
        title: 'Giới thiệu',
        level: 1,
        children: [DocumentSection(id: '0.1', title: 'Phạm vi', level: 2)],
      ),
      DocumentSection(id: '1', title: 'Use case', level: 1),
    ];
    final issues = [
      const AiIssue(
        sectionId: '1',
        category: AiIssueCategory.ambiguity,
        severity: AiIssueSeverity.high,
        title: 'Use case không có luồng phụ',
        evidence: 'Bảng use case',
        suggestion: 'Bổ sung ngoại lệ.',
      ),
    ];
    final grades = completeSectionGrades(
      sections: sections,
      provided: const [
        AiSectionGrade(sectionId: '0', status: AiGradeStatus.pass, note: 'Đủ mục đích.'),
        AiSectionGrade(sectionId: '1', status: AiGradeStatus.pass, note: 'Có bảng.'),
      ],
      issues: issues,
    );

    expect(grades.map((grade) => grade.sectionId), ['0', '0.1', '1']);
    expect(grades[0].status, AiGradeStatus.pass);
    expect(grades[1].status, AiGradeStatus.pass);
    expect(grades[2].status, AiGradeStatus.fail);

    expect(
      sectionNoteFromGrade(grades[2], issues),
      'Có bảng.\n- Use case không có luồng phụ — Bổ sung ngoại lệ.',
    );
  });
}
