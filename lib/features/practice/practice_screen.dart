import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../cards/card_model.dart';
import '../dictionary/dictionary_service.dart';
import '../laya/laya_client.dart';
import '../scoring/dsp_scorer.dart';
import '../srs/drill_service.dart';
import '../srs/srs_service.dart';
import '../voice/reference_voice_service.dart';
import 'recorder_service.dart';

/// Main loop: show card → native voice reference → live mic stream →
/// score in-RAM PCM against dictionary timing → LAYA next action → save.
/// No audio files anywhere: references come from the bundled pronunciation
/// dictionary (display + timing) and the OS voice (playback).
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});
  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final _cards = CardRepository();
  final _rec = RecorderService();
  final _voice = ReferenceVoiceService();
  final _dict = DictionaryService();
  final _laya = LayaClient();
  late final AppDb _db;
  late final SrsService _srs;
  List<CardModel> _deck = [];
  int _i = 0;
  bool _recording = false;
  bool _scoring = false;
  double _level = 0.0;
  int _liveSecs = 0;
  Timer? _liveTimer;
  DateTime? _liveStart;
  StreamSubscription<double>? _levelSub;
  String _status = 'Loading…';
  String _ipa = '';
  LayaResult? _last;

  @override
  void initState() {
    super.initState();
    _levelSub = _rec.levelStream.listen(
      (v) {
        if (mounted) setState(() => _level = v);
      },
      onError: (_) {},
    );
    _boot();
  }

  Future<void> _boot() async {
    _db = AppDb();
    _srs = SrsService(_db);
    await _laya.init();
    await _voice.init();
    try {
      final all = await _cards.loadAll();
      for (final c in all) {
        await _db.upsertCard(
          CardsCompanion(
            id: drift.Value(c.id),
            es: drift.Value(c.es),
            en: drift.Value(c.en),
            targetSound: drift.Value(c.targetSound),
            difficulty: drift.Value(c.difficulty),
          ),
        );
      }
      final dueRows = await _srs.dueNow();
      final dueIds = dueRows.map((r) => r.cardId).toSet();
      final allSrs = await _db.select(_db.srs).get();
      if (!mounted) return;
      setState(() {
        if (all.isEmpty) {
          _deck = [];
          _status = 'No cards bundled.';
        } else if (allSrs.isEmpty) {
          _deck = all;
          _status = 'Ready';
        } else if (dueRows.isNotEmpty) {
          _deck = all.where((c) => dueIds.contains(c.id)).toList();
          if (_deck.isEmpty) _deck = all;
          _status = 'Ready · ${dueIds.length} due';
        } else {
          _deck = all;
          _status = 'All caught up — reviewing all';
        }
      });
      await _refreshIpa();
      unawaited(_warmReferences()); // render native refs ahead of time
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Startup failed: $e');
    }
  }

  /// Fire-and-forget: synthesize native references for the first due
  /// cards so scoring rarely waits on TTS. Failures just fall back.
  Future<void> _warmReferences() async {
    for (final c in _deck.take(6)) {
      try {
        await _voice.getReferencePcm(cardId: c.id, text: c.es);
      } catch (_) {}
    }
  }

  CardModel? get _card => _deck.isEmpty ? null : _deck[_i % _deck.length];

  Future<void> _refreshIpa() async {
    final c = _card;
    if (c == null) return;
    final ipa = await _dict.transcription(c.es);
    if (!mounted) return;
    setState(() => _ipa = ipa);
  }

  Future<void> _listen() async {
    final c = _card;
    if (c == null) return;
    await _voice.speak(c.es);
  }

  void _startLiveTimer() {
    _liveStart = DateTime.now();
    _liveSecs = 0;
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_recording) return;
      setState(() {
        _liveSecs = DateTime.now().difference(_liveStart!).inSeconds;
      });
    });
  }

  void _stopLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  Future<void> _toggleRecord() async {
    if (_scoring) return;
    if (_recording) {
      _stopLiveTimer();
      setState(() {
        _recording = false;
        _scoring = true;
        _status = 'Scoring…';
      });
      try {
        final take = await _rec.stop();
        if (take == null) throw StateError('No recording captured');
        await _scoreLiveTake(take);
      } catch (e) {
        if (!mounted) return;
        setState(() => _status = 'Recording failed: $e');
      } finally {
        if (mounted) {
          setState(() {
            _scoring = false;
            _level = 0.0;
          });
        }
      }
    } else {
      setState(() {
        _recording = true;
        _last = null;
        _level = 0.0;
        _status = 'Listening… speak now';
      });
      _startLiveTimer();
      try {
        await _rec.start();
      } catch (e) {
        if (!mounted) return;
        _stopLiveTimer();
        setState(() {
          _recording = false;
          _status = 'Mic failed: $e';
        });
      }
    }
  }

  Future<void> _scoreLiveTake(LiveTake take) async {
    final c = _card;
    if (c == null) return;
    if (take.pcmBytes.isEmpty) throw StateError('Recording too short');

    // Live PCM straight from RAM. Reference is the OS native voice
    // rendered on-device (cached); without it we score from your
    // audio + dictionary timing alone.
    final learnerPcm = take.pcmFloat;
    final expectedSecs = await _dict.expectedSecs(c.es);
    final ipa = await _dict.transcription(c.es);
    Float32List? refPcm;
    try {
      refPcm = await _voice.getReferencePcm(cardId: c.id, text: c.es);
    } catch (_) {
      refPcm = null;
    }
    final DspResult dsp;
    if (refPcm != null && refPcm.length >= 8000) {
      dsp = DspScorer.score(
        learner: learnerPcm,
        reference: refPcm,
        expectedSecs: expectedSecs,
      );
    } else {
      dsp = DspScorer.scoreNoReference(
        learner: learnerPcm,
        expectedSecs: expectedSecs,
      );
    }

    final recent = await _db.recentAttempts(c.id, limit: 3);
    final history = recent.reversed.map((a) => a.overall).toList();

    final res = await _laya.decide(
      expected: c.es,
      targetSound: c.targetSound,
      history: history,
      learnerWav: take.wavBytes,
      dsp: dsp,
      referenceIpa: ipa,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.logAttempt(
      AttemptsCompanion.insert(
        cardId: c.id,
        ts: now,
        path: res.path.name,
        overall: dsp.overall,
        fluency: dsp.fluency,
        completeness: dsp.completeness,
        prosody: dsp.prosody,
        distance: dsp.distance >= 0
            ? drift.Value(dsp.distance)
            : const drift.Value.absent(),
        layaJson: jsonEncode(res.decision.toJson()),
        confidence: res.decision.confidence,
      ),
    );
    await _srs.schedule(c.id, dsp.overall);
    await _db.recordSoundStat(c.targetSound, dsp.overall);

    if (!mounted) return;
    setState(() {
      _last = res;
      _status =
          '${res.decision.nextAction} · ${res.path.name} · ${take.duration.inMilliseconds / 1000.0}s live';
    });
  }

  @override
  void dispose() {
    _levelSub?.cancel();
    _liveTimer?.cancel();
    _rec.dispose();
    _voice.dispose();
    _db.close();
    super.dispose();
  }

  String _scoreLabel(int overall) {
    if (overall >= 85) return 'Excellent';
    if (overall >= 70) return 'Good match';
    if (overall >= 50) return 'Keep practicing';
    return 'Try again';
  }

  Widget _roundButton({
    required double size,
    required IconData icon,
    required VoidCallback? onPressed,
    Color? background,
    Color? foreground,
  }) {
    return SizedBox.square(
      dimension: size,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 2,
        ),
        child: Icon(icon, size: size * 0.4),
      ),
    );
  }

  Widget _pill(BuildContext context, String text, {bool highlight = false}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? colors.primaryContainer
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: highlight
              ? colors.onPrimaryContainer
              : colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _curvyCard(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final c = _card;
    final d = _last?.decision;
    final dsp = _last?.dsp;
    final tip = c == null ? '' : DrillService.soundTips[c.targetSound] ?? '';
    return Scaffold(
      backgroundColor: colors.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('SpeakCards'),
        centerTitle: true,
        backgroundColor: colors.surfaceContainerLow,
      ),
      body: c == null
          ? Center(child: Text(_status))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _pill(
                    context,
                    'Card ${(_i % _deck.length) + 1} of ${_deck.length}',
                  ),
                  const SizedBox(height: 16),
                  _curvyCard(
                    context,
                    child: Column(
                      children: [
                        Text(
                          c.es,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          c.en,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                        ),
                        if (_ipa.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '/$_ipa/',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: colors.primary,
                                  fontStyle: FontStyle.italic,
                                ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _pill(context, '${c.targetSound} · $tip',
                            highlight: true,),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _roundButton(
                        size: 60,
                        icon: Icons.volume_up_rounded,
                        onPressed: _listen,
                        background: colors.secondaryContainer,
                        foreground: colors.onSecondaryContainer,
                      ),
                      const SizedBox(width: 20),
                      _roundButton(
                        size: 88,
                        icon: _recording
                            ? Icons.stop_rounded
                            : Icons.mic_rounded,
                        onPressed: _scoring ? null : _toggleRecord,
                        background: _recording
                            ? colors.errorContainer
                            : colors.primary,
                        foreground: _recording
                            ? colors.onErrorContainer
                            : colors.onPrimary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_recording) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        width: 200,
                        child: LinearProgressIndicator(
                          value: _level.clamp(0.0, 1.0),
                          minHeight: 10,
                          backgroundColor: colors.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Listening… $_liveSecs s — tap stop when done',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ] else if (_scoring)
                    const CircularProgressIndicator()
                  else if (_last != null && d != null && dsp != null) ...[
                    _curvyCard(
                      context,
                      child: Column(
                        children: [
                          Text(
                            '${dsp.overall}%',
                            style: Theme.of(context)
                                .textTheme
                                .displayMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colors.primary,
                                ),
                          ),
                          Text(
                            _scoreLabel(dsp.overall),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _pill(context, 'Flow ${dsp.fluency}'),
                              _pill(context, 'Full ${dsp.completeness}'),
                              _pill(context, 'Tone ${dsp.prosody}'),
                            ],
                          ),
                          if (dsp.qualityFlag != 'ok') ...[
                            const SizedBox(height: 8),
                            Text(
                              dsp.qualityFlag == 'too_short'
                                  ? 'Too short — say the full phrase.'
                                  : 'Clipped — hold the mic farther.',
                              style: TextStyle(color: colors.error),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            dsp.distance >= 0
                                ? 'Matched the native voice (this device).'
                                : 'No native voice on this device — scored from your audio + dictionary.',
                            style:
                                const TextStyle(fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${d.feedbackEn}\n${d.feedbackEs}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() => _i++);
                                _refreshIpa();
                              },
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16,),
                              ),
                              child: const Text('Continue'),
                            ),
                          ),
                          TextButton(
                            onPressed: () {},
                            child: Text('Practice "${d.target}"'),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    Text(
                      _status,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
    );
  }
}
