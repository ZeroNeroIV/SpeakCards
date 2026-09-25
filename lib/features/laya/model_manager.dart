import 'package:device_info_plus/device_info_plus.dart';

/// Picks Path A (audio LAYA, needs ~6GB RAM + 2.8GB model) vs Path B
/// (DSP + 270M, works on 4GB phones). Model files download once on WiFi.
class ModelManager {
  static const String audioModelId = 'google/gemma-3n-E2B-it (litertlm)';
  static const String audioGgufAlt =
      'unsloth/gemma-3n-E2B-it-GGUF:Q4_K_M (~2.8GB)';
  static const String textModelId = 'google/gemma-3-270m-it (~0.3GB)';

  /// device_info_plus exposes no RAM size; use Android's low-RAM flag as the
  /// proxy. Low-RAM → Path B only. Everything else → user may opt into A
  /// (model download ~2.8GB still required).
  Future<bool> deviceSupportsAudioLaya() async {
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      return !android.isLowRamDevice;
    } catch (_) {
      return false; // iOS/desktop: opt into A manually from settings.
    }
  }
}
