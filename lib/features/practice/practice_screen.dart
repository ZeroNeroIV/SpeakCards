import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/db.dart';
import '../cards/card_model.dart';
import '../laya/laya_client.dart';
import '../scoring/dsp_scorer.dart';
import '../srs/drill_service.dart';
import '../srs/srs_service.dart';
import 'recorder_service.dart';

/// Main loop: show card → listen → live mic stream → score in-RAM PCM →
/// LAYA next action → save. No WAV files: mic PCM never touches disk.
/// Honest labels: "match vs reference (this device)" or
/// "from your audio alone" when no reference WAV is bundled.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});
  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final _cards = CardRepository();
  final _rec = RecorderService();
  final _player = AudioPlayer();
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
    try {
      final all = await _cards.loadAll();
      for (final c in all) {
        await _db.upsertCard(
          CardsCompanion(
            id: drift.Value(c.id),
            es: drift.Value(c.es),
            en: drift.Value(c.en),
            audioPath: drift.Value(c.audioPath),
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Startup failed: $e');
    }
  }

  CardModel? get _card => _deck.isEmpty ? null : _deck[_i % _deck.length];

  Future<void> _listen() async {
    final c = _card;
    if (c == null) return;
    try {
      await _player.setAsset(c.audioPath);
      await _player.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Reference audio missing: ${c.audioPath}');
    }
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

    // Live PCM straight from RAM — no file read, no WAV strip.
    final learnerPcm = take.pcmFloat;
    final wavBytes = take.wavBytes;

    Float32List? refPcm;
    try {
      final refData = await rootBundle.load(c.audioPath);
      final refBytes = refData.buffer.asUint8List();
      refPcm = AudioPrep.toFloat32(AudioPrep.pcm16FromWav(refBytes));
    } catch (_) {
      refPcm = null;
    }

    final expectedSecs = DspScorer.expectedSecsFor(c.es);
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
      learnerWav: wavBytes,
      dsp: dsp,
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
    _player.dispose();
    _db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _card;
    final d = _last?.decision;
    final dsp = _last?.dsp;
    final tip = c == null ? '' : DrillService.soundTips[c.targetSound] ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('SpeakCards · Español')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: c == null
            ? Text(_status)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(c.es, style: Theme.of(context).textTheme.headlineSmall),
                  Text(c.en, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Focus: ${c.targetSound} · $tip',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _listen,
                        child: const Text('Listen'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _scoring ? null : _toggleRecord,
                        child: Text(
                          _scoring
                              ? 'Scoring…'
                              : _recording
                                  ? 'Stop ($_liveSecs s)'
                                  : 'Record',
                        ),
                      ),
                    ],
                  ),
                  if (_recording) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.mic, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _level.clamp(0.0, 1.0),
                              minHeight: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${(_level * 100).round()}%'),
                      ],
                    ),
                    const Text(
                      'Live mic stream — nothing saved to disk.',
                      style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_scoring)
                    const LinearProgressIndicator()
                  else if (_last != null && d != null && dsp != null) ...[
                    Text(
                      'Match ${dsp.overall}% · '
                      'Fluency ${dsp.fluency} · '
                      'Complete ${dsp.completeness} · '
                      'Natural ${dsp.prosody}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (dsp.qualityFlag != 'ok')
                      Text(
                        dsp.qualityFlag == 'too_short'
                            ? 'Too short — speak the full phrase.'
                            : 'Clipped — hold the mic a bit farther.',
                        style: const TextStyle(color: Colors.orange),
                      ),
                    Text(
                      dsp.distance >= 0
                          ? 'Matched reference (DTW ${dsp.distance.toStringAsFixed(2)}, this device).'
                          : 'No reference WAV bundled — scored live from your audio (this device).',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                    Text('${d.feedbackEn}\n${d.feedbackEs}'),
                    Text('Next: ${d.nextAction} → ${d.target} '
                        '(confidence ${d.confidence}/4, via ${_last!.path.name})'),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {},
                          child: Text('Practice "${d.target}"'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _i++),
                          child: const Text('Continue'),
                        ),
                      ],
                    ),
                  ] else
                    Text(_status),
                ],
              ),
      ),
    );
  }
}
