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
}
