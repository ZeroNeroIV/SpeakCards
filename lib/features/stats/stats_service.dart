/// Pure helpers for the Progress tab. No widgets, fully testable.
class StatsService {
  /// Consecutive days with at least one attempt, ending today or
  /// yesterday (a streak stays alive until a full day is missed).
  static int calcStreak(List<int> stamps, {DateTime? now}) {
    if (stamps.isEmpty) return 0;
    final today = now ?? DateTime.now();
    DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
    final days = stamps
        .map((t) => dayOf(DateTime.fromMillisecondsSinceEpoch(t)))
        .toSet();
    var cursor = dayOf(today);
    if (!days.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static String masteryLabel(double avg) {
    if (avg >= 85) return 'Strong';
    if (avg >= 70) return 'Getting there';
    if (avg >= 50) return 'Needs work';
    return 'Starting out';
  }

  /// Tries per day for the last 7 days, oldest first (for the
  /// activity chart). [stamps] are attempt timestamps in ms.
  static List<int> weeklyCounts(List<int> stamps, {DateTime? now}) {
    final today = now ?? DateTime.now();
    DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
    final base = dayOf(today);
    final counts = List<int>.filled(7, 0);
    for (final t in stamps) {
      final diff = base.difference(dayOf(DateTime.fromMillisecondsSinceEpoch(t)));
      final days = diff.inDays;
      if (days >= 0 && days < 7) counts[6 - days]++;
    }
    return counts;
  }

  /// Weekday letters matching [weeklyCounts] order (oldest first).
  static List<String> weeklyLetters({DateTime? now}) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final today = now ?? DateTime.now();
    return List.generate(7, (i) {
      final d = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: 6 - i));
      return letters[d.weekday - 1];
    });
  }
}
