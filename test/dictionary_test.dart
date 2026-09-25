import 'package:flutter_test/flutter_test.dart';
import 'package:speakcards/features/cards/card_model.dart';
import 'package:speakcards/features/dictionary/dictionary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dictionary covers every word of every card', () async {
    final cards = await CardRepository().loadAll();
    expect(cards, isNotEmpty);
    final dict = DictionaryService();
    final entries = await dict.load();
    for (final c in cards) {
      for (final w in DictionaryService.wordsOf(c.es)) {
        expect(entries.containsKey(w), isTrue,
            reason: 'no dictionary entry for "$w" (${c.id})',);
        final e = entries[w]!;
        expect(e.ipa, isNotEmpty);
        expect(e.syllables, isNotEmpty);
        expect(e.stress, inInclusiveRange(0, e.syllables.length - 1),
            reason: 'bad stress for "$w"',);
      }
    }
  });

  test('transcription and timing look sane', () async {
    final dict = DictionaryService();
    expect(await dict.transcription('perro'), contains('pe'));
    expect(
      await dict.syllableCount('El perro está en el patio.'),
      greaterThan(3),
    );
    final secs = await dict.expectedSecs('perro');
    expect(secs, inInclusiveRange(1.0, 6.0));
  });
}
