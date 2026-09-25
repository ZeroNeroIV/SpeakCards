import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../practice/recorder_service.dart';
import '../scoring/dsp_scorer.dart';
import '../scoring/wav_utils.dart';

/// On-device native voice for reference playback AND reference scoring.
/// No audio files shipped: speaks through the OS TTS engine (Google TTS
/// on Android, AVSpeech on iOS) and can also render an utterance to PCM
/// in RAM via [getReferencePcm] for DTW comparison. Synthesized
/// references are cached (memory + app documents) per card + voice.
/// Works offline once the device has a Spanish voice installed.
class ReferenceVoiceService {
  static const double listenRate = 0.45;
  static const double synthRate = 1.0;

  final FlutterTts _tts = FlutterTts();
  final Map<String, Float32List> _refCache = {};
  bool _ready = false;

  /// BCP-47 code of the voice in use, for honest labelling.
  String voice = 'system default';

  Future<void> init() async {
    try {
      for (final lang in ['es-MX', 'es-ES', 'es']) {
        try {
          final available = await _tts.isLanguageAvailable(lang);
          if (available == true) {
            await _tts.setLanguage(lang);
            voice = lang;
            break;
          }
        } catch (_) {}
      }
      await _tts.setSpeechRate(listenRate);
      await _tts.setPitch(1.0);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> speak(String text) async {
    if (!_ready) await init();
    try {
      await _tts.setSpeechRate(listenRate);
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  /// Native reference utterance as 16kHz mono PCM, or null when the
  /// engine can't render (then callers use reference-free scoring).
  Future<Float32List?> getReferencePcm({
    required String cardId,
    required String text,
  }) async {
    if (_refCache.containsKey(cardId)) return _refCache[cardId];
    try {
      final cached = await _readDiskCache(cardId);
      if (cached != null) {
        _refCache[cardId] = cached;
        return cached;
      }
    } catch (_) {}
    final fresh = await _synthesize(text);
    if (fresh == null || fresh.length < 8000) return null;
    _refCache[cardId] = fresh;
    try {
      await _writeDiskCache(cardId, fresh);
    } catch (_) {}
    return fresh;
  }

  Future<Directory> _refDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'tts_reference'));
  }

  Future<Float32List?> _readDiskCache(String cardId) async {
    final dir = await _refDir();
    final marker = File(p.join(dir.path, 'voice.txt'));
    if (!await marker.exists()) return null;
    if ((await marker.readAsString()).trim() != voice) {
      await dir.delete(recursive: true); // stale voice: drop cache
      return null;
    }
    final f = File(p.join(dir.path, 'ref_$cardId.wav'));
    if (!await f.exists()) return null;
    final pcm = AudioPrep.toFloat32(
        AudioPrep.pcm16FromWav(await f.readAsBytes()),);
    return pcm.length >= 8000 ? pcm : null;
  }

  Future<void> _writeDiskCache(String cardId, Float32List pcm) async {
    final dir = await _refDir();
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'voice.txt')).writeAsString(voice);
    await File(p.join(dir.path, 'ref_$cardId.wav')).writeAsBytes(
      RecorderService.wavFromPcm(AudioPrep.floatToPcm16(pcm)),
    );
  }

  /// Renders [text] at natural rate through the OS engine into RAM.
  Future<Float32List?> _synthesize(String text) async {
    try {
      if (!_ready) await init();
      await _tts.setSpeechRate(synthRate);
      final tmp = await getTemporaryDirectory();
      final out = File(p.join(
        tmp.path,
        'tts_${DateTime.now().millisecondsSinceEpoch}.wav',
      ),);
      try {
        final ok = await _tts.synthesizeToFile(text, out.path, true);
        await _tts.setSpeechRate(listenRate);
        if (ok != 1 || !await out.exists()) return null;
        final raw = await out.readAsBytes();
        return WavUtils.readMono16k(raw);
      } finally {
        try {
          await out.delete();
        } catch (_) {}
      }
    } catch (_) {
      try {
        await _tts.setSpeechRate(listenRate);
      } catch (_) {}
      return null;
    }
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
