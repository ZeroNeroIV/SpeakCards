import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speakcards/data/db.dart';

AppDb memoryDb() => AppDb.forTesting(NativeDatabase.memory());

Future<void> seedCard(AppDb db, String id, String sound) {
  return db.upsertCard(CardsCompanion(
    id: Value(id),
    es: Value(id),
    en: Value(id),
    targetSound: Value(sound),
    difficulty: const Value(1),
  ),);
}

Future<void> log(AppDb db, String cardId, int overall, int ts) {
  return db.logAttempt(AttemptsCompanion.insert(
    cardId: cardId,
    ts: ts,
    path: 'rule',
    overall: overall,
    fluency: overall,
    completeness: overall,
    prosody: overall,
    layaJson: '{}',
    confidence: 2,
  ),);
}

void main() {
  test('per-sound scores come back newest-first', () async {
    final db = memoryDb();
    addTearDown(db.close);
    await seedCard(db, 'w_perro', 'rr');
    await seedCard(db, 'w_carro', 'rr');
    await seedCard(db, 'w_pero', 'r');
    await log(db, 'w_perro', 60, 1000);
    await log(db, 'w_carro', 70, 2000);
    await log(db, 'w_perro', 80, 3000);
    await log(db, 'w_pero', 95, 4000);
    expect(await db.recentScoresForSound('rr'), [80, 70, 60]);
    expect(await db.recentScoresForSound('rr', limit: 2), [80, 70]);
    expect(await db.recentScoresForSound('r'), [95]);
    expect(await db.recentScoresForSound('ny'), isEmpty);
  });

  test('counts, average and timestamps', () async {
    final db = memoryDb();
    addTearDown(db.close);
    expect(await db.attemptCount(), 0);
    expect(await db.averageOverall(), 0.0);
    await seedCard(db, 'w_perro', 'rr');
    await log(db, 'w_perro', 60, 1000);
    await log(db, 'w_perro', 80, 3000);
    expect(await db.attemptCount(), 2);
    expect(await db.averageOverall(), 70.0);
    expect(await db.attemptTimes(), [3000, 1000]);
  });
}
