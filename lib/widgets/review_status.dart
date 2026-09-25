import 'package:flutter/material.dart';

import '../models/section_review.dart';

extension ReviewStatusPresentation on ReviewStatus {
  String get label => switch (this) {
    ReviewStatus.unreviewed => 'Chưa chấm',
    ReviewStatus.pass => 'Đạt',
    ReviewStatus.fail => 'Chưa đạt',
  };

  IconData get icon => switch (this) {
    ReviewStatus.unreviewed => Icons.circle_outlined,
    ReviewStatus.pass => Icons.check_circle,
    ReviewStatus.fail => Icons.cancel,
  };

  Color get color => switch (this) {
    ReviewStatus.unreviewed => const Color(0xFF607D8B),
    ReviewStatus.pass => const Color(0xFF2E7D32),
    ReviewStatus.fail => const Color(0xFFC62828),
  };
}
