import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tables.dart';

part 'db.g.dart';

/// On-device database. Nothing leaves the phone.
@DriftDatabase(tables: [Cards, Attempts, Srs, SoundStats])
class AppDb extends _$AppDb {
  AppDb() : super(_open());

  AppDb.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2 drops Cards.audioPath (dictionary + native voice replace
            // reference WAVs). Cards mirror bundled JSON and are reseeded
            // every boot; attempts/SRS rows rejoin by card id.
            await m.deleteTable('cards');
            await m.createTable(cards);
          }
        },
      );

  Future<void> upsertCard(CardsCompanion c) =>
      into(cards).insertOnConflictUpdate(c);

  Future<void> logAttempt(AttemptsCompanion a) => into(attempts).insert(a);

  Future<List<Attempt>> recentAttempts(String cardId, {int limit = 3}) {
    return (select(attempts)
          ..where((t) => t.cardId.equals(cardId))
          ..orderBy([(t) => OrderingTerm.desc(t.ts)])
          ..limit(limit))
        .get();
  }

  /// Newest-first overall scores across all cards of one target sound.
  Future<List<int>> recentScoresForSound(String sound, {int limit = 5}) async {
    final ids = await (select(cards)
          ..where((t) => t.targetSound.equals(sound)))
        .map((c) => c.id)
        .get();
    if (ids.isEmpty) return [];
    final rows = await (select(attempts)
          ..where((t) => t.cardId.isIn(ids))
          ..orderBy([(t) => OrderingTerm.desc(t.ts)])
          ..limit(limit))
        .get();
    return rows.map((a) => a.overall).toList();
  }

  Future<int> attemptCount() async {
    final q = selectOnly(attempts)..addColumns([attempts.id.count()]);
    return (await q.getSingle()).read(attempts.id.count()) ?? 0;
  }

  Future<double> averageOverall() async {
    final q = selectOnly(attempts)..addColumns([attempts.overall.avg()]);
    return (await q.getSingle()).read(attempts.overall.avg()) ?? 0.0;
  }

  Future<List<SoundStat>> allSoundStats() {
    return (select(soundStats)..orderBy([(t) => OrderingTerm.asc(t.sound)]))
        .get();
  }

  /// Newest-first attempt timestamps (for streak math).
  Future<List<int>> attemptTimes({int limit = 1000}) {
    final q = selectOnly(attempts)
      ..addColumns([attempts.ts])
      ..orderBy([OrderingTerm.desc(attempts.ts)])
      ..limit(limit);
    return q.map((r) => r.read(attempts.ts)!).get();
  }

  Future<int> bestForCard(String cardId) async {
    final q = selectOnly(attempts)
      ..addColumns([attempts.overall.max()])
      ..where(attempts.cardId.equals(cardId));
    return (await q.getSingle()).read(attempts.overall.max()) ?? 0;
  }

  Future<int> todayCount({DateTime? now}) async {
    final day = now ?? DateTime.now();
    final start =
        DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final q = selectOnly(attempts)
      ..addColumns([attempts.id.count()])
      ..where(attempts.ts.isBiggerOrEqualValue(start));
    return (await q.getSingle()).read(attempts.id.count()) ?? 0;
  }

  Future<void> recordSoundStat(String sound, int overall) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await (select(soundStats)
          ..where((t) => t.sound.equals(sound)))
        .getSingleOrNull();
    if (existing == null) {
      await into(soundStats).insert(
        SoundStatsCompanion.insert(
          sound: sound,
          attempts: const Value(1),
          avg: Value(overall.toDouble()),
          lastFail: overall < 70 ? Value(now) : const Value.absent(),
        ),
      );
    } else {
      final n = existing.attempts + 1;
      final avg = (existing.avg * existing.attempts + overall) / n;
      await (update(soundStats)..where((t) => t.sound.equals(sound))).write(
        SoundStatsCompanion(
          attempts: Value(n),
          avg: Value(avg),
          lastFail: overall < 70 ? Value(now) : Value(existing.lastFail),
        ),
      );
    }
  }
}

LazyDatabase _open() => LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'speakcards.sqlite'));
      return NativeDatabase(file);
    });
