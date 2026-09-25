import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reviewer/models/section_review.dart';
import 'package:reviewer/services/review_store.dart';

void main() {
  test('each review pass keeps its own document copy, marks, and notes', () async {
    final root = await Directory.systemTemp.createTemp('reviewer_store');
    addTearDown(() => root.delete(recursive: true));
    final store = ReviewStore(root: root);

    final source = File('${root.path}/Report.docx');
    await source.writeAsString('ban 1');

    final first = await store.startNewVersion(sourcePath: source.path, fileName: 'Report.docx');
    await store.saveVersion(first, {
      '0': const SectionReview(status: ReviewStatus.fail, note: 'Thiếu biểu đồ'),
      '1': const SectionReview(status: ReviewStatus.pass),
    });

    await source.writeAsString('ban 2 da sua');
    final second = await store.startNewVersion(sourcePath: source.path, fileName: 'Report.docx');

    final versions = await store.listVersions(fileName: 'Report.docx');
    expect(versions.map((item) => item.number), [1, 2]);
    expect(versions[0].failCount, 1);
    expect(versions[0].passCount, 1);
    expect(versions[0].noteCount, 1);
    expect(versions[1].passCount, 0);
    expect(versions[1].noteCount, 0);

    expect(await File(first.savedPath).readAsString(), 'ban 1');
    expect(await File(second.savedPath).readAsString(), 'ban 2 da sua');

    final reloaded = await store.loadVersion(first);
    expect(reloaded['0']?.note, 'Thiếu biểu đồ');
    expect(reloaded['0']?.status, ReviewStatus.fail);
    expect(await store.loadVersion(second), isEmpty);
  });
}
