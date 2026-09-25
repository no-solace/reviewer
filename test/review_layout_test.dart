import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reviewer/models/document_section.dart';
import 'package:reviewer/models/section_content.dart';
import 'package:reviewer/models/section_review.dart';
import 'package:reviewer/widgets/document_view.dart';
import 'package:reviewer/widgets/outline_tree.dart';

void main() {
  testWidgets('sidebar shows unreviewed, pass, and fail counts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OutlineTree(
            sections: [
              DocumentSection(
                id: '0',
                title: 'Parent',
                level: 1,
                children: [
                  const DocumentSection(id: '0.0', title: 'Passed child', level: 2),
                  const DocumentSection(id: '0.1', title: 'Failed child', level: 2),
                ],
              ),
            ],
            reviewState: const {
              '0.0': SectionReview(status: ReviewStatus.pass),
              '0.1': SectionReview(status: ReviewStatus.fail),
            },
          ),
        ),
      ),
    );

    expect(find.text('Chưa chấm'), findsOneWidget);
    expect(find.text('Đạt'), findsOneWidget);
    expect(find.text('Chưa đạt'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-count-unreviewed')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-count-pass')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-count-fail')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('review-count-unreviewed'))).data,
      '1',
    );
    expect(tester.widget<Text>(find.byKey(const ValueKey('review-count-pass'))).data, '1');
    expect(tester.widget<Text>(find.byKey(const ValueKey('review-count-fail'))).data, '1');
    expect(find.text('Parent'), findsOneWidget);
    expect(find.text('Passed child'), findsOneWidget);
  });

  testWidgets('document view scrolls every section in one page', (tester) async {
    final cache = <String, Future<SectionContent>>{};
    Future<SectionContent> load(DocumentSection section) {
      return cache.putIfAbsent(
        section.id,
        () async => SectionContent(
          pieces: [
            ContentPiece.text('Body ${section.title}'),
            if (section.id == '1')
              const ContentPiece.table([
                ['ID', 'Use Case'],
                ['01', 'Generate Slide'],
              ]),
          ],
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentView(
            sections: const [
              DocumentSection(id: '0', title: '2.2.1 Diagram(s)', level: 3),
              DocumentSection(id: '1', title: '2.2.2 Descriptions', level: 3),
            ],
            selectedId: '1',
            reviews: const {'1': SectionReview(note: 'Thiếu mô tả ngoại lệ')},
            loadContent: load,
            onSectionFocused: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2.2.1 Diagram(s)'), findsOneWidget);
    expect(find.text('2.2.2 Descriptions'), findsOneWidget);
    expect(find.text('Body 2.2.1 Diagram(s)'), findsOneWidget);
    expect(find.text('Body 2.2.2 Descriptions'), findsOneWidget);
    expect(find.text('Generate Slide'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Thiếu mô tả ngoại lệ'), findsOneWidget);
    expect(find.text('Ghi chú'), findsOneWidget);
  });
}
