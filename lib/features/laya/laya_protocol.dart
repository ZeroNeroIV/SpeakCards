/// LAYA prompts + JSON schemas. Same contract for Path A (audio-capable
/// Gemma 3n E2B) and Path B (text-only 270M + DSP numbers).
class LayaPrompts {
  static const String system = '''
You are LAYA, the ONLY AI in SpeakCards, running fully on-device.
Decide the next learning action for an English speaker learning Spanish.
Be kind, concrete, one tip only. Never claim accent judgment; scores are
reference-match on this device, not absolute truth.
Reply with JSON ONLY, no prose, matching the schema.
Spanish pain points: rr/perro vs r/pero, jota rojo, ll/y llama, ñ niño,
b/v merge, soft d cada, 5 pure vowels, stress papa vs papá.
''';

  static String userText({
    required String expected,
    required String targetSound,
    required List<int> history,
    Map<String, dynamic>? dsp,
    String? ipa,
  }) {
    final h = history.isEmpty ? 'none' : history.join(',');
    final d = dsp == null ? 'audio attached (Path A)' : dsp.toString();
    final canon = ipa == null ? '' : '"canonical":"$ipa",';
    return '''
{"state":{"card":"$expected",$canon"target_sound":"$targetSound",
"history_scores":"$h","measurement":"$d"},
"questions":{"next_action":{"type":"choice","criteria":{
"repeat_word":"single-word card <70 or target weak",
"repeat_sentence":"understandable but overall <80",
"show_explanation":"same sound fails 3x",
"advance":"overall >=85","schedule_review":"otherwise"}},
"confidence":{"type":"score","instructions":"0-4 trust"}}}
''';
  }
}

/// Validated LAYA output. Rule fallback lives in LayaClient on parse fail.
class LayaDecision {
  final String nextAction;
  final String target;
  final int confidence;
  final String feedbackEn;
  final String feedbackEs;

  const LayaDecision({
    required this.nextAction,
    required this.target,
    required this.confidence,
    required this.feedbackEn,
    required this.feedbackEs,
  });

  static const validActions = {
    'repeat_word',
    'repeat_sentence',
    'show_explanation',
    'advance',
    'schedule_review',
  };

  factory LayaDecision.fromJson(Map<String, dynamic> j, String fallbackTarget) {
    final a = (j['next_action'] ?? 'schedule_review').toString();
    return LayaDecision(
      nextAction: validActions.contains(a) ? a : 'schedule_review',
      target: (j['target'] ?? fallbackTarget).toString(),
      confidence: ((j['confidence'] ?? 2) as num).toInt().clamp(0, 4),
      feedbackEn: (j['feedback_en'] ?? 'Try once more, slowly.').toString(),
      feedbackEs: (j['feedback_es'] ?? 'Intenta de nuevo, despacio.').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'next_action': nextAction,
        'target': target,
        'confidence': confidence,
        'feedback_en': feedbackEn,
        'feedback_es': feedbackEs,
      };
}
