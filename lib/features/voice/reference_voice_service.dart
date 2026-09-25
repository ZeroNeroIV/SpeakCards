import 'package:flutter_tts/flutter_tts.dart';

/// On-device native voice for reference playback. No audio files:
/// speaks through the OS TTS engine (Google TTS on Android,
/// AVSpeech on iOS). Works offline once the device has a Spanish
/// voice installed; otherwise the OS falls back as best it can.
class ReferenceVoiceService {
  final FlutterTts _tts = FlutterTts();
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
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> speak(String text) async {
    if (!_ready) await init();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
