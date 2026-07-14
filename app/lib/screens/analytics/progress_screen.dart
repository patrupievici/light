import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/activity_kind.dart';
import '../../services/activity_calendar_store.dart';
import '../../services/nutrition_service.dart';
import '../../services/workout_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';

/// PROGRESS — 1:1 with the ZVELT handoff prototype (`isProg`, HTML 592–615):
/// header + Week/Month segmented toggle, "Calories burned" bar card with the
/// period delta, then a 2×2 stat grid (Weight / Workouts / Streak / Avg
/// intake). All values are real app data.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  static const _kWeeklyGoalPref = 'zvelt_weekly_goal';

  bool _loading = true;
  bool _weekPeriod = true;

  /// kcal burned per LOCAL day key, cardio MET estimates (the app's only
  /// honest burn source — gym sessions record no calories).
  Map<String, int> _burnByDay = const {};
  int _workoutsThisWeek = 0;
  int _weekGoal = 5;
  int _streakCur = 0;
  int _streakLongest = 0;
  double? _weightKg;
  double? _weightDeltaWeek;
  int? _avgIntake;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<T?> _safe<T>(Future<T> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _safe(WorkoutService().getWorkouts(limit: 50)),
      _safe(ActivityCalendarStore().loadManualSessions()),
      _safe(NutritionService.instance.loadNutritionHistory(days: 60)),
      _safe(SharedPreferences.getInstance()),
      // Manual day marks (Consistency calendar) — unioned into trained days
      // so the Streak tile matches ConsistencyScreen.
      _safe(ActivityCalendarStore().loadAll()),
    ]);
    if (!mounted) return;

    final workouts = (results[0] as WorkoutsResponse?)?.data
            .where((w) => w.status != 'draft')
            .toList() ??
        const <WorkoutDto>[];
    final cardio =
        (results[1] as Map<String, List<ManualCardioSession>>?) ?? const {};
    final nutrition =
        (results[2] as List<NutritionDaySnapshot>?) ?? const [];
    final prefs = results[3] as SharedPreferences?;
    final marks =
        (results[4] as Map<String, List<ActivityKind>>?) ?? const {};

    // Weight logs first — the MET burn estimate below uses the user's real
    // bodyweight (fallback 70 kg only when no weight was ever logged).
    final weights = [
      for (final d in nutrition)
        if (d.weightKg != null && d.weightKg! > 0) (d.date, d.weightKg!),
    ];
    final burnBodyweight = weights.isNotEmpty ? weights.last.$2 : 70.0;

    final burn = <String, int>{};
    cardio.forEach((day, sessions) {
      var kcal = 0;
      for (final s in sessions) {
        final mins = s.durationMin;
        if (mins == null || mins <= 0) continue;
        final met = switch (s.kind) {
          ActivityKind.cycle => 6.0,
          ActivityKind.swim => 7.0,
          ActivityKind.walk => 4.0,
          _ => 9.0,
        };
        kcal += (met * burnBodyweight * (mins / 60)).round();
      }
      if (kcal > 0) burn[day] = (burn[day] ?? 0) + kcal;
    });

    final trained = <String>{
      for (final w in workouts)
        _ymd(DateUtils.dateOnly((w.endedAt ?? w.startedAt).toLocal())),
      for (final e in cardio.entries)
        if (e.value.isNotEmpty) e.key,
      for (final e in marks.entries)
        if (e.value.isNotEmpty) e.key,
    };

    final today = DateUtils.dateOnly(DateTime.now());
    final sunday = today.subtract(Duration(days: today.weekday % 7));
    var workoutsThisWeek = 0;
    for (var i = 0; i < 7; i++) {
      final d = sunday.add(Duration(days: i));
      if (!d.isAfter(today) && trained.contains(_ymd(d))) workoutsThisWeek++;
    }

    // Weight: latest log + delta over the trailing 7 days.
    double? weight;
    double? weightDelta;
    if (weights.isNotEmpty) {
      weight = weights.last.$2;
      final weekAgo = today.subtract(const Duration(days: 7));
      final inWeek = [
        for (final (date, kg) in weights)
          if (!DateUtils.dateOnly(date).isBefore(weekAgo)) kg,
      ];
      if (inWeek.length >= 2) weightDelta = inWeek.last - inWeek.first;
    }

    // Avg intake: mean of the last 7 logged days (calories > 0).
    final loggedDays = [
      for (final d in nutrition)
        if (d.calories > 0) d.calories,
    ];
    int? avgIntake;
    if (loggedDays.isNotEmpty) {
      final tail = loggedDays.length > 7
          ? loggedDays.sublist(loggedDays.length - 7)
          : loggedDays;
      avgIntake =
          (tail.fold<double>(0, (a, b) => a + b) / tail.length).round();
    }

    setState(() {
      _loading = false;
      _burnByDay = burn;
      _workoutsThisWeek = workoutsThisWeek;
      _weekGoal = (prefs?.getInt(_kWeeklyGoalPref) ?? 5).clamp(1, 7);
      _streakCur = _currentStreak(trained, today);
      _streakLongest = _longestStreak(trained, today);
      _weightKg = weight;
      _weightDeltaWeek = weightDelta;
      _avgIntake = avgIntake;
    });
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int _currentStreak(Set<String> trained, DateTime today) {
    var day = today;
    if (!trained.contains(_ymd(day))) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (trained.contains(_ymd(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static int _longestStreak(Set<String> trained, DateTime today) {
    var longest = 0, run = 0;
    for (var i = 84; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      if (trained.contains(_ymd(d))) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 0;
      }
    }
    return longest;
  }

  // ─── period data ──────────────────────────────────────────────────────────

  int _burnOn(DateTime d) => _burnByDay[_ymd(d)] ?? 0;

  /// Week: last 7 days (label = weekday letter). Month: last 7 weeks
  /// (label = week-start day of month). Highlight = current bucket.
  List<({String label, int kcal})> get _bars {
    final today = DateUtils.dateOnly(DateTime.now());
    if (_weekPeriod) {
      const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      return [
        for (var i = 6; i >= 0; i--)
          () {
            final d = today.subtract(Duration(days: i));
            return (label: letters[d.weekday - 1], kcal: _burnOn(d));
          }(),
      ];
    }
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return [
      for (var w = 6; w >= 0; w--)
        () {
          final start = monday.subtract(Duration(days: 7 * w));
          var kcal = 0;
          for (var i = 0; i < 7; i++) {
            kcal += _burnOn(start.add(Duration(days: i)));
          }
          return (label: '${start.day}/${start.month}', kcal: kcal);
        }(),
    ];
  }

  /// "+8% vs last" — current period total vs the previous period.
  String? get _delta {
    final today = DateUtils.dateOnly(DateTime.now());
    final span = _weekPeriod ? 7 : 28;
    var cur = 0, prev = 0;
    for (var i = 0; i < span; i++) {
      cur += _burnOn(today.subtract(Duration(days: i)));
      prev += _burnOn(today.subtract(Duration(days: span + i)));
    }
    if (prev == 0) return null;
    final pct = ((cur - prev) / prev * 100).round();
    return '${pct >= 0 ? '+' : ''}$pct% vs last';
  }

  // ─── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: ZveltTokens.brand))
          : ListView(
              padding: EdgeInsets.fromLTRB(0, topPad + 8, 0, 30),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.of(context).maybePop(),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ZveltTokens.chip,
                            border: Border.all(color: ZveltTokens.border),
                          ),
                          child: Icon(AppIcons.angle_small_left,
                              size: 18, color: ZveltTokens.text),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('Progress', style: ZType.h1.copyWith(fontSize: 24)),
                      const Spacer(),
                      _segToggle(),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _caloriesCard(),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _statGrid(),
                ),
              ],
            ),
    );
  }

  // Week / Month segmented toggle (HTML 596)
  Widget _segToggle() {
    Widget seg(String label, bool active, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: active ? ZveltTokens.brand : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              label,
              style: ZType.bodyS.copyWith(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? ZveltTokens.onBrand : ZveltTokens.text3,
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ZveltTokens.chip,
        borderRadius: BorderRadius.circular(ZveltTokens.rControl),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg('Week', _weekPeriod, () => setState(() => _weekPeriod = true)),
          const SizedBox(width: 3),
          seg('Month', !_weekPeriod, () => setState(() => _weekPeriod = false)),
        ],
      ),
    );
  }

  // Calories burned card (HTML 599–606)
  Widget _caloriesCard() {
    final bars = _bars;
    final maxKcal =
        bars.fold<int>(1, (a, b) => b.kcal > a ? b.kcal : a);
    final delta = _delta;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: ZveltTokens.surfaceGrad,
        borderRadius: BorderRadius.circular(ZveltTokens.rCard),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Calories burned',
                  style: ZType.bodyM.copyWith(fontSize: 14)),
              const Spacer(),
              if (delta != null)
                Text(delta,
                    style: ZType.bodyS.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ZveltTokens.brand)),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 118,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < bars.length; i++) ...[
                  Expanded(
                    child: _bar(
                      bars[i],
                      maxKcal,
                      highlight: i == bars.length - 1,
                    ),
                  ),
                  if (i < bars.length - 1) const SizedBox(width: 9),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(({String label, int kcal}) b, int maxKcal,
      {required bool highlight}) {
    final frac = maxKcal <= 0 ? 0.0 : b.kcal / maxKcal;
    final h = (frac * 96).clamp(6.0, 96.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: double.infinity,
          height: h,
          decoration: BoxDecoration(
            gradient: highlight
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [ZveltTokens.brand2, ZveltTokens.brandDeep],
                  )
                : null,
            color: highlight ? null : ZveltTokens.track,
            borderRadius: BorderRadius.circular(6),
            boxShadow: highlight ? ZveltTokens.glowSm : null,
          ),
        ),
        const SizedBox(height: 8),
        Text(b.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ZType.monoXS.copyWith(
                fontSize: 10.5, color: ZveltTokens.text3)),
      ],
    );
  }

  // 2×2 stat grid (HTML 608–613)
  Widget _statGrid() {
    final toGo = (_weekGoal - _workoutsThisWeek).clamp(0, 7);
    final delta = _weightDeltaWeek;
    final deltaLabel = delta == null
        ? 'No weight logs this week'
        : '${delta >= 0 ? '+' : '−'}${delta.abs().toStringAsFixed(1)} kg this week';

    Widget tile({
      required IconData icon,
      required String title,
      required String value,
      String? unit,
      required String sub,
      bool subAccent = false,
    }) =>
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: ZveltTokens.surface2Grad,
            borderRadius: BorderRadius.circular(ZveltTokens.rBox),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: ZveltTokens.brand),
                  const SizedBox(width: 8),
                  Text(title,
                      style: ZType.bodyS.copyWith(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child:
                          Text(value, style: ZType.stat.copyWith(fontSize: 24)),
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 5),
                    Text(unit,
                        style: ZType.bodyS.copyWith(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZType.bodyS.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: subAccent ? ZveltTokens.brand : ZveltTokens.text2,
                ),
              ),
            ],
          ),
        );

    // IntrinsicHeight: equal-height tiles WITHOUT a bare stretch Row — stretch
    // under a ListView's unbounded height blanks the screen in release builds
    // (flutter-layout-release-blank).
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: tile(
                  icon: AppIcons.chart_line_up,
                  title: 'Weight',
                  value:
                      _weightKg == null ? '—' : _weightKg!.toStringAsFixed(1),
                  unit: 'kg',
                  sub: deltaLabel,
                  subAccent: delta != null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: tile(
                  icon: AppIcons.gym,
                  title: 'Workouts',
                  value: '$_workoutsThisWeek',
                  unit: '/ $_weekGoal planned',
                  sub: toGo == 0
                      ? 'Goal reached'
                      : '$toGo session${toGo == 1 ? '' : 's'} to go',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: tile(
                  icon: AppIcons.flame,
                  title: 'Streak',
                  value: '$_streakCur',
                  unit: 'days',
                  sub: 'Best: $_streakLongest days',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: tile(
                  icon: AppIcons.bolt,
                  title: 'Avg intake',
                  value: _avgIntake == null ? '—' : _fmtInt(_avgIntake!),
                  sub: 'kcal / day',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmtInt(int v) {
    final s = '$v';
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '$buf';
  }
}
