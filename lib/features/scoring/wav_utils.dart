import 'dart:math' as math;
import 'dart:typed_data';

/// Reads WAV files produced by foreign encoders (the OS TTS engine:
/// unknown sample rate, channel count, bit depth) into 16kHz mono
/// float PCM for the DSP scorer. Throws [FormatException] when the
/// bytes are not a supported WAV — callers fall back to
/// reference-free scoring.
class WavUtils {
  static Float32List readMono16k(Uint8List bytes, {int targetSr = 16000}) {
    if (bytes.length < 44) throw const FormatException('too small for WAV');
    if (!_tag(bytes, 0, 'RIFF') || !_tag(bytes, 8, 'WAVE')) {
      throw const FormatException('not a WAV file');
    }
    final bd = ByteData.sublistView(bytes);
    var pos = 12;
    int? format, channels, sr, bits;
    Uint8List? data;
    while (pos + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final size = bd.getUint32(pos + 4, Endian.little);
      final end = math.min(pos + 8 + size, bytes.length);
      if (id == 'fmt ') {
        format = bd.getUint16(pos + 8, Endian.little);
        channels = bd.getUint16(pos + 10, Endian.little);
        sr = bd.getUint32(pos + 12, Endian.little);
        bits = bd.getUint16(pos + 22, Endian.little);
      } else if (id == 'data') {
        data = bytes.sublist(pos + 8, end);
      }
      pos += 8 + size + (size % 2); // chunks are word-aligned
      if (format != null && data != null) break;
    }
    if (format == null || channels == null || sr == null || bits == null) {
      throw const FormatException('WAV missing fmt chunk');
    }
    if (data == null || data.isEmpty) {
      throw const FormatException('WAV missing data chunk');
    }
    if (sr <= 0 || channels <= 0) throw const FormatException('bad WAV fmt');

    final frames = _decodeFrames(data, format, channels, bits);
    final mono = _downmix(frames, channels);
    return _resample(mono, sr, targetSr);
  }

  static bool _tag(Uint8List b, int at, String tag) {
    if (at + 4 > b.length) return false;
    return String.fromCharCodes(b.sublist(at, at + 4)) == tag;
  }

  /// Interleaved frames → per-frame channel lists as floats.
  static List<List<double>> _decodeFrames(
      Uint8List data, int format, int channels, int bits,) {
    final frameBytes = channels * bits ~/ 8;
    final nFrames = data.length ~/ frameBytes;
    if (nFrames == 0) throw const FormatException('WAV data empty');
    final frames = List<List<double>>.generate(
        nFrames, (_) => List<double>.filled(channels, 0),);
    final bd = ByteData.sublistView(data, 0, nFrames * frameBytes);
    for (var f = 0; f < nFrames; f++) {
      for (var ch = 0; ch < channels; ch++) {
        final off = (f * channels + ch) * bits ~/ 8;
        double v;
        if (format == 1 && bits == 16) {
          v = bd.getInt16(off, Endian.little) / 32768.0;
        } else if (format == 1 && bits == 8) {
          v = (bd.getUint8(off) - 128) / 128.0;
        } else if (format == 3 && bits == 32) {
          v = bd.getFloat32(off, Endian.little).clamp(-1.0, 1.0);
        } else {
          throw FormatException('unsupported WAV: format=$format bits=$bits');
        }
        frames[f][ch] = v;
      }
    }
    return frames;
  }

  static Float32List _downmix(List<List<double>> frames, int channels) {
    final out = Float32List(frames.length);
    for (var i = 0; i < frames.length; i++) {
      var s = 0.0;
      for (final v in frames[i]) {
        s += v;
      }
      out[i] = s / channels;
    }
    return out;
  }

  static Float32List _resample(Float32List x, int fromSr, int toSr) {
    if (fromSr == toSr) return x;
    final n = (x.length * toSr / fromSr).round();
    if (n < 1) throw const FormatException('resample produced nothing');
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      final pos = i * x.length / n;
      final i0 = pos.floor().clamp(0, x.length - 1);
      final i1 = (i0 + 1).clamp(0, x.length - 1);
      final t = (pos - i0).clamp(0.0, 1.0);
      out[i] = x[i0] * (1 - t) + x[i1] * t;
    }
    return out;
  }
}
