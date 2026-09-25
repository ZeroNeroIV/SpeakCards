import 'package:drift/drift.dart';

/// Cards mirror the bundled JSON so SRS state can join locally.
class Cards extends Table {
  TextColumn get id => text()();
  TextColumn get es => text()();
  TextColumn get en => text()();
  TextColumn get audioPath => text()();
  TextColumn get targetSound => text()();
  IntColumn get difficulty => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per recording attempt. Scores are device-computed (DSP) or
/// LAYA-audio similarity — labelled as reference-match, never accent truth.
class Attempts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get cardId => text().references(Cards, #id)();
  IntColumn get ts => integer()(); // ms since epoch
  TextColumn get path => text()(); // 'A' (LAYA audio) or 'B' (DSP+text)
  IntColumn get overall => integer()();
  IntColumn get fluency => integer()();
  IntColumn get completeness => integer()();
  IntColumn get prosody => integer()();
  RealColumn get distance => real().nullable()(); // DSP DTW distance, if any
  TextColumn get layaJson => text()();
  IntColumn get confidence => integer()();
}

/// FSRS-lite SRS state. App computes dates; LAYA only picks the category.
class Srs extends Table {
  TextColumn get cardId => text().references(Cards, #id)();
  RealColumn get stability => real().withDefault(const Constant(2.5))();
  RealColumn get difficulty => real().withDefault(const Constant(5.0))();
  IntColumn get dueAt => integer()();
  IntColumn get lapses => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {cardId};
}

/// Aggregate per-sound stats driving sound-specific drills.
class SoundStats extends Table {
  TextColumn get sound => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  RealColumn get avg => real().withDefault(const Constant(0))();
  IntColumn get lastFail => integer().nullable()();

  @override
  Set<Column> get primaryKey => {sound};
}
