import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../srs/srs_service.dart';
import '../stats/stats_service.dart';

class _ProgressData {
  final int attempts;
  final double average;
  final int streak;
  final int due;
  final List<SoundStat> sounds;
  final List<int> weekly;
  final List<String> letters;
  const _ProgressData({
    required this.attempts,
    required this.average,
    required this.streak,
    required this.due,
    required this.sounds,
    required this.weekly,
    required this.letters,
  });
}

/// Progress tab: totals, streak, and per-sound mastery — all from the
/// on-device database the practice loop already maintains.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late final AppDb _db;
  late Future<_ProgressData> _future;

  @override
  void initState() {
    super.initState();
    _db = AppDb();
    _future = _load();
  }

  Future<_ProgressData> _load() async {
    final attempts = await _db.attemptCount();
    final average = await _db.averageOverall();
    final times = await _db.attemptTimes();
    final due = await SrsService(_db).dueNow().then((r) => r.length);
    final sounds = await _db.allSoundStats();
    return _ProgressData(
      attempts: attempts,
      average: average,
      streak: StatsService.calcStreak(times),
      due: due,
      sounds: sounds,
      weekly: StatsService.weeklyCounts(times),
      letters: StatsService.weeklyLetters(),
    );
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }

  Widget _statCard(
      BuildContext context, String label, String value, IconData icon,) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(height: 6),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Progress'),
        centerTitle: true,
        backgroundColor: colors.surfaceContainerLow,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => setState(() => _future = _load()),
          ),
        ],
      ),
      body: FutureBuilder<_ProgressData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _statCard(context, 'Tries', '${d.attempts}',
                        Icons.mic_rounded,),
                    const SizedBox(width: 12),
                    _statCard(context, 'Average',
                        d.attempts == 0 ? '–' : '${d.average.round()}%',
                        Icons.show_chart_rounded,),
                    const SizedBox(width: 12),
                    _statCard(context, 'Day streak', '${d.streak}',
                        Icons.local_fire_department_rounded,),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: d.sounds.isEmpty
                      ? const Text(
                          'Practice once and your per-sound mastery shows up here.',)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Sounds',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),),
                            const SizedBox(height: 12),
                            for (final s in d.sounds) ...[
                              Row(
                                children: [
                                  SizedBox(
                                    width: 72,
                                    child: Text(s.sound,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,),),
                                  ),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(999),
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween(
                                          begin: 0,
                                          end: (s.avg / 100)
                                              .clamp(0.0, 1.0),
                                        ),
                                        duration: const Duration(
                                            milliseconds: 800,),
                                        builder: (context, value, _) =>
                                            LinearProgressIndicator(
                                          value: value,
                                          minHeight: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 96,
                                    child: Text(
                                      '${s.avg.round()}% · ${StatsService.masteryLabel(s.avg)}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('This week',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 110,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < 7; i++)
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: FractionallySizedBox(
                                          widthFactor: 0.55,
                                          heightFactor: d.weekly[i] == 0
                                              ? 0.04
                                              : (d.weekly[i] /
                                                      d.weekly.reduce(
                                                          (a, b) => a > b
                                                              ? a
                                                              : b,))
                                                  .clamp(0.08, 1.0),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: i == 6
                                                  ? colors.primary
                                                  : colors.primary.withValues(
                                                      alpha: 0.45,),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(d.letters[i],
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color:
                                                  colors.onSurfaceVariant,
                                            ),),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    d.due == 0
                        ? 'All caught up — nothing due right now.'
                        : '$d.due card${d.due == 1 ? '' : 's'} due for review.',
                    style: TextStyle(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
