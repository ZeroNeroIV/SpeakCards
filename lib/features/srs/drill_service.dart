import '../cards/card_model.dart';

/// Sound-specific drills: after 3 fails on one target_sound (avg < 70),
/// build a mini-lesson from cards sharing that sound.
class DrillService {
  static const int triggerCount = 3;
  static const int triggerAvg = 70;

  bool shouldTrigger(List<int> recentScoresForSound) {
    if (recentScoresForSound.length < triggerCount) return false;
    final last3 = recentScoresForSound.sublist(
        recentScoresForSound.length - triggerCount,);
    final avg = last3.reduce((a, b) => a + b) / last3.length;
    return avg < triggerAvg;
  }

  List<CardModel> buildDrill(List<CardModel> sameSound, {int limit = 4}) {
    return sameSound.take(limit).toList();
  }

  static const Map<String, String> soundTips = {
    'rr': 'Trill rr: perro, carro. Tip: tongue tip taps the ridge, extra airflow.',
    'r': 'Single r is one tap: pero, para. Don’t roll it.',
    'j': 'Jota is a throaty h: rojo, jamás. From the back, not the lips.',
    'll': 'll/y ≈ English y: llama, yo. No j-sound.',
    'ny': 'ñ ≈ ny in canyon: niño, mañana.',
    'b_v': 'b/v merge: vaso, beso. Soft, lips barely touch between vowels.',
    'd': 'd between vowels is soft ð (this): cada, nada.',
    'vowels': 'Five pure vowels: a e i o u. Don’t diphthongize o/e.',
    'stress': 'Stress matters: papa vs papá. Hit the accented syllable.',
  };
}
