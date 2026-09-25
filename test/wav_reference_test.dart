import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:speakcards/features/scoring/dsp_scorer.dart';
import 'package:speakcards/features/scoring/wav_utils.dart';

/// Builds a minimal WAV: [channels]×[bits]-bit PCM at [sr] Hz.
Uint8List makeWav({
  required Float32List mono,
  required int sr,
  int channels = 1,
  int bits = 16,
}) {
  final frames = mono.length;
  final data = Uint8List(frames * channels * bits ~/ 8);
  final bd = ByteData.sublistView(data);
  for (var f = 0; f < frames; f++) {
    for (var ch = 0; ch < channels; ch++) {
      final off = (f * channels + ch) * bits ~/ 8;
      // Stereo check: tone on left only, silence on right.
      final sample = (channels == 2 && ch == 1) ? 0.0 : mono[f];
      if (bits == 16) {
        bd.setInt16(off, (sample * 32767).round(), Endian.little);
      } else {
        bd.setUint8(off, (sample * 127 + 128).round());
      }
    }
  }
  final out = Uint8List(44 + data.length);
  final h = ByteData.sublistView(out);
  out.setRange(0, 4, 'RIFF'.codeUnits);
  h.setUint32(4, 36 + data.length, Endian.little);
  out.setRange(8, 12, 'WAVE'.codeUnits);
  out.setRange(12, 16, 'fmt '.codeUnits);
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, channels, Endian.little);
  h.setUint32(24, sr, Endian.little);
  h.setUint32(28, sr * channels * bits ~/ 8, Endian.little);
  h.setUint16(32, channels * bits ~/ 8, Endian.little);
  h.setUint16(34, bits, Endian.little);
  out.setRange(36, 40, 'data'.codeUnits);
  h.setUint32(40, data.length, Endian.little);
  out.setRange(44, 44 + data.length, data);
  return out;
}

Float32List tone(double freq, double secs, {int sr = 16000}) {
  final n = (secs * sr).toInt();
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = 0.5 * math.sin(2 * math.pi * freq * i / sr);
  }
  return out;
}

void main() {
  test('foreign WAV (22k stereo) becomes 16k mono', () {
    final wav = makeWav(mono: tone(440, 1.0, sr: 22050), sr: 22050,
        channels: 2,);
    final out = WavUtils.readMono16k(wav);
    expect(out.length, inInclusiveRange(15900, 16100));
    var peak = 0.0;
    for (final s in out) {
      peak = math.max(peak, s.abs());
    }
    expect(peak, inInclusiveRange(0.2, 0.3)); // 0.5 downmixed to 0.25
  });

  test('8-bit 8kHz mono upscales', () {
    final wav = makeWav(mono: tone(440, 1.0, sr: 8000), sr: 8000,
        channels: 1, bits: 8,);
    final out = WavUtils.readMono16k(wav);
    expect(out.length, inInclusiveRange(15900, 16100));
    var peak = 0.0;
    for (final s in out) {
      peak = math.max(peak, s.abs());
    }
    expect(peak, greaterThan(0.4));
  });

  test('non-WAV throws FormatException', () {
    expect(() => WavUtils.readMono16k(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,);
    expect(
        () => WavUtils.readMono16k(
            Uint8List.fromList(List.filled(100, 0)),),
        throwsFormatException,);
  });

  test('loudness normalization does not fake similarity', () {
    final ref = tone(440, 1.5);
    final quiet = Float32List.fromList(ref.map((s) => s * 0.1).toList());
    final loud = Float32List.fromList(ref.map((s) => s * 3.0).toList());
    final q = DspScorer.score(learner: quiet, reference: ref);
    final l = DspScorer.score(learner: loud, reference: ref);
    expect(q.overall, greaterThan(80));
    expect(l.overall, greaterThan(80));
    expect(q.rateRatio, closeTo(1.0, 0.01));
  });

  test('different content scores lower than identical', () {
    final ref = tone(440, 1.5);
    final same = Float32List.fromList(ref);
    final other = tone(880, 1.5);
    final s = DspScorer.score(learner: same, reference: ref);
    final o = DspScorer.score(learner: other, reference: ref);
    expect(s.overall, greaterThan(o.overall));
    expect(DspScorer.scoreNoReference(learner: same).rateRatio, -1);
  });
}
