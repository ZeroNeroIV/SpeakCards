import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

/// One live mic take. Everything stays in memory — no WAV files on disk.
/// [pcmBytes] is raw LE16 mono 16kHz, [pcmFloat] is -1..1 for the DSP scorer,
/// [wavBytes] is a 44-byte RIFF header + PCM for the LAYA audio model.
class LiveTake {
  final Uint8List pcmBytes;
  final Float32List pcmFloat;
  final Uint8List wavBytes;
  final Duration duration;
  const LiveTake({
    required this.pcmBytes,
    required this.pcmFloat,
    required this.wavBytes,
    required this.duration,
  });
}

/// Native live recorder: streams raw PCM16 from the OS mic via
/// `AudioRecorder.startStream`, accumulates in RAM, emits a live 0..1
/// level for the UI. No temp files, no path_provider, works on
/// Android/iOS/macOS/Windows/web where the record plugin supports PCM.
class RecorderService {
  static const int sampleRate = 16000;
  static const int numChannels = 1;

  final AudioRecorder _rec = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  BytesBuilder? _buf;
  DateTime? _startAt;
  bool _on = false;

  final _levelCtrl = StreamController<double>.broadcast();
  Stream<double> get levelStream => _levelCtrl.stream;
  bool get isRecording => _on;

  Future<bool> hasPermission() => _rec.hasPermission();

  Future<void> start() async {
    if (!await hasPermission()) {
      throw StateError('Microphone permission denied');
    }
    // Clean any previous session without emitting levels after dispose.
    await _sub?.cancel();
    _sub = null;
    try {
      await _rec.cancel();
    } catch (_) {}

    _buf = BytesBuilder();
    _startAt = DateTime.now();

    final stream = await _rec.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: false,
      ),
    );
    _on = true;
    _sub = stream.listen(
      (chunk) {
        _buf?.add(chunk);
        if (!_levelCtrl.isClosed) _levelCtrl.add(rms01(chunk));
      },
      onError: (Object e) {
        if (!_levelCtrl.isClosed) _levelCtrl.addError(e);
      },
      cancelOnError: false,
    );
  }

  /// Stops the OS stream and returns the in-memory take,
  /// or null if not recording.
  Future<LiveTake?> stop() async {
    if (!_on) return null;
    _on = false;
    try {
      await _rec.stop();
    } catch (_) {}
    await _sub?.cancel();
    _sub = null;

    final pcm = _buf?.takeBytes() ?? Uint8List(0);
    _buf = null;
    final duration = _startAt == null
        ? Duration.zero
        : DateTime.now().difference(_startAt!);
    _startAt = null;
    if (!_levelCtrl.isClosed) _levelCtrl.add(0.0);

    final floats = pcmToFloat32(pcm);
    final wav = wavFromPcm(pcm,
        sampleRate: sampleRate, numChannels: numChannels,);
    return LiveTake(
      pcmBytes: pcm,
      pcmFloat: floats,
      wavBytes: wav,
      duration: duration,
    );
  }

  Future<void> dispose() async {
    _on = false;
    await _sub?.cancel();
    await _levelCtrl.close();
    await _rec.dispose();
  }

  /// RMS level 0..1 computed live from a raw LE16 chunk.
  static double rms01(Uint8List chunk) {
    if (chunk.length < 2) return 0.0;
    final n = chunk.length ~/ 2;
    final bd = ByteData.sublistView(chunk, 0, n * 2);
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final s = bd.getInt16(i * 2, Endian.little) / 32768.0;
      sum += s * s;
    }
    return math.sqrt(sum / n).clamp(0.0, 1.0);
  }

  static Float32List pcmToFloat32(Uint8List pcm16) {
    final n = pcm16.length ~/ 2;
    final out = Float32List(n);
    final bd = ByteData.sublistView(pcm16, 0, n * 2);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  /// Synthesizes a 16-bit PCM WAV in RAM so the LAYA audio model
  /// (which expects whole WAV bytes) works with zero file I/O.
  static Uint8List wavFromPcm(
    Uint8List pcm, {
    int sampleRate = sampleRate,
    int numChannels = numChannels,
  }) {
    final dataLen = (pcm.length ~/ 2) * 2;
    final out = Uint8List(44 + dataLen);
    final bd = ByteData.sublistView(out);
    // RIFF
    out[0] = 0x52; out[1] = 0x49; out[2] = 0x46; out[3] = 0x46; // RIFF
    bd.setUint32(4, 36 + dataLen, Endian.little);
    out[8] = 0x57; out[9] = 0x41; out[10] = 0x56; out[11] = 0x45; // WAVE
    out[12] = 0x66; out[13] = 0x6D; out[14] = 0x74; out[15] = 0x20; // fmt
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, numChannels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * numChannels * 2, Endian.little);
    bd.setUint16(32, numChannels * 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    out[36] = 0x64; out[37] = 0x61; out[38] = 0x74; out[39] = 0x61; // data
    bd.setUint32(40, dataLen, Endian.little);
    out.setRange(44, 44 + dataLen, pcm);
    return out;
  }
}
