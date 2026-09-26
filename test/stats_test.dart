import 'package:flutter_test/flutter_test.dart';
import 'package:speakcards/features/stats/stats_service.dart';

int daysAgo(int n, {DateTime? now}) {
  final base = now ?? DateTime.now();
  final d = DateTime(base.year, base.month, base.day)
      .subtract(Duration(days: n));
  return d.millisecondsSinceEpoch + 12 * 60 * 60 * 1000; // midday
}

void main() {
  test('streak counts consecutive days', () {
    final now = DateTime.now();
    expect(StatsService.calcStreak([]), 0);
    expect(StatsService.calcStreak([daysAgo(0, now: now)], now: now), 1);
    expect(
      StatsService.calcStreak(
          [daysAgo(0, now: now), daysAgo(1, now: now), daysAgo(2, now: now)],
          now: now,),
      3,
    );
    // Yesterday only: streak alive at 1.
    expect(StatsService.calcStreak([daysAgo(1, now: now)], now: now), 1);
    // Gap breaks it: today + 2 days ago = 1.
    expect(
      StatsService.calcStreak([daysAgo(0, now: now), daysAgo(2, now: now)],
          now: now,),
      1,
    );
    // Last practice 3 days ago: streak dead.
    expect(StatsService.calcStreak([daysAgo(3, now: now)], now: now), 0);
  });

  test('mastery labels follow bands', () {
    expect(StatsService.masteryLabel(90), 'Strong');
    expect(StatsService.masteryLabel(75), 'Getting there');
    expect(StatsService.masteryLabel(55), 'Needs work');
    expect(StatsService.masteryLabel(20), 'Starting out');
  });

  test('weekly counts bucket last 7 days oldest-first', () {
    final now = DateTime.now();
    final counts = StatsService.weeklyCounts(
      [daysAgo(0, now: now), daysAgo(0, now: now), daysAgo(3, now: now)],
      now: now,
    );
    expect(counts.length, 7);
    expect(counts[6], 2); // today
    expect(counts[3], 1); // 3 days ago
    expect(counts.reduce((a, b) => a + b), 3);
    expect(
      StatsService.weeklyCounts([daysAgo(9, now: now)], now: now),
      List.filled(7, 0),
    );
    expect(StatsService.weeklyLetters(now: now).length, 7);
  });
}
