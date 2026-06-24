import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../services/_crash_reporter.dart';
import '../../services/health_service.dart';
import '../../services/stats_charts_service.dart';
import '../../services/workout_service.dart';
import '../../services/http_client.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/z/z_card.dart';
import '../../widgets/z/z_eyebrow.dart';
import '../../widgets/z/zvelt_charts.dart';

/// Which training/health metric the detail screen renders.
enum TrainingMetric { volume, strength, exercises, consistency, steps, calories }

/// Parametrized detail screen for the Progress-tab metrics (the design's
/// `METRIC_CONFIG` contract: hero · chart · breakdown · stats · "What it
/// measures" · coach insight) — sibling of MetricDetailScreen (strain /
/// recovery / sleep), but these metrics load their own history from the
/// stats endpoints.
///
/// Honest by construction: every number on screen is computed from fetched
/// history; an empty history renders an empty state, never a placeholder
/// chart.
class TrainingMetricDetailScreen extends StatefulWidget {
  const TrainingMetricDetailScreen({super.key, required this.metric});

  final TrainingMetric metric;

  @override
  State<TrainingMetricDetailScreen> createState() =>
      _TrainingMetricDetailScreenState();
}

class _TrainingMetricDetailScreenState
    extends State<TrainingMetricDetailScreen> {
  bool _loading = true;
  String? _error;
  _MetricData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Static copy per metric ────────────────────────────────────────────────

  String get _title {
    switch (widget.metric) {
      case TrainingMetric.volume:
        return 'Weekly volume';
      case TrainingMetric.strength:
        return 'Strength progression';
      case TrainingMetric.exercises:
        return 'Top exercises';
      case TrainingMetric.consistency:
        return 'Consistency';
      case TrainingMetric.steps:
        return 'Steps';
      case TrainingMetric.calories:
        return 'Active calories';
    }
  }

  Color get _color {
    switch (widget.metric) {
      case TrainingMetric.volume:
      case TrainingMetric.steps:
        return ZveltTokens.brand;
      case TrainingMetric.strength:
        return ZveltTokens.strain;
      case TrainingMetric.exercises:
      case TrainingMetric.calories:
        return ZveltTokens.cardio;
      case TrainingMetric.consistency:
        return ZveltTokens.success;
    }
  }

  String get _whatItMeasures {
    switch (widget.metric) {
      case TrainingMetric.volume:
        return 'Total work per week: weight × reps summed over every WORK '
            'set you logged (warm-ups and drop sets excluded). Volume is '
            'the simplest honest proxy for how much training stimulus a '
            'week actually delivered.';
      case TrainingMetric.strength:
        return 'Your estimated one-rep max (e1RM) over time, per lift — '
            'Epley formula: weight × (1 + reps / 30), computed from sets '
            'of 1–12 reps. Rising e1RM = you got stronger, regardless of '
            'which weight × rep combo you trained that day.';
      case TrainingMetric.exercises:
        return 'Where your training volume actually went in the last 30 '
            'days, ranked by total work (weight × reps) per exercise. A '
            'lopsided list is the fastest way to spot a neglected '
            'movement pattern.';
      case TrainingMetric.consistency:
        return 'Days with at least one logged session, over the last 365 '
            'days. Consistency predicts long-term progress better than '
            'any single workout — the chart shows sessions per month, '
            'the breakdown shows which weekdays carry your routine.';
      case TrainingMetric.steps:
        return 'Daily steps from your wearable (Apple Health / Health '
            'Connect), last 14 days. Steps are your non-training '
            'activity baseline — they feed 15% of the daily strain '
            'score.';
      case TrainingMetric.calories:
        return 'Active energy burned per day from your wearable, last 14 '
            'days. This is movement on top of your resting burn — it '
            'feeds 35% of the daily strain score.';
    }
  }

  // ── Data loading per metric ───────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final _MetricData data;
      switch (widget.metric) {
        case TrainingMetric.volume:
          data = await _loadVolume();
          break;
        case TrainingMetric.strength:
          data = await _loadStrength();
          break;
        case TrainingMetric.exercises:
          data = await _loadExercises();
          break;
        case TrainingMetric.consistency:
          data = await _loadConsistency();
          break;
        case TrainingMetric.steps:
          data = await _loadSteps();
          break;
        case TrainingMetric.calories:
          data = await _loadCalories();
          break;
      }
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e, st) {
      reportError(e, st, reason: 'metric-detail:${widget.metric.name}');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyLoadError(e);
      });
    }
  }

  static String _kg(double v) =>
      v >= 10000 ? '${(v / 1000).toStringAsFixed(1)}t' : '${v.round()}';

  static String _thousands(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      buf.write(s[i]);
      final left = s.length - 1 - i;
      if (left > 0 && left % 3 == 0) buf.write(',');
    }
    return buf.toString();
  }

  Future<_MetricData> _loadVolume() async {
    final weeks = await StatsChartsService().getWeeklyEffort(weeks: 12);
    if (weeks.isEmpty || weeks.every((w) => w.volumeKg <= 0)) {
      return _MetricData.empty(
          'No volume yet — log a workout and the chart starts here.');
    }
    // Oldest → newest for the chart.
    final pts = List.of(weeks)..sort((a, b) => a.weekStart.compareTo(b.weekStart));
    final maxV = pts.map((w) => w.volumeKg).reduce((a, b) => a > b ? a : b);
    final thisWeek = pts.last;
    final prior = pts.length >= 2 ? pts[pts.length - 2] : null;
    final delta = (prior != null && prior.volumeKg > 0)
        ? ((thisWeek.volumeKg - prior.volumeKg) / prior.volumeKg * 100)
        : null;

    final totalV = pts.fold<double>(0, (a, w) => a + w.volumeKg);
    final totalSets = pts.fold<int>(0, (a, w) => a + w.workSets);
    final best = pts.reduce((a, b) => a.volumeKg >= b.volumeKg ? a : b);

    final recent = pts.reversed.take(4).toList();
    return _MetricData(
      heroValue: _kg(thisWeek.volumeKg),
      heroUnit: 'kg-reps',
      heroSub: 'this week',
      chart: ZveltBarChart(
        data: [for (final w in pts) maxV > 0 ? w.volumeKg / maxV * 100 : 0.0],
        height: 130,
        activeIdx: pts.length - 1,
        labels: [
          for (var i = 0; i < pts.length; i++)
            i % 3 == 0 || i == pts.length - 1 ? _weekLabel(pts[i].weekStart) : ''
        ],
        delay: const Duration(milliseconds: 200),
      ),
      chartEyebrow: 'Last 12 weeks',
      breakdown: [
        for (final w in recent)
          _BreakdownItem(
            label: 'Week of ${_weekLabel(w.weekStart)}',
            value: '${_kg(w.volumeKg)} kg',
            detail: '${w.workSets} work sets',
            quality: maxV > 0 ? w.volumeKg / maxV : 0,
          ),
      ],
      stats: [
        ('12-wk total', '${_kg(totalV)} kg'),
        ('Avg / week', '${_kg(totalV / pts.length)} kg'),
        ('Best week', '${_kg(best.volumeKg)} kg'),
        ('Work sets', '$totalSets'),
      ],
      insight: delta == null
          ? 'First weeks of data — the trend gets meaningful from week 3.'
          : delta >= 10
              ? 'Volume up ${delta.round()}% vs last week — make sure recovery keeps pace.'
              : delta <= -10
                  ? 'Volume down ${delta.abs().round()}% vs last week — fine if planned, worth a look if not.'
                  : 'Volume steady vs last week (${delta >= 0 ? '+' : ''}${delta.round()}%) — consistency is the win here.',
    );
  }

  Future<_MetricData> _loadStrength() async {
    final progressions = await WorkoutService().getMyProgressionHistory();
    final withData =
        progressions.where((p) => p.dataPoints.length >= 2).toList()
          ..sort((a, b) => b.bestE1rmKg.compareTo(a.bestE1rmKg));
    if (withData.isEmpty) {
      return _MetricData.empty(
          'No e1RM history yet — log working sets (1-12 reps) on your main lifts and the progression appears here.');
    }
    final top = withData.first;
    final pts = List.of(top.dataPoints)
      ..sort((a, b) => a.date.compareTo(b.date));
    final first = pts.first.e1rmKg;
    final last = pts.last.e1rmKg;
    final deltaPct = first > 0 ? ((last - first) / first * 100) : 0.0;
    final maxBest = withData.first.bestE1rmKg;
    final totalLp = withData.fold<int>(0, (a, p) => a + p.currentLP);

    return _MetricData(
      heroValue: top.bestE1rmKg.toStringAsFixed(
          top.bestE1rmKg % 1 == 0 ? 0 : 1),
      heroUnit: 'kg e1RM',
      heroSub: '${top.exerciseName} · best estimate',
      chart: ZveltAreaChart(
        points: [for (final p in pts) p.e1rmKg],
        color: _color,
        height: 110,
        xLabels: [
          _monthDay(pts.first.date),
          if (pts.length > 2) _monthDay(pts[pts.length ~/ 2].date),
          _monthDay(pts.last.date),
        ],
        delay: const Duration(milliseconds: 200),
      ),
      chartEyebrow: '${top.exerciseName} · e1RM trend',
      breakdown: [
        for (final p in withData.take(5))
          _BreakdownItem(
            label: p.exerciseName,
            value: '${p.bestE1rmKg.toStringAsFixed(p.bestE1rmKg % 1 == 0 ? 0 : 1)} kg',
            detail: '${p.currentTier} · ${p.currentLP} LP',
            quality: maxBest > 0 ? p.bestE1rmKg / maxBest : 0,
          ),
      ],
      stats: [
        ('Lifts tracked', '${withData.length}'),
        ('Total LP', '$totalLp'),
        ('Top tier', withData.first.currentTier),
        ('Sessions', '${pts.length}'),
      ],
      insight: deltaPct >= 5
          ? '${top.exerciseName} e1RM is up ${deltaPct.round()}% over this period — real strength gain, not just a good day.'
          : deltaPct <= -5
              ? '${top.exerciseName} e1RM dipped ${deltaPct.abs().round()}% — common during volume blocks or after a break.'
              : 'e1RM is holding steady — strength maintenance while other qualities develop.',
    );
  }

  Future<_MetricData> _loadExercises() async {
    final top = await StatsChartsService().getTopExercises(days: 30, limit: 8);
    if (top.isEmpty) {
      return _MetricData.empty(
          'No exercises logged in the last 30 days yet.');
    }
    final maxV = top.map((e) => e.volumeKg).reduce((a, b) => a > b ? a : b);
    final totalV = top.fold<double>(0, (a, e) => a + e.volumeKg);
    final totalSets = top.fold<int>(0, (a, e) => a + e.workSets);
    final topShare = totalV > 0 ? (top.first.volumeKg / totalV * 100).round() : 0;

    return _MetricData(
      heroValue: top.first.name,
      heroUnit: '',
      heroSub:
          '${_kg(top.first.volumeKg)} kg volume · your #1 this month',
      heroIsText: true,
      chart: null, // breakdown bars carry the comparison better than a chart
      chartEyebrow: null,
      breakdown: [
        for (final e in top)
          _BreakdownItem(
            label: e.name,
            value: '${_kg(e.volumeKg)} kg',
            detail: '${e.workSets} work sets',
            quality: maxV > 0 ? e.volumeKg / maxV : 0,
          ),
      ],
      stats: [
        ('Exercises', '${top.length}'),
        ('Total volume', '${_kg(totalV)} kg'),
        ('Work sets', '$totalSets'),
        ('#1 share', '$topShare%'),
      ],
      insight: topShare >= 40
          ? '${top.first.name} carries $topShare% of your volume — great for specialization, but check nothing essential is starving.'
          : 'Volume is well spread across your lifts — balanced month.',
    );
  }

  Future<_MetricData> _loadConsistency() async {
    final daily = await StatsChartsService().getDailyTraining(days: 365);
    final active = daily.where((d) => d.sessions > 0).toList();
    if (active.isEmpty) {
      return _MetricData.empty(
          'No sessions in the last year yet — day one starts the streak.');
    }

    // Sessions per month (oldest → newest, up to 12 buckets).
    final byMonth = <String, int>{};
    for (final d in daily) {
      final dt = DateTime.tryParse(d.day);
      if (dt == null || d.sessions <= 0) continue;
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
      byMonth[key] = (byMonth[key] ?? 0) + 1;
    }
    final monthKeys = byMonth.keys.toList()..sort();
    final monthVals = [for (final k in monthKeys) byMonth[k]!.toDouble()];
    final maxMonth =
        monthVals.isEmpty ? 1.0 : monthVals.reduce((a, b) => a > b ? a : b);
    const monthNames = [
      'J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'
    ];

    // Streaks — daily list is newest-first per service; normalize.
    final activeDays = <String>{for (final d in active) d.day};
    int current = 0;
    var cursor = DateTime.now();
    // Today not trained yet shouldn't break the streak — start from
    // yesterday in that case.
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (!activeDays.contains(ymd(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (activeDays.contains(ymd(cursor))) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    int longest = 0, run = 0;
    final sortedDays = activeDays.toList()..sort();
    DateTime? prev;
    for (final s in sortedDays) {
      final dt = DateTime.tryParse(s);
      if (dt == null) continue;
      run = (prev != null && dt.difference(prev).inDays == 1) ? run + 1 : 1;
      if (run > longest) longest = run;
      prev = dt;
    }

    // Day-of-week breakdown.
    final dowCounts = List<int>.filled(7, 0);
    for (final d in active) {
      final dt = DateTime.tryParse(d.day);
      if (dt != null) dowCounts[dt.weekday - 1]++;
    }
    final maxDow =
        dowCounts.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);
    const dowNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    final topDows = List.generate(7, (i) => (i, dowCounts[i]))
      ..sort((a, b) => b.$2.compareTo(a.$2));

    final weeksCovered =
        (daily.length / 7).clamp(1, 53).toDouble();

    return _MetricData(
      heroValue: '${active.length}',
      heroUnit: 'days',
      heroSub: 'trained in the last year',
      chart: monthVals.length >= 2
          ? ZveltBarChart(
              data: [for (final v in monthVals) v / maxMonth * 100],
              height: 110,
              activeIdx: monthVals.length - 1,
              labels: [
                for (final k in monthKeys)
                  monthNames[int.parse(k.split('-')[1]) - 1]
              ],
              delay: const Duration(milliseconds: 200),
            )
          : null,
      chartEyebrow: 'Sessions per month',
      breakdown: [
        for (final (i, count) in topDows.take(4))
          _BreakdownItem(
            label: dowNames[i],
            value: '$count',
            detail: 'sessions on this weekday',
            quality: count / maxDow,
          ),
      ],
      stats: [
        ('Current streak', '$current d'),
        ('Longest streak', '$longest d'),
        ('Active days', '${active.length}'),
        ('Avg / week', (active.length / weeksCovered).toStringAsFixed(1)),
      ],
      insight: current >= 3
          ? "You're $current days deep — momentum is the rarest resource, protect it."
          : longest >= 7
              ? 'Your record is $longest straight days — the engine works, it just needs restarting.'
              : 'Routine beats intensity. Lock one fixed weekday first; the rest follow.',
    );
  }

  Future<_MetricData> _loadSteps() async {
    final history =
        await HealthService.instance.getDailyStepsHistory(days: 14);
    final pts = List.of(history)
      ..sort((a, b) => a.dayStart.compareTo(b.dayStart));
    if (pts.isEmpty || pts.every((d) => d.steps <= 0)) {
      return _MetricData.empty(
          'No step data — connect Apple Health / Health Connect and move a little.');
    }
    final maxSteps =
        pts.map((d) => d.steps).reduce((a, b) => a > b ? a : b);
    final total = pts.fold<int>(0, (a, d) => a + d.steps);
    final avg = (total / pts.length).round();
    final over10k = pts.where((d) => d.steps >= 10000).length;
    final today = pts.last;
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return _MetricData(
      heroValue: _thousands(today.steps),
      heroUnit: 'steps',
      heroSub: 'today',
      chart: ZveltBarChart(
        data: [for (final d in pts) maxSteps > 0 ? d.steps / maxSteps * 100 : 0.0],
        height: 110,
        activeIdx: pts.length - 1,
        labels: [for (final d in pts) days[d.dayStart.weekday - 1]],
        delay: const Duration(milliseconds: 200),
      ),
      chartEyebrow: 'Last ${pts.length} days',
      breakdown: [
        _BreakdownItem(
          label: 'Best day',
          value: _thousands(maxSteps),
          detail: 'your 14-day peak',
          quality: 1,
        ),
        _BreakdownItem(
          label: 'Daily average',
          value: _thousands(avg),
          detail: 'vs the 10,000 mark',
          quality: (avg / 10000).clamp(0.0, 1.0),
        ),
      ],
      stats: [
        ('14-day total', _thousands(total)),
        ('Avg / day', _thousands(avg)),
        ('Days ≥ 10k', '$over10k'),
        ('Today', _thousands(today.steps)),
      ],
      insight: avg >= 10000
          ? 'Averaging ${_thousands(avg)} a day — your activity baseline is genuinely high.'
          : avg >= 6000
              ? 'Solid baseline. A short evening walk closes the gap to 10k on most days.'
              : 'Low step days cap your strain score — even 20 minutes of walking moves this needle.',
    );
  }

  Future<_MetricData> _loadCalories() async {
    final history =
        await HealthService.instance.getDailyCaloriesBurnedHistory(days: 14);
    final pts = List.of(history)
      ..sort((a, b) => a.dayStart.compareTo(b.dayStart));
    if (pts.isEmpty || pts.every((d) => d.caloriesBurned <= 0)) {
      return _MetricData.empty(
          'No active-energy data from your wearable yet.');
    }
    final maxKcal = pts
        .map((d) => d.caloriesBurned)
        .reduce((a, b) => a > b ? a : b);
    final total = pts.fold<double>(0, (a, d) => a + d.caloriesBurned);
    final avg = total / pts.length;
    final today = pts.last;
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return _MetricData(
      heroValue: '${today.caloriesBurned.round()}',
      heroUnit: 'kcal',
      heroSub: 'active burn today',
      chart: ZveltBarChart(
        data: [
          for (final d in pts)
            maxKcal > 0 ? d.caloriesBurned / maxKcal * 100 : 0.0
        ],
        height: 110,
        activeIdx: pts.length - 1,
        labels: [for (final d in pts) days[d.dayStart.weekday - 1]],
        delay: const Duration(milliseconds: 200),
      ),
      chartEyebrow: 'Last ${pts.length} days',
      breakdown: [
        _BreakdownItem(
          label: 'Best day',
          value: '${maxKcal.round()} kcal',
          detail: 'your 14-day peak',
          quality: 1,
        ),
        _BreakdownItem(
          label: 'Daily average',
          value: '${avg.round()} kcal',
          detail: 'vs the 600 kcal strain target',
          quality: (avg / 600).clamp(0.0, 1.0),
        ),
      ],
      stats: [
        ('14-day total', '${total.round()}'),
        ('Avg / day', '${avg.round()}'),
        ('Best day', '${maxKcal.round()}'),
        ('Today', '${today.caloriesBurned.round()}'),
      ],
      insight: avg >= 600
          ? 'Averaging ${avg.round()} kcal of active burn — a genuinely active baseline.'
          : 'Active burn feeds 35% of your strain score — cardio days lift this fastest.',
    );
  }

  static String _weekLabel(String ymd) {
    final dt = DateTime.tryParse(ymd);
    if (dt == null) return '';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${m[dt.month - 1]} ${dt.day}';
  }

  static String _monthDay(String ymd) => _weekLabel(ymd);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(_title,
            style: const TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontWeight: FontWeight.w700,
            )),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: ZveltTokens.brand, strokeWidth: 2))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(ZveltTokens.s8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.cloud_disabled,
                            color: ZveltTokens.text2, size: 40),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: ZType.bodyM.copyWith(
                                color: ZveltTokens.text2)),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _buildBody(_data!),
    );
  }

  Widget _buildBody(_MetricData d) {
    if (d.emptyCopy != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ZveltTokens.s8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.chart_line_up, color: ZveltTokens.text3, size: 44),
              const SizedBox(height: 12),
              Text(
                d.emptyCopy!,
                textAlign: TextAlign.center,
                style: ZType.bodyM.copyWith(
                    color: ZveltTokens.text2, height: 1.45),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH, ZveltTokens.s2, ZveltTokens.screenPaddingH, ZveltTokens.s8),
      children: [
        // ── Hero ───────────────────────────────────────────────────────
        ZCard(
          color: ZveltTokens.surfaceTinted,
          shadow: ZveltTokens.shadowHero,
          padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5, vertical: ZveltTokens.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ZEyebrow(_title.toUpperCase()),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      d.heroValue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: d.heroIsText
                          ? ZType.h2.copyWith(
                              color: ZveltTokens.text, fontSize: 24)
                          : ZType.stat.copyWith(
                              fontSize: 42, color: ZveltTokens.text),
                    ),
                  ),
                  if (d.heroUnit.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: ZveltTokens.s2, bottom: ZveltTokens.s1),
                      child: Text(d.heroUnit,
                          style: ZType.monoS.copyWith(
                            color: ZveltTokens.text2,
                            fontWeight: FontWeight.w500,
                          )),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(d.heroSub,
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Chart ──────────────────────────────────────────────────────
        if (d.chart != null) ...[
          ZCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (d.chartEyebrow != null) ...[
                  ZEyebrow(d.chartEyebrow!),
                  const SizedBox(height: 14),
                ],
                Semantics(
                  label:
                      '${d.chartEyebrow ?? _title} chart, ${d.heroValue} ${d.heroUnit} ${d.heroSub}',
                  child: d.chart!,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Breakdown ──────────────────────────────────────────────────
        if (d.breakdown.isNotEmpty) ...[
          ZCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ZEyebrow('Breakdown'),
                const SizedBox(height: 12),
                for (var i = 0; i < d.breakdown.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  _BreakdownRow(item: d.breakdown[i], color: _color),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Stats 2×2 ──────────────────────────────────────────────────
        if (d.stats.isNotEmpty) ...[
          Row(children: [
            Expanded(child: _StatTile(stat: d.stats[0])),
            const SizedBox(width: 10),
            Expanded(
                child: d.stats.length > 1
                    ? _StatTile(stat: d.stats[1])
                    : const SizedBox()),
          ]),
          if (d.stats.length > 2) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _StatTile(stat: d.stats[2])),
              const SizedBox(width: 10),
              Expanded(
                  child: d.stats.length > 3
                      ? _StatTile(stat: d.stats[3])
                      : const SizedBox()),
            ]),
          ],
          const SizedBox(height: 12),
        ],

        // ── What it measures ───────────────────────────────────────────
        ZCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ZEyebrow('What it measures'),
              const SizedBox(height: 8),
              Text(_whatItMeasures,
                  style: ZType.bodyS.copyWith(
                      color: ZveltTokens.text2, height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Coach insight ──────────────────────────────────────────────
        ZCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                ),
                child: const Icon(AppIcons.brain_circuit,
                    color: ZveltTokens.brand, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Coach',
                        style: ZType.bodyS.copyWith(
                          fontWeight: FontWeight.w700,
                          color: ZveltTokens.text,
                        )),
                    const SizedBox(height: 3),
                    Text(d.insight,
                        style: ZType.bodyS.copyWith(
                            color: ZveltTokens.text2,
                            height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Internal models / sub-widgets ─────────────────────────────────────────

class _MetricData {
  _MetricData({
    required this.heroValue,
    required this.heroUnit,
    required this.heroSub,
    required this.chart,
    required this.chartEyebrow,
    required this.breakdown,
    required this.stats,
    required this.insight,
    this.heroIsText = false,
  }) : emptyCopy = null;

  _MetricData.empty(this.emptyCopy)
      : heroValue = '',
        heroUnit = '',
        heroSub = '',
        chart = null,
        chartEyebrow = null,
        breakdown = const [],
        stats = const [],
        insight = '',
        heroIsText = false;

  final String heroValue;
  final String heroUnit;
  final String heroSub;
  final bool heroIsText;
  final Widget? chart;
  final String? chartEyebrow;
  final List<_BreakdownItem> breakdown;
  final List<(String, String)> stats;
  final String insight;
  final String? emptyCopy;
}

class _BreakdownItem {
  const _BreakdownItem({
    required this.label,
    required this.value,
    required this.detail,
    required this.quality,
  });
  final String label;
  final String value;
  final String detail;
  final double quality;
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.item, required this.color});
  final _BreakdownItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodyS.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ZveltTokens.text,
                  )),
            ),
            Text(item.value,
                style: ZType.monoS.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                )),
          ],
        ),
        const SizedBox(height: ZveltTokens.s1),
        Text(item.detail,
            style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                color: ZveltTokens.text3,
                fontSize: 11)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          child: LinearProgressIndicator(
            value: item.quality.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: color.withValues(alpha: 0.14),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});
  final (String, String) stat;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ZEyebrow(stat.$1),
          const SizedBox(height: 8),
          Text(stat.$2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZType.stat.copyWith(fontSize: 20, color: ZveltTokens.text)),
        ],
      ),
    );
  }
}
