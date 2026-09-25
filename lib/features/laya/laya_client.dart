import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../scoring/dsp_scorer.dart';
import 'laya_protocol.dart';

/// Which LAYA actually ran. 'rule' = deterministic fallback (no AI call).
enum LayaPath { audioModel, textModel, rule }

class LayaResult {
  final LayaDecision decision;
  final LayaPath path;
  final DspResult? dsp;
  const LayaResult(this.decision, this.path, [this.dsp]);
}

/// Single-AI client.
/// Path A: audio-capable Gemma 3n/4 E2B (.litertlm + audio adapter) hears the
///   whole 16kHz mono WAV directly (header INCLUDED per flutter_gemma docs).
/// Path B: tiny 270M text model reads DSP numbers.
/// Rule fallback if no model installed / parse fails / OOM.
class LayaClient {
  bool audioModelReady = false;
  bool textModelReady = false;

  /// Call once at startup. Probes for installed on-device models;
  /// stays in rule mode when nothing is installed (tests, fresh install).
  Future<void> init() async {
    try {
      final models = await FlutterGemma.listInstalledModels();
      final names = models.map((m) => m.toLowerCase()).join(' ');
      audioModelReady =
          names.contains('e2b') || names.contains('e4b') || names.contains('3n');
      textModelReady = names.contains('270m') || names.isNotEmpty;
    } catch (_) {
      audioModelReady = false;
      textModelReady = false;
    }
  }

  Future<LayaResult> decide({
    required String expected,
    required String targetSound,
    required List<int> history,
    Uint8List? learnerWav, // whole WAV, header included (Path A)
    DspResult? dsp,
    int? dspOverall,
    String? referenceIpa, // canonical transcription from bundled dictionary
  }) async {
    if (learnerWav != null && audioModelReady) {
      try {
        return LayaResult(
          await _askAudio(
            LayaPrompts.userText(
                expected: expected,
                targetSound: targetSound,
                history: history,
                ipa: referenceIpa,),
            learnerWav,
            expected,
          ),
          LayaPath.audioModel,
          dsp,
        );
      } catch (_) {/* fall through to B / rule */}
    }
    if (dsp != null && textModelReady) {
      try {
        return LayaResult(
          await _askText(
            LayaPrompts.userText(
                expected: expected,
                targetSound: targetSound,
                history: history,
                dsp: dsp.toJson(),
                ipa: referenceIpa,),
            expected,
          ),
          LayaPath.textModel,
          dsp,
        );
      } catch (_) {/* fall through */}
    }
    // No invented default: without any measurement overall is 0 (repeat).
    final overall = dsp?.overall ?? dspOverall ?? 0;
    return LayaResult(
        _rule(expected, targetSound, history, overall), LayaPath.rule, dsp,);
  }

  Future<LayaDecision> _askAudio(
      String user, Uint8List wavBytes, String fallbackTarget,) async {
    final model = await FlutterGemma.getActiveModel(
      maxTokens: 1024, // .litertlm requires context >= 1024
      preferredBackend: PreferredBackend.gpu,
      supportAudio: true,
      preferredAudioBackend: PreferredBackend.gpu,
    );
    final chat = await model.createChat(
      systemInstruction: LayaPrompts.system,
      supportAudio: true,
      maxOutputTokens: 256,
    );
    await chat.addQueryChunk(
      Message.withAudio(text: user, audioBytes: wavBytes, isUser: true),
    );
    return _parse(await _responseText(chat), fallbackTarget);
  }

  Future<LayaDecision> _askText(String user, String fallbackTarget) async {
    final model = await FlutterGemma.getActiveModel(
      maxTokens: 1024,
      preferredBackend: PreferredBackend.gpu,
    );
    final chat = await model.createChat(
      systemInstruction: LayaPrompts.system,
      maxOutputTokens: 256,
    );
    await chat.addQueryChunk(Message.text(text: user, isUser: true));
    return _parse(await _responseText(chat), fallbackTarget);
  }

  /// generateChatResponse returns a ModelResponse union; plain text arrives
  /// as TextResponse. Anything else (or empty) is a parse failure → rule path.
  Future<String> _responseText(InferenceChat chat) async {
    final resp = await chat.generateChatResponse();
    if (resp is TextResponse) return resp.token;
    throw FormatException('non-text response: $resp');
  }

  LayaDecision _parse(String resp, String fallbackTarget) {
    final start = resp.indexOf('{');
    final end = resp.lastIndexOf('}');
    if (start < 0 || end <= start) throw const FormatException('no json');
    return LayaDecision.fromJson(
        jsonDecode(resp.substring(start, end + 1)) as Map<String, dynamic>,
        fallbackTarget,);
  }

  LayaDecision _rule(
      String expected, String targetSound, List<int> history, int overall,) {
    final fails = history.where((s) => s < 70).length;
    final action = overall >= 85
        ? 'advance'
        : fails >= 3
            ? 'show_explanation'
            : overall < 70
                ? 'repeat_word'
                : overall < 80
                    ? 'repeat_sentence'
                    : 'schedule_review';
    return LayaDecision(
      nextAction: action,
      target: expected,
      confidence: 2,
      feedbackEn: 'Match $overall% vs reference. One more slow try.',
      feedbackEs: 'Similitud $overall%. Una vez más, despacio.',
    );
  }
}
