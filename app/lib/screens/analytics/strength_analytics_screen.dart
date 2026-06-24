import 'dart:math' as math;
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../services/workout_service.dart';
import '../../services/stats_charts_service.dart';
import '../../services/http_client.dart';
import '../../theme/zvelt_tokens.dart';
import 'progress_hub_screen.dart' show ZveltAreaChart, ZveltBarChart;

class StrengthAnalyticsScreen extends StatefulWidget {
  const StrengthAnalyticsScreen({super.key});

  @override
  State<StrengthAnalyticsScreen> createState() => _StrengthAnalyticsScreenState();
}

class _StrengthAnalyticsScreenState extends State<StrengthAnalyticsScreen> {
  final _workoutService = WorkoutService();
  final _statsService = StatsChartsService();

  List<ExerciseProgressionDto> _progressions = [];
  List<WeeklyEffortPoint> _weeklyEffort = [];
  bool _loading = true;
  String? _error;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pFuture = _workoutService.getMyProgressionHistory();
      final wFuture = _statsService.getWeeklyEffort(weeks: 8);
      final progressions = await pFuture;
      final weeklyEffort = await wFuture;
      if (!mounted) return;
      setState(() {
        _progressions = progressions;
        _weeklyEffort = weeklyEffort;
        if (_selectedId == null && progressions.isNotEmpty) {
          _selectedId = progressions.first.exerciseId;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyLoadError(e);
        _loading = false;
      });
    }
  }

  ExerciseProgressionDto? get _selected =>
      _progressions.where((p) => p.exerciseId == _selectedId).firstOrNull;

  // Best single-rep weight; falls back to Epley inverse from e1RM.
  double _prKg(ExerciseProgressionDto p) {
    if (p.dataPoints.isEmpty) return p.bestE1rmKg;
    double maxSingle = 0;
    for (final dp in p.dataPoints) {
      if (dp.reps == 1 && dp.weightKg > maxSingle) maxSingle = dp.weightKg;
    }
    if (maxSingle > 0) return maxSingle;
    // Invert Epley for 1 rep: weight = e1RM / (1 + 1/30)
    return p.bestE1rmKg / 1.0333;
  }

  // Change in e1RM vs ~30 days ago; falls back to first vs last.
  String _deltaThisMonth(ExerciseProgressionDto p) {
    if (p.dataPoints.length < 2) return '+0 kg';
    final monthAgo = DateTime.now().subtract(const Duration(days: 30));
    final sorted = List.of(p.dataPoints)..sort((a, b) => a.date.compareTo(b.date));
    ProgressionPointDto? refPoint;
    for (final dp in sorted) {
      final date = DateTime.tryParse(dp.date);
      if (date != null && date.isBefore(monthAgo)) refPoint = dp;
    }
    final refE1rm = refPoint?.e1rmKg ?? sorted.first.e1rmKg;
    final delta = p.bestE1rmKg - refE1rm;
    final sign = delta >= 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(1)} kg';
  }

  bool _deltaPositive(ExerciseProgressionDto p) {
    final s = _deltaThisMonth(p);
    return !s.startsWith('-');
  }

  String _prDate(ExerciseProgressionDto p) {
    if (p.dataPoints.isEmpty) return '—';
    final sorted = List.of(p.dataPoints)..sort((a, b) => b.e1rmKg.compareTo(a.e1rmKg));
    final date = DateTime.tryParse(sorted.first.date);
    if (date == null) return '—';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${m[date.month - 1]}';
  }

  IconData _iconFor(String name) {
    final l = name.toLowerCase();
    if (l.contains('bench') || l.contains('chest') || l.contains('fly')) return AppIcons.gym;
    if (l.contains('squat') || l.contains('lunge') || l.contains('leg')) return AppIcons.user;
    if (l.contains('overhead') || l.contains('ohp') || l.contains('shoulder') || l.contains('press')) return AppIcons.gym;
    return AppIcons.gym;
  }

  List<double> _historyPoints(ExerciseProgressionDto p) {
    if (p.dataPoints.isEmpty) return [0];
    final sorted = List.of(p.dataPoints)..sort((a, b) => a.date.compareTo(b.date));
    final pts = sorted.map((dp) => dp.e1rmKg).toList();
    return pts.length > 12 ? pts.sublist(pts.length - 12) : pts;
  }

  List<String> _historyLabels(ExerciseProgressionDto p) {
    if (p.dataPoints.isEmpty) return ['—', '—', 'Today'];
    final sorted = List.of(p.dataPoints)..sort((a, b) => a.date.compareTo(b.date));
    if (sorted.length == 1) return ['Start', '—', 'Today'];
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String fmt(String iso) {
      final d = DateTime.tryParse(iso);
      return d == null ? '—' : '${d.day} ${m[d.month - 1]}';
    }
    return [fmt(sorted.first.date), fmt(sorted[sorted.length ~/ 2].date), 'Today'];
  }

  List<double> _volumeNorm() {
    if (_weeklyEffort.isEmpty) return List.filled(8, 0);
    final vals = _weeklyEffort.map((w) => w.volumeKg).toList();
    final maxV = vals.reduce(math.max);
    if (maxV == 0) return List.filled(vals.length, 0);
    return vals.map((v) => v / maxV * 100).toList();
  }

  List<String> _weekLabels() {
    if (_weeklyEffort.isEmpty) return List.generate(8, (i) => 'W${i + 1}');
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return _weeklyEffort.map((w) {
      final d = DateTime.tryParse(w.weekStart);
      return d == null ? 'W' : '${d.day}/${m[d.month - 1].substring(0, 3)}';
    }).toList();
  }

  double _latestVolume() => _weeklyEffort.isEmpty ? 0 : _weeklyEffort.last.volumeKg;

  double _volumeDeltaPct() {
    if (_weeklyEffort.length < 2) return 0;
    final prev = _weeklyEffort[_weeklyEffort.length - 2].volumeKg;
    if (prev == 0) return 0;
    return (_weeklyEffort.last.volumeKg - prev) / prev * 100;
  }

  List<ExerciseProgressionDto> get _prList {
    final sorted = List.of(_progressions)
      ..sort((a, b) => b.bestE1rmKg.compareTo(a.bestE1rmKg));
    return sorted.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _SubHeader(
              title: 'Strength Analytics',
              onBack: () => Navigator.pop(context),
              right: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: ZveltTokens.gradBtn,
                  boxShadow: [BoxShadow(color: ZveltTokens.brand.withValues(alpha: 0.4), blurRadius: 14)],
                ),
                child: const Icon(AppIcons.bolt, color: Colors.white, size: 18),
              ),
              safeTop: top,
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: ZveltTokens.brand)),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.cloud_disabled, color: ZveltTokens.text2, size: 40),
                      const SizedBox(height: 12),
                      Text(_error ?? 'Could not load analytics.', style: ZType.bodyM.copyWith(color: ZveltTokens.text2), textAlign: TextAlign.center),
                      const SizedBox(height: ZveltTokens.s4),
                      Semantics(
                        button: true,
                        label: 'Retry loading',
                        child: GestureDetector(
                          onTap: _load,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s6, vertical: ZveltTokens.s3),
                            decoration: BoxDecoration(
                              gradient: ZveltTokens.gradBtn,
                              borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                            ),
                            child: Text('Retry', style: ZType.bodyS.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_progressions.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.gym, color: ZveltTokens.text2, size: 44),
                      const SizedBox(height: ZveltTokens.s4),
                      Text(
                        'Log a few workouts to see\nyour strength analytics.',
                        style: ZType.bodyM.copyWith(color: ZveltTokens.text2),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s8),
              sliver: SliverToBoxAdapter(child: _buildContent()),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final L = _selected;
    if (L == null) return const SizedBox.shrink();

    final histPoints = _historyPoints(L);
    final histLabels = _historyLabels(L);
    final prKg = _prKg(L);
    final nextKg = ((prKg / 2.5).ceil() * 2.5) + 2.5;
    final delta = _deltaThisMonth(L);
    final deltaPos = _deltaPositive(L);
    final volData = _volumeNorm();
    final weekLabels = _weekLabels();
    final latestVol = _latestVolume();
    final volDelta = _volumeDeltaPct();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Lift selector
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _progressions.map((p) {
              final sel = _selectedId == p.exerciseId;
              return Padding(
                padding: const EdgeInsets.only(right: ZveltTokens.s2),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedId = p.exerciseId),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4),
                    decoration: BoxDecoration(
                      gradient: sel ? ZveltTokens.gradBtn : null,
                      color: sel ? null : ZveltTokens.surface,
                      borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      border: sel ? null : Border.all(color: ZveltTokens.border),
                      boxShadow: sel ? [BoxShadow(color: ZveltTokens.brand.withValues(alpha: 0.35), blurRadius: 12)] : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_iconFor(p.exerciseName), size: 13, color: sel ? Colors.white : ZveltTokens.text2),
                        const SizedBox(width: ZveltTokens.s2),
                        Text(
                          p.exerciseName.length > 16 ? '${p.exerciseName.substring(0, 14)}…' : p.exerciseName.toUpperCase(),
                          style: ZType.monoXS.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.8, color: sel ? Colors.white : ZveltTokens.text2),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: ZveltTokens.s4),

        // e1RM hero
        _E1RMCard(
          e1rm: L.bestE1rmKg,
          delta: delta,
          deltaPositive: deltaPos,
          histPoints: histPoints,
          histLabels: histLabels,
        ),
        const SizedBox(height: 10),

        // PR + Try today row
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: AppIcons.trophy,
                iconColor: ZveltTokens.brand,
                overline: 'Current PR',
                value: prKg == prKg.roundToDouble()
                    ? prKg.toStringAsFixed(0)
                    : prKg.toStringAsFixed(1),
                unit: 'kg',
                subtitle: 'Set on ${_prDate(L)}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: AppIcons.sparkles,
                iconColor: ZveltTokens.info,
                overline: 'Try Today',
                value: '+${(nextKg - prKg).toStringAsFixed(1)}',
                unit: 'kg',
                subtitle: 'Target: ${nextKg.toStringAsFixed(1)} kg',
                valueColor: ZveltTokens.info,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // AI Insight
        _ZCard(
          accent: true,
          padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: ZveltTokens.gradBtn,
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                  boxShadow: [BoxShadow(color: ZveltTokens.brand.withValues(alpha: 0.4), blurRadius: 14)],
                ),
                child: const Icon(AppIcons.sparkles, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                    children: [
                      TextSpan(text: deltaPos ? "You're " : "You're "),
                      TextSpan(
                        text: delta,
                        style: TextStyle(
                          color: deltaPos ? ZveltTokens.success : ZveltTokens.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(text: ' vs last month on '),
                      TextSpan(text: L.exerciseName, style: TextStyle(color: ZveltTokens.text, fontWeight: FontWeight.w700)),
                      const TextSpan(text: '. Try '),
                      TextSpan(
                        text: '+${(nextKg - prKg).toStringAsFixed(1)}kg',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: ZveltTokens.brand),
                      ),
                      const TextSpan(text: ' on the bar today.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Weekly Tonnage (all exercises, real)
        _ZCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      'Weekly Tonnage',
                      style: ZType.h3.copyWith(fontSize: 20, color: ZveltTokens.text),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'LAST 8 WEEKS · ALL EXERCISES · KG',
                      style: ZType.eyebrow.copyWith(fontSize: 11, color: ZveltTokens.text2),
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(
                      latestVol.toStringAsFixed(0),
                      style: ZType.stat.copyWith(fontSize: 24, color: ZveltTokens.brand, height: 1),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      volDelta >= 0 ? '↑ +${volDelta.toStringAsFixed(1)}% vs prev' : '↓ ${volDelta.toStringAsFixed(1)}% vs prev',
                      style: ZType.eyebrow.copyWith(fontSize: 11, color: volDelta >= 0 ? ZveltTokens.success : ZveltTokens.error, fontWeight: FontWeight.w700),
                    ),
                  ]),
                ],
              ),
              const SizedBox(height: 16),
              Semantics(
                label:
                    'Weekly tonnage bar chart over the last ${volData.length} weeks, latest week ${latestVol.toStringAsFixed(0)} kilograms',
                child: ZveltBarChart(
                  data: volData,
                  height: 110,
                  activeIdx: volData.isNotEmpty ? volData.length - 1 : 0,
                  labels: weekLabels,
                  delay: const Duration(milliseconds: 200),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Top e1RMs
        Text(
          'PERSONAL RECORDS',
          style: ZType.eyebrow.copyWith(fontSize: 11, color: ZveltTokens.text2),
        ),
        const SizedBox(height: 10),
        _ZCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: List.generate(_prList.length, (i) {
              final pr = _prList[i];
              final prW = _prKg(pr);
              final prDelta = _deltaThisMonth(pr);
              final prPos = _deltaPositive(pr);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
                decoration: BoxDecoration(
                  // V2 light theme: white-alpha dividers are invisible here.
                  border: i < _prList.length - 1
                      ? Border(bottom: BorderSide(color: ZveltTokens.border))
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: ZveltTokens.brand.withValues(alpha: 0.12),
                        border: Border.all(color: ZveltTokens.brand.withValues(alpha: 0.25)),
                        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                      ),
                      child: const Icon(AppIcons.trophy, size: 16, color: ZveltTokens.brand),
                    ),
                    const SizedBox(width: ZveltTokens.s4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pr.exerciseName, style: ZType.bodyS.copyWith(fontWeight: FontWeight.w700, color: ZveltTokens.text)),
                          const SizedBox(height: 2),
                          Text('${_prDate(pr)} · ${pr.currentTier} tier', style: ZType.eyebrow.copyWith(fontSize: 11, color: ZveltTokens.text2, letterSpacing: 0.3)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: prW == prW.roundToDouble() ? prW.toStringAsFixed(0) : prW.toStringAsFixed(1),
                                style: ZType.stat.copyWith(fontSize: 18, color: ZveltTokens.text, height: 1),
                              ),
                              TextSpan(text: 'kg', style: ZType.monoXS.copyWith(fontSize: 11, color: ZveltTokens.text2, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(prDelta, style: ZType.eyebrow.copyWith(fontSize: 11, color: prPos ? ZveltTokens.success : ZveltTokens.error, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ─── e1RM Card ───────────────────────────────────────────────────────────────

class _E1RMCard extends StatelessWidget {
  const _E1RMCard({
    required this.e1rm,
    required this.delta,
    required this.deltaPositive,
    required this.histPoints,
    required this.histLabels,
  });
  final double e1rm;
  final String delta;
  final bool deltaPositive;
  final List<double> histPoints;
  final List<String> histLabels;

  @override
  Widget build(BuildContext context) {
    return _ZCard(
      accent: true,
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ESTIMATED 1RM',
                    style: ZType.eyebrow.copyWith(color: ZveltTokens.brand),
                  ),
                  const SizedBox(height: ZveltTokens.s1),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ShaderMask(
                        shaderCallback: (r) => ZveltTokens.gradBtn.createShader(r),
                        child: Text(
                          e1rm.round().toString(),
                          style: ZType.num_.copyWith(fontSize: 56, color: Colors.white, height: 1),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: ZveltTokens.s2, left: ZveltTokens.s2),
                        child: Text('kg', style: ZType.bodyM.copyWith(color: ZveltTokens.text2, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$delta this month',
                    style: ZType.monoXS.copyWith(fontSize: 11, color: deltaPositive ? ZveltTokens.success : ZveltTokens.error, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: ZveltTokens.brand.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                  border: Border.all(color: ZveltTokens.brand.withValues(alpha: 0.3)),
                  boxShadow: [BoxShadow(color: ZveltTokens.brand.withValues(alpha: 0.2), blurRadius: 14)],
                ),
                child: const Icon(AppIcons.bolt, size: 26, color: ZveltTokens.brand),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            label:
                'Estimated one-rep-max trend chart, ${e1rm.round()} kilograms, $delta this month',
            child: ZveltAreaChart(
              points: histPoints,
              height: 90,
              xLabels: histLabels,
              delay: const Duration(milliseconds: 200),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stat Card ───────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.overline,
    required this.value,
    required this.unit,
    required this.subtitle,
    this.valueColor,
  });

  final IconData icon;
  final Color iconColor;
  final String overline;
  final String value;
  final String unit;
  final String subtitle;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return _ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 8),
            Text(overline.toUpperCase(), style: ZType.eyebrow.copyWith(fontSize: 11, color: ZveltTokens.text2)),
          ]),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: ZType.stat.copyWith(fontSize: 28, color: valueColor ?? ZveltTokens.text, height: 1),
                ),
                TextSpan(text: unit, style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: ZType.eyebrow.copyWith(fontSize: 11, color: ZveltTokens.text2, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── Sub Header ──────────────────────────────────────────────────────────────

class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.title, required this.onBack, required this.right, required this.safeTop});
  final String title;
  final VoidCallback onBack;
  final Widget right;
  final double safeTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(ZveltTokens.s4, safeTop + ZveltTokens.s2, ZveltTokens.s4, ZveltTokens.s4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: GestureDetector(
              onTap: onBack,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ZveltTokens.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: ZveltTokens.border),
                ),
                child: Icon(AppIcons.angle_small_left, size: 16, color: ZveltTokens.text2),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: ZType.h4.copyWith(fontSize: 18, color: ZveltTokens.text)),
          ),
          right,
        ],
      ),
    );
  }
}

// ─── ZCard ───────────────────────────────────────────────────────────────────

class _ZCard extends StatelessWidget {
  const _ZCard({required this.child, this.padding = const EdgeInsets.all(ZveltTokens.s5), this.accent = false, this.glow = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool accent;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: accent ? ZveltTokens.surfaceTinted : ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: glow ? ZveltTokens.shadowHero : ZveltTokens.shadowCard,
      ),
      child: child,
    );
  }
}
