import 'dart:io';

import 'package:plenara/weekly_review.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.parse('2026-08-17T09:00:00');

  test('review explains deterministic keep, defer, drop, and goal decisions',
      () {
    final review = buildWeeklyReviewArtifact({
      'urgent': {
        'id': 'urgent',
        'typeId': 'task',
        'description': 'Urgent',
        'createdAt': '2026-08-16T09:00:00',
        'dueAt': '2026-08-15',
        'status': 'inbox',
      },
      'later': {
        'id': 'later',
        'typeId': 'task',
        'description': 'Later',
        'createdAt': '2026-08-16T09:00:00',
        'status': 'inbox',
      },
      'stale': {
        'id': 'stale',
        'typeId': 'task',
        'description': 'Stale',
        'createdAt': '2026-06-01T09:00:00',
        'status': 'someday',
      },
      'goal': {
        'id': 'goal',
        'typeId': 'goal',
        'title': 'Be present',
      },
    }, now);

    expect(
      {for (final item in review.items) item.recordId: item.decision},
      {
        'goal': ReviewDecision.keep,
        'later': ReviewDecision.defer,
        'stale': ReviewDecision.drop,
        'urgent': ReviewDecision.keep,
      },
    );
    expect(review.items.every((item) => item.evidence.isNotEmpty), isTrue);
  });

  test('edited review persists across relaunch', () {
    final dir = Directory.systemTemp.createTempSync('plenara_weekly_review_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/review.json';
    final original = buildWeeklyReviewArtifact({
      'task': {
        'id': 'task',
        'typeId': 'task',
        'description': 'A task',
        'createdAt': '2026-08-16T09:00:00',
        'status': 'inbox',
      },
    }, now);
    WeeklyReviewStore(path: path).save(original.copyWith(items: [
      original.items.single.copyWith(decision: ReviewDecision.keep),
    ]));

    final restored = WeeklyReviewStore(path: path).active!;

    expect(restored.items.single.decision, ReviewDecision.keep);
  });
}
