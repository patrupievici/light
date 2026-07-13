import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/activity_kind.dart';
import '../../services/activity_calendar_store.dart';
import '../../services/feed_refresh_notifier.dart';
import '../../services/workout_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';

/// CONSISTENCY — 1:1 with the ZVELT handoff prototype (`sheetStreak`,
/// HTML 1096–1144): CURRENT/LONGEST cards, This month/Rate row, month
/// calendar with prev/next + tap-to-toggle days, Trained/Today legend,
/// Weekly-goal stepper, footer hint.
///
/// Trained days are real (completed workouts + cardio sessions + manual day
/// marks). Tapping toggles a MANUAL mark — days earned by a real session
/// can't be un-trained by tap.
class ConsistencyScreen extends StatefulWidget {
  const ConsistencyScreen({super.key});

  @override
  State<ConsistencyScreen> createState() => _ConsistencyScreenState();
}

class _ConsistencyScreenState extends State<ConsistencyScreen> {
  static const _kWeeklyGoalPref = 'zvelt_weekly_goal';

  final _store = ActivityCalendarStore();

  bool _loading = true;
  int _monthOffset = 0;
  int _weekGoal = 5;

  /// Days trained via a REAL session (workout / cardio) — not toggleable.
  Set<String> _sessionDays = const {};

  /// Days marked trained by hand (calendar store activities) — toggleable.
  Set<String> _manualDays = const {};

  SharedPreferences? _prefs;

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
      _safe(_store.loadManualSessions()),
      _safe(_store.loadAll()),
      _safe(SharedPreferences.getInstance()),
    ]);
    if (!mounted) return;

    final workouts = (results[0] as WorkoutsResponse?)?.data
            .where((w) => w.status != 'draft') ??
        const Iterable<WorkoutDto>.empty();
    final cardio =
        (results[1] as Map<String, List<ManualCardioSession>>?) ?? const {};
    final marks =
        (results[2] as Map<String, List<ActivityKind>>?) ?? const {};
    final prefs = results[3] as SharedPreferences?;

    setState(() {
      _loading = false;
      _prefs = prefs;
      _weekGoal = (prefs?.getInt(_kWeeklyGoalPref) ?? 5).clamp(1, 7);
      _sessionDays = {
        for (final w in workouts)
          _ymd(DateUtils.dateOnly((w.endedAt ?? w.startedAt).toLocal())),
        for (final e in cardio.entries)
          if (e.value.isNotEmpty) e.key,
      };
      _manualDays = {
        for (final e in marks.entries)
          if (e.value.isNotEmpty) e.key,
      };
    });
  }

  Set<String> get _trained => {..._sessionDays, ..._manualDays};

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int get _streakCur {
    final trained = _trained;
    var day = DateUtils.dateOnly(DateTime.now());
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

  int get _streakLongest {
    final trained = _trained;
    final today = DateUtils.dateOnly(DateTime.now());
    var longest = 0, run = 0;
    for (var i = 84; i >= 0; i--) {
      if (trained.contains(_ymd(today.subtract(Duration(days: i))))) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 0;
      }
    }
    return longest;
  }

  // ─── actions ──────────────────────────────────────────────────────────────

  Future<void> _toggleDay(DateTime day) async {
    final key = _ymd(day);
    if (_sessionDays.contains(key)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZveltTokens.rSm)),
        content: const Text('This day has a logged session'),
      ));
      return;
    }
    if (_manualDays.contains(key)) {
      // Remove every manual mark on that day.
      final all = await _store.loadAll();
      final count = all[key]?.length ?? 0;
      for (var i = count - 1; i >= 0; i--) {
        await _store.removeAt(key, i);
      }
      if (!mounted) return;
      setState(() => _manualDays = {..._manualDays}..remove(key));
    } else {
      await _store.add(key, ActivityKind.other);
      if (!mounted) return;
      setState(() => _manualDays = {..._manualDays, key});
    }
    FeedRefreshNotifier.instance.bump(RefreshScope.home);
  }

  Future<void> _setGoal(int delta) async {
    final next = (_weekGoal + delta).clamp(1, 7);
    if (next == _weekGoal) return;
    setState(() => _weekGoal = next);
    try {
      await _prefs?.setInt(_kWeeklyGoalPref, next);
    } catch (_) {}
    FeedRefreshNotifier.instance.bump(RefreshScope.home);
  }

  // ─── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: Column(
        children: [
          // Header — back · Consistency · spacer (HTML 1098–1102)
          Padding(
            padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 10),
            child: Row(
              children: [
                _circleBtn(AppIcons.angle_small_left, 36,
                    () => Navigator.of(context).maybePop()),
                const Spacer(),
                Text('Consistency',
                    style: ZType.bodyL.copyWith(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                const SizedBox(width: 36),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: ZveltTokens.brand))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                    children: [
                      _statCards(),
                      const SizedBox(height: 11),
                      _monthStatsRow(),
                      const SizedBox(height: 14),
                      _calendarCard(),
                      const SizedBox(height: 12),
                      _weeklyGoalCard(),
                      const SizedBox(height: 14),
                      Text(
                        'Tap any day to mark it as trained.',
                        textAlign: TextAlign.center,
                        style: ZType.bodyS.copyWith(
                            fontSize: 12, color: ZveltTokens.text3),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, double size, VoidCallback onTap) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ZveltTokens.chip,
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Icon(icon, size: size / 2, color: ZveltTokens.text),
        ),
      );

  // CURRENT / LONGEST cards (HTML 1104–1113)
  Widget _statCards() {
    Widget value(String v, String unit) => Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(v, style: ZType.stat.copyWith(fontSize: 30, height: 1)),
            const SizedBox(width: 5),
            Text(unit,
                style: ZType.bodyS.copyWith(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x33F58214), Color(0x0DF58214)],
              ),
              borderRadius: BorderRadius.circular(ZveltTokens.rBox),
              border: Border.all(color: const Color(0x4DF58214)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(AppIcons.flame,
                        size: 17, color: ZveltTokens.brand),
                    const SizedBox(width: 6),
                    Text('CURRENT',
                        style: ZType.eyebrow.copyWith(fontSize: 10.5)),
                  ],
                ),
                const SizedBox(height: 8),
                value('$_streakCur', 'day streak'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: ZveltTokens.surface2Grad,
              borderRadius: BorderRadius.circular(ZveltTokens.rBox),
              border: Border.all(color: ZveltTokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Text('LONGEST',
                      style: ZType.eyebrow.copyWith(fontSize: 10.5)),
                ),
                const SizedBox(height: 8),
                value('$_streakLongest', 'days'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  DateTime get _displayMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month + _monthOffset, 1);
  }

  (int count, int pct) get _monthStats {
    final disp = _displayMonth;
    final today = DateUtils.dateOnly(DateTime.now());
    final daysIn = DateUtils.getDaysInMonth(disp.year, disp.month);
    final trained = _trained;
    var count = 0;
    for (var d = 1; d <= daysIn; d++) {
      if (trained.contains(_ymd(DateTime(disp.year, disp.month, d)))) count++;
    }
    final isCur = disp.year == today.year && disp.month == today.month;
    final elapsed = isCur ? today.day : daysIn;
    final pct = elapsed == 0 ? 0 : (count / elapsed * 100).round();
    return (count, pct);
  }

  // This month / Rate row (HTML 1114–1117)
  Widget _monthStatsRow() {
    final (count, pct) = _monthStats;
    Widget tile(String label, String value, {bool accent = false}) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: ZveltTokens.surface2Grad,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ZveltTokens.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label,
                    style: ZType.bodyS.copyWith(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(value,
                    style: ZType.bodyL.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: accent ? ZveltTokens.brand : ZveltTokens.text)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        tile('This month', '$count days'),
        const SizedBox(width: 11),
        tile('Rate', '$pct%', accent: true),
      ],
    );
  }

  // Month calendar card (HTML 1118–1136)
  Widget _calendarCard() {
    const mon = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    final disp = _displayMonth;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        gradient: ZveltTokens.surfaceGrad,
        borderRadius: BorderRadius.circular(ZveltTokens.rCard),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _circleBtn(AppIcons.angle_small_left, 32,
                  () => setState(() => _monthOffset--)),
              Text('${mon[disp.month - 1]} ${disp.year}',
                  style: ZType.bodyL.copyWith(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              _circleBtn(AppIcons.angle_small_right, 32,
                  () => setState(() => _monthOffset++)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final d in const ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'])
                Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: ZType.monoXS.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: ZveltTokens.text3),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          _monthGrid(disp),
          const SizedBox(height: 14),
          Container(height: 1, color: ZveltTokens.hairline),
          const SizedBox(height: 13),
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [ZveltTokens.brand2, ZveltTokens.brandDeep],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text('Trained',
                  style: ZType.bodyS.copyWith(
                      fontSize: 11.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 16),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ZveltTokens.brand, width: 2),
                ),
              ),
              const SizedBox(width: 6),
              Text('Today',
                  style: ZType.bodyS.copyWith(
                      fontSize: 11.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _monthGrid(DateTime disp) {
    final today = DateUtils.dateOnly(DateTime.now());
    final firstWd = DateTime(disp.year, disp.month, 1).weekday % 7; // Su = 0
    final daysIn = DateUtils.getDaysInMonth(disp.year, disp.month);
    final trained = _trained;

    final cells = <Widget>[
      for (var i = 0; i < firstWd; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysIn; d++)
        _dayCell(DateTime(disp.year, disp.month, d), today, trained),
    ];

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: cells,
    );
  }

  Widget _dayCell(DateTime date, DateTime today, Set<String> trained) {
    final key = _ymd(date);
    final isTrained = trained.contains(key);
    final isToday = DateUtils.isSameDay(date, today);
    final isFuture = date.isAfter(today);

    final BoxDecoration deco;
    final Color color;
    final FontWeight weight;
    if (isTrained) {
      deco = const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ZveltTokens.brand2, ZveltTokens.brandDeep],
        ),
        boxShadow: ZveltTokens.glowSm,
      );
      color = ZveltTokens.onBrand;
      weight = FontWeight.w800;
    } else if (isToday) {
      deco = BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ZveltTokens.brand, width: 2),
      );
      color = ZveltTokens.brand;
      weight = FontWeight.w800;
    } else if (isFuture) {
      deco = const BoxDecoration(shape: BoxShape.circle);
      color = ZveltTokens.text4;
      weight = FontWeight.w600;
    } else {
      deco = BoxDecoration(shape: BoxShape.circle, color: ZveltTokens.chip);
      color = ZveltTokens.text3;
      weight = FontWeight.w600;
    }

    return InkWell(
      onTap: isFuture ? null : () => _toggleDay(date),
      customBorder: const CircleBorder(),
      child: Container(
        alignment: Alignment.center,
        decoration: deco,
        child: Text('${date.day}',
            style: ZType.bodyS.copyWith(
                fontSize: 13, color: color, fontWeight: weight)),
      ),
    );
  }

  // Weekly goal stepper (HTML 1137–1140)
  Widget _weeklyGoalCard() {
    Widget step(IconData icon, VoidCallback onTap) => InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ZveltTokens.chip,
              border: Border.all(color: ZveltTokens.border),
            ),
            child: Icon(icon, size: 14, color: ZveltTokens.text),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        gradient: ZveltTokens.surface2Grad,
        borderRadius: BorderRadius.circular(ZveltTokens.rBox),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Weekly goal',
                    style: ZType.bodyL.copyWith(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Days trained per week',
                    style: ZType.bodyS.copyWith(fontSize: 12)),
              ],
            ),
          ),
          step(AppIcons.minus, () => _setGoal(-1)),
          Container(
            constraints: const BoxConstraints(minWidth: 44),
            alignment: Alignment.center,
            child: Text('$_weekGoal',
                style: ZType.bodyL.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ZveltTokens.brand)),
          ),
          step(AppIcons.plus, () => _setGoal(1)),
        ],
      ),
    );
  }
}
