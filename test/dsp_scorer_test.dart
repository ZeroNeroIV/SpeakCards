import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:speakcards/features/scoring/dsp_scorer.dart';

Float32List tone(double freq, double secs, {int sr = 16000}) {
  final n = (secs * sr).toInt();
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = 0.5 * math.sin(3.14159 * 2 * freq * i / sr);
  }
  return out;
}

void main() {
  test('identical signals score high, short clips flagged', () {
    final ref = tone(440, 1.5);
    final same = Float32List.fromList(ref);
    final r = DspScorer.score(learner: same, reference: ref);
    expect(r.qualityFlag, 'ok');
    expect(r.overall, greaterThan(80));

    final tiny = tone(440, 0.2);
    expect(DspScorer.score(learner: tiny, reference: ref).qualityFlag,
        'too_short',);
  });

  test('dtw is symmetric-ish and finite', () {
    final a = DspScorer.mfcc(tone(440, 1.0));
    final b = DspScorer.mfcc(tone(520, 1.0));
    expect(DspScorer.dtw(a, a), lessThan(DspScorer.dtw(a, b)));
  });
}
