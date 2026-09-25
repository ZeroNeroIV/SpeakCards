import 'package:drift/drift.dart';
import '../../data/db.dart';

/// SRS: LAYA picks category, app computes date. Keeps scheduling
/// predictable and editable without re-prompting the model.
class SrsService {
  final AppDb db;
  SrsService(this.db);

  /// Returns next due timestamp (ms) for an overall score.
  static int nextDueMs(int overall, {DateTime? now}) {
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    const day = 24 * 60 * 60 * 1000;
    if (overall < 60) return t; // immediately (same session)
    if (overall < 80) return t + 8 * 60 * 60 * 1000; // later today
    if (overall < 90) return t + day; // tomorrow
    return t + 4 * day; // several days
  }

  Future<void> schedule(String cardId, int overall) async {
    final due = nextDueMs(overall);
    await db.into(db.srs).insertOnConflictUpdate(
          SrsCompanion(
            cardId: Value(cardId),
            dueAt: Value(due),
            stability: Value(_stabilityFor(overall)),
          ),
        );
  }

  static double _stabilityFor(int overall) {
    if (overall >= 90) return 7.0;
    if (overall >= 80) return 4.0;
    if (overall >= 60) return 2.0;
    return 1.0;
  }

  Future<List<Sr>> dueNow() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (db.select(db.srs)..where((t) => t.dueAt.isSmallerOrEqualValue(now)))
        .get();
  }
}
