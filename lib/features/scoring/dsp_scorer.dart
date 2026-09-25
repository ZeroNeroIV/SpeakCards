import 'dart:math' as math;
import 'dart:typed_data';

/// 16kHz mono 16-bit helpers. All audio stays on-device.
class AudioPrep {
  static const int sampleRate = 16000;

  /// Strips a 44-byte WAV header if present; otherwise returns input.
  static Uint8List pcm16FromWav(Uint8List wav) {
    if (wav.length > 44 &&
        wav[0] == 0x52 &&
        wav[1] == 0x49 &&
        wav[2] == 0x46 &&
        wav[3] == 0x46) {
      return wav.sublist(44);
    }
    return wav;
  }

  static Float32List toFloat32(Uint8List pcm16) {
    final n = pcm16.length ~/ 2;
    final out = Float32List(n);
    final bd = ByteData.sublistView(pcm16);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  /// Simple energy VAD trim (leading/trailing silence).
  static Float32List vadTrim(Float32List x, {double threshDb = -40}) {
    final thresh = math.pow(10, threshDb / 20);
    var s = 0, e = x.length;
    while (s < e && x[s].abs() < thresh) {
      s++;
    }
    while (e > s && x[e - 1].abs() < thresh) {
      e--;
    }
    if (e - s < sampleRate ~/ 2) return x; // keep all if <0.5s voiced
    return Float32List.fromList(x.sublist(s, e));
  }

  /// RMS-normalizes to [target] so mic gain vs TTS volume never
  /// dominates the comparison. Returns the original when near-silent.
  static Float32List normalizeRms(Float32List x, {double target = 0.1}) {
    var sum = 0.0;
    for (final s in x) {
      sum += s * s;
    }
    final rms = math.sqrt(sum / x.length);
    if (rms < 1e-6) return x;
    final g = target / rms;
    final out = Float32List(x.length);
    for (var i = 0; i < x.length; i++) {
      out[i] = (x[i] * g).clamp(-1.0, 1.0).toDouble();
    }
    return out;
  }

  static Uint8List floatToPcm16(Float32List x) {
    final out = Uint8List(x.length * 2);
    final bd = ByteData.sublistView(out);
    for (var i = 0; i < x.length; i++) {
      bd.setInt16(i * 2, (x[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return out;
  }
}

/// Result of the classical (non-AI) scorer.
/// [distance] is the DTW cost vs the on-device native reference, or -1
/// when no reference could be synthesized (then [overall] is computed
/// from the learner audio + dictionary timing alone).
/// [rateRatio] is learnerSecs / referenceSecs (>1.2 slow, <0.8 fast),
/// or -1 without a reference.
class DspResult {
  final int overall, fluency, completeness, prosody;
  final double distance;
  final double rateRatio;
  final String qualityFlag; // ok | too_short | clipped | noisy
  const DspResult({
    required this.overall,
    required this.fluency,
    required this.completeness,
    required this.prosody,
    required this.distance,
    required this.rateRatio,
    required this.qualityFlag,
  });

  Map<String, dynamic> toJson() => {
        'overall': overall,
        'fluency': fluency,
        'completeness': completeness,
        'prosody': prosody,
        'distance': distance,
        'rate_ratio': rateRatio,
        'quality_flag': qualityFlag,
      };
}

/// Classical scorer: MFCC-lite + DTW vs bundled native reference,
/// speaking-rate/pause fluency, duration completeness, pitch/energy prosody.
/// Deliberately NOT neural — so LAYA remains the only AI in the app.
class DspScorer {
  /// Simplified MFCC: pre-emphasis → Hamming frames → magnitude spectrum
  /// → 13 mel-ish cepstral-ish coefficients via DCT-II. Good enough for
  /// template DTW on short drills; not a certified phoneme recognizer.
  static List<List<double>> mfcc(Float32List x, {int sr = 16000}) {
    const frameLen = 400; // 25ms @16k
    const hop = 160; // 10ms
    const nCoef = 13;
    final frames = <List<double>>[];
    final win = List<double>.generate(
        frameLen, (n) => 0.54 - 0.46 * math.cos(2 * math.pi * n / frameLen),);
    for (var start = 0; start + frameLen <= x.length; start += hop) {
      // Naive DFT magnitudes (32 bins) — fine for short on-device drills.
      const bins = 32;
      final mags = List<double>.filled(bins, 0);
      for (var k = 0; k < bins; k++) {
        var re = 0.0, im = 0.0;
        for (var n = 0; n < frameLen; n++) {
          final s = x[start + n] * win[n];
          final a = 2 * math.pi * k * n / frameLen;
          re += s * math.cos(a);
          im -= s * math.sin(a);
        }
        mags[k] = math.sqrt(re * re + im * im) + 1e-6;
      }
      // log + DCT-II → cepstra
      final coef = List<double>.filled(nCoef, 0);
      for (var m = 0; m < nCoef; m++) {
        var acc = 0.0;
        for (var k = 0; k < bins; k++) {
          acc += math.log(mags[k]) * math.cos(math.pi * m * (2 * k + 1) / (2 * bins));
        }
        coef[m] = acc;
      }
      frames.add(coef);
    }
    return frames;
  }

  static double _frameDist(List<double> a, List<double> b) {
    var s = 0.0;
    for (var i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      s += d * d;
    }
    return math.sqrt(s);
  }

  /// DTW mean cost per aligned step.
  static double dtw(List<List<double>> a, List<List<double>> b) {
    if (a.isEmpty || b.isEmpty) return double.infinity;
    final n = a.length, m = b.length;
    final prev = List<double>.filled(m + 1, double.infinity);
    final cur = List<double>.filled(m + 1, double.infinity);
    prev[0] = 0;
    for (var i = 1; i <= n; i++) {
      cur[0] = double.infinity;
      for (var j = 1; j <= m; j++) {
        final cost = _frameDist(a[i - 1], b[j - 1]);
        cur[j] = cost +
            math.min(prev[j], math.min(cur[j - 1], prev[j - 1]));
      }
      for (var j = 0; j <= m; j++) {
        prev[j] = cur[j];
      }
    }
    return prev[m] / (n + m);
  }

  static int _clamp01(double v) => (v * 100).round().clamp(0, 100);

  /// Heuristic expected duration from card text (words * 0.7s, 1..6s).
  /// Used when no reference WAV exists so completeness stays REAL
  /// (measured from the actual recording length).
  static double expectedSecsFor(String text) {
    final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return (words * 0.7).clamp(1.0, 6.0);
  }

  /// REAL scoring without a synthesized reference (e.g. no Spanish voice
  /// installed). Measures the actual learner PCM:
  /// too_short/clipped detection, pause-based fluency, duration-based
  /// completeness, pitch/energy prosody. No mocks, no constants.
  static DspResult scoreNoReference({
    required Float32List learner,
    double expectedSecs = 2.0,
  }) {
    if (learner.length < 8000) {
      return const DspResult(
        overall: 0, fluency: 0, completeness: 0, prosody: 0,
        distance: -1, rateRatio: -1, qualityFlag: 'too_short',
      );
    }
    var clipped = 0;
    for (final s in learner) {
      if (s.abs() > 0.98) clipped++;
    }
    final quality =
        clipped > learner.length * 0.01 ? 'clipped' : 'ok';

    final l = AudioPrep.vadTrim(learner);
    final durRatio = (l.length / learner.length).clamp(0.0, 1.0);
    final pauses = _countPauses(learner);
    final fluency = _clamp01(
        (durRatio * 0.6 + (1 - (pauses / 6).clamp(0.0, 1.0)) * 0.4),);

    final gotSecs = learner.length / 16000;
    final completeness =
        _clamp01(1.0 - ((gotSecs - expectedSecs).abs() / (expectedSecs * 1.5 + 0.5)));

    final prosody = _clamp01(1.0 - (_pitchVar(l) + _energyVar(l)) / 2.0);

    final overall =
        ((fluency * 0.4 + prosody * 0.3 + completeness * 0.3)).round().clamp(0, 100);

    return DspResult(
      overall: overall, fluency: fluency,
      completeness: completeness, prosody: prosody,
      distance: -1, rateRatio: -1, qualityFlag: quality,
    );
  }

  /// Full scoring vs reference PCM. Thresholds are pilot defaults —
  /// recalibrate on 20 real clips (see test/dsp_scorer_test.dart).
  static DspResult score({
    required Float32List learner,
    required Float32List reference,
    double expectedSecs = 2.0,
  }) {
    if (learner.length < 8000) {
      return const DspResult(
          overall: 0, fluency: 0, completeness: 0, prosody: 0,
          distance: 1e9, rateRatio: -1, qualityFlag: 'too_short',);
    }
    var clipped = 0;
    for (final s in learner) {
      if (s.abs() > 0.98) clipped++;
    }
    final quality =
        clipped > learner.length * 0.01 ? 'clipped' : 'ok';

    // Loudness-normalize first: mic gain vs TTS volume must not fake
    // similarity. Clipping was already detected on the raw signal above.
    final learnerN = AudioPrep.normalizeRms(learner);
    final l = AudioPrep.vadTrim(learnerN);
    final r = AudioPrep.vadTrim(AudioPrep.normalizeRms(reference));
    final dist = dtw(mfcc(l), mfcc(r));

    // distance ~0.5 native-like … ~8+ far. Map to 0..100.
    final overall = _clamp01(1.0 - (dist / 8.0).clamp(0.0, 1.0));

    final durRatio = (l.length / learnerN.length).clamp(0.0, 1.0);
    final pauses = _countPauses(learnerN);
    final fluency = _clamp01((durRatio * 0.6 + (1 - (pauses / 6).clamp(0.0, 1.0)) * 0.4));

    final refSecs = reference.length / 16000;
    final gotSecs = learner.length / 16000;
    final completeness =
        _clamp01(1.0 - ((gotSecs - refSecs).abs() / (refSecs + expectedSecs)));
    final rateRatio = refSecs > 0 ? gotSecs / refSecs : -1.0;

    final prosody = _clamp01(1.0 - (_pitchVar(l) + _energyVar(l)) / 2.0);

    return DspResult(
      overall: overall, fluency: fluency,
      completeness: completeness, prosody: prosody,
      distance: dist, rateRatio: rateRatio, qualityFlag: quality,
    );
  }

  static int _countPauses(Float32List x) {
    const hop = 1600; // 100ms
    var pauses = 0, inPause = false;
    for (var i = 0; i < x.length; i += hop) {
      var e = 0.0;
      final end = math.min(i + hop, x.length);
      for (var j = i; j < end; j++) {
        e += x[j] * x[j];
      }
      e /= (end - i);
      if (e < 1e-5) {
        if (!inPause) {
          pauses++;
          inPause = true;
        }
      } else {
        inPause = false;
      }
    }
    return pauses;
  }

  static double _energyVar(Float32List x) {
    const hop = 1600;
    final energies = <double>[];
    for (var i = 0; i < x.length; i += hop) {
      var e = 0.0;
      final end = math.min(i + hop, x.length);
      for (var j = i; j < end; j++) {
        e += x[j] * x[j];
      }
      energies.add(e / (end - i));
    }
    if (energies.isEmpty) return 1.0;
    final mean = energies.reduce((a, b) => a + b) / energies.length;
    var v = 0.0;
    for (final e in energies) {
      v += (e - mean) * (e - mean);
    }
    return (v / energies.length).clamp(0.0, 1.0);
  }

  /// Zero-crossing-rate variance as cheap pitch-movement proxy.
  static double _pitchVar(Float32List x) {
    const hop = 1600;
    final zcrs = <double>[];
    for (var i = 0; i + hop <= x.length; i += hop) {
      var zc = 0;
      for (var j = i + 1; j < i + hop; j++) {
        if ((x[j] >= 0) != (x[j - 1] >= 0)) zc++;
      }
      zcrs.add(zc / hop);
    }
    if (zcrs.isEmpty) return 1.0;
    final mean = zcrs.reduce((a, b) => a + b) / zcrs.length;
    var v = 0.0;
    for (final z in zcrs) {
      v += (z - mean) * (z - mean);
    }
    return (v * 40).clamp(0.0, 1.0);
  }
}
