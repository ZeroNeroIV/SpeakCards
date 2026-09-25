import 'dart:convert';

import 'package:flutter/services.dart';

/// One dictionary entry: canonical Latin American Spanish pronunciation.
class WordEntry {
  final String ipa;
  final List<String> syllables;
  final int stress;
  const WordEntry({
    required this.ipa,
    required this.syllables,
    required this.stress,
  });

  factory WordEntry.fromJson(Map<String, dynamic> j) => WordEntry(
        ipa: j['ipa'] as String,
        syllables: (j['syllables'] as List).cast<String>(),
        stress: (j['stress'] as num).toInt(),
      );
}

/// Bundled pronunciation dictionary (`assets/content/es_dict.json`).
/// The single source of truth for how each card *should* sound —
/// no reference audio files needed.
class DictionaryService {
  Map<String, WordEntry>? _cache;

  Future<Map<String, WordEntry>> load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/content/es_dict.json');
    final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
    _cache = {
      for (final e in map.entries)
        e.key: WordEntry.fromJson(
            (e.value as Map).cast<String, dynamic>(),),
    };
    return _cache!;
  }

  /// Lowercase words with punctuation stripped (accents kept).
  static List<String> wordsOf(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp('[¿?¡!.,;:]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// Canonical transcription, e.g. "perro" → "ˈpe.ro".
  /// Unknown words fall back to the raw word (never fails).
  Future<String> transcription(String text) async {
    final dict = await load();
    return wordsOf(text).map((w) => dict[w]?.ipa ?? w).join(' ');
  }

  Future<int> syllableCount(String text) async {
    final dict = await load();
    var n = 0;
    for (final w in wordsOf(text)) {
      n += dict[w]?.syllables.length ?? 1;
    }
    return n;
  }

  /// Expected spoken seconds from dictionary syllables (~0.35s each for
  /// learners + 0.3s padding), clamped to a sane drill range.
  Future<double> expectedSecs(String text) async {
    final n = await syllableCount(text);
    return (n * 0.35 + 0.3).clamp(1.0, 6.0);
  }
}
