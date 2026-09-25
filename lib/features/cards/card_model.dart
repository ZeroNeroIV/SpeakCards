import 'dart:convert';
import 'package:flutter/services.dart';

/// Flashcard model. `targetSound` tags the Spanish sound this card drills
/// (rr, r, j, ll, ny, b_v, d, vowels, stress). Canonical pronunciation
/// comes from the bundled dictionary; the OS voice speaks references.
class CardModel {
  final String id;
  final String es;
  final String en;
  final String targetSound;
  final int difficulty;

  const CardModel({
    required this.id,
    required this.es,
    required this.en,
    required this.targetSound,
    required this.difficulty,
  });

  factory CardModel.fromJson(Map<String, dynamic> j) => CardModel(
        id: j['id'] as String,
        es: j['es'] as String,
        en: j['en'] as String,
        targetSound: j['target_sound'] as String,
        difficulty: (j['difficulty'] as num).toInt(),
      );
}

/// Loads bundled content. Human reference WAVs live under assets/audio/es/.
class CardRepository {
  List<CardModel>? _cache;

  Future<List<CardModel>> loadAll() async {
    if (_cache != null) return _cache!;
    final raw =
        await rootBundle.loadString('assets/content/cards_es_en.json');
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    _cache = list.map(CardModel.fromJson).toList();
    return _cache!;
  }

  Future<List<CardModel>> dueCards() async {
    // Unfiltered loader; PracticeScreen filters by SRS due dates from AppDb.
    return loadAll();
  }

  Future<List<CardModel>> bySound(String sound) async {
    final all = await loadAll();
    return all.where((c) => c.targetSound == sound).toList();
  }
}
