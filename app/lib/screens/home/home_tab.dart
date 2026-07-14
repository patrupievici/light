import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/activity_kind.dart';
import '../../services/activity_calendar_store.dart';
import '../../services/background_tracking_service.dart';
import '../../services/feed_refresh_notifier.dart';
import '../../services/nutrition_service.dart';
import '../../services/profile_service.dart';
import '../../services/stats_charts_service.dart';
import '../../services/workout_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/muscle_map_widget.dart';
import '../../widgets/zvelt_main_nav_bar.dart';
import '../activity/cardio_history_screen.dart';
import '../analytics/progress_screen.dart';
import '../outdoor/outdoor_track_screen.dart';
import 'consistency_screen.dart';

/// HOME / TODAY — 1:1 with the ZVELT handoff prototype (`zvelt-home-ux`).
///
/// Blocks, in order (nothing else):
///  ① Header — "Today ▾" (day menu) · avatar (→ Profile) · streak badge
///  ② Cardio resume banner — conditional; shows only while
///     [BackgroundTrackingService] reports a live in-process session (the
///     prototype rule is "never show when inactive")
///  ③ START A SESSION eyebrow + History › (→ Cardio history)
///  ④ Run / Ride tiles (→ Cardio tracking)
///  ⑤⑥ Consistency title + card (→ Streak Calendar)
///  ⑦⑧ Last 14 Workouts title + Volume card (→ Progress)
///  ⑨ Stat trio — Avg Session · New PRs · Avg Burn
///  ⑩ Bodyweight card — value + add (real editor sheet)
///  ⑪⑫ Muscles title + muscle-map card (Front/Back toggle)
///
/// All numbers are REAL app data (workouts, cardio store, PRs, nutrition
/// history) — the prototype's demo values are replaced per its own logic.md.
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    this.onOpenProfile,
    this.onOpenNotifications,
    this.onOpenFood,
    this.onOpenFeed,
  });

  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenFood;
  final VoidCallback? onOpenFeed;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _profile = ProfileService();
  final _workouts = WorkoutService();
  final _stats = StatsChartsService();
  final _nutrition = NutritionService.instance;

  static const _kWeeklyGoalPref = 'zvelt_weekly_goal';

  bool _loading = true;
  bool _dayMenuOpen = false;

  String _avatarInitial = 'A';
  Set<String> _trainedDayKeys = const {};
  int _streakCur = 0;
  int _streakLongest = 0;
  int _weekGoal = 5;
  _Last14 _last14 = _Last14.empty;
  int _newPrs = 0;
  int? _avgBurnCal;
  double? _bodyweightKg;
  List<double> _bodyweightTrend = const [];

  // ② Live cardio session (resume banner) — real tracking-service state only.
  StreamSubscription<TrackingStats>? _liveSub;
  TrackingStats? _liveStats;

  @override
  void initState() {
    super.initState();
    FeedRefreshNotifier.instance
        .notifier(RefreshScope.home)
        .addListener(_onHomeBump);
    final snap = BackgroundTrackingService.instance.getCurrentStats();
    if (snap.isTracking) _liveStats = snap;
    _liveSub = BackgroundTrackingService.instance.statsStream.listen((s) {
      if (mounted) setState(() => _liveStats = s);
    });
    _load();
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    FeedRefreshNotifier.instance
        .notifier(RefreshScope.home)
        .removeListener(_onHomeBump);
    super.dispose();
  }

  void _onHomeBump() {
    if (!mounted || _loading) return;
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
    if (!mounted) return;
    setState(() => _loading = true);

    final results = await Future.wait([
      _safe(_profile.getMe()),
      // Same source of truth History uses (GET /v1/workouts; page-1 cached
      // offline in WorkoutService).
      _safe(_workouts.getWorkouts(limit: 50)),
      _safe(ActivityCalendarStore().loadManualSessions()),
      _safe(_stats.getRecentPrs(days: 30)),
      _safe(_nutrition.loadNutritionHistory(days: 14)),
      _safe(SharedPreferences.getInstance()),
      // Manual day marks (Consistency calendar) — same trained-day source
      // ConsistencyScreen unions in, so streak math never desyncs.
      _safe(ActivityCalendarStore().loadAll()),
    ]);
    if (!mounted) return;

    final me = results[0] as Map<String, dynamic>?;
    final workoutsRes = results[1] as WorkoutsResponse?;
    final cardioByDay =
        (results[2] as Map<String, List<ManualCardioSession>>?) ?? const {};
    final recentPrs = (results[3] as List<RecentPr>?) ?? const <RecentPr>[];
    final nutritionHistory = (results[4] as List<NutritionDaySnapshot>?) ??
        const <NutritionDaySnapshot>[];
    final prefs = results[5] as SharedPreferences?;
    final dayMarks =
        (results[6] as Map<String, List<ActivityKind>>?) ?? const {};

    // Trained days = completed gym sessions (LOCAL day) + cardio days +
    // manual calendar marks (kept in sync with ConsistencyScreen).
    final completedWorkouts = (workoutsRes?.data ?? const <WorkoutDto>[])
        .where((w) => w.status != 'draft')
        .toList()
      ..sort((a, b) =>
          (b.endedAt ?? b.startedAt).compareTo(a.endedAt ?? a.startedAt));
    final trainedKeys = <String>{
      for (final w in completedWorkouts)
        _ymd(DateUtils.dateOnly((w.endedAt ?? w.startedAt).toLocal())),
      for (final e in cardioByDay.entries)
        if (e.value.isNotEmpty) e.key,
      for (final e in dayMarks.entries)
        if (e.value.isNotEmpty) e.key,
    };

    final today = DateUtils.dateOnly(DateTime.now());
    final profile = me?['profile'] as Map<String, dynamic>?;
    final name = (profile?['displayName'] as String?)?.trim();
    final weightTrend = [
      for (final d in nutritionHistory)
        if (d.weightKg != null && d.weightKg! > 0) d.weightKg!,
    ];
    final profileBodyweight = _asDouble(profile?['bodyweightKg']);

    // Avg Burn — MET estimate per cardio session (last 14 sessions), same
    // formula as ProgressScreen's "Calories burned" chart, with the user's
    // real bodyweight (fallback 70 kg only when no weight exists).
    final burnBodyweight =
        weightTrend.isNotEmpty ? weightTrend.last : (profileBodyweight ?? 70.0);
    final cardioSessions = <(String, ManualCardioSession)>[
      for (final e in cardioByDay.entries)
        for (final s in e.value) (e.key, s),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    var burnTotal = 0.0;
    var burnCount = 0;
    for (final (_, s) in cardioSessions.take(14)) {
      final mins = s.durationMin;
      if (mins == null || mins <= 0) continue;
      final met = switch (s.kind) {
        ActivityKind.cycle => 6.0,
        ActivityKind.swim => 7.0,
        ActivityKind.walk => 4.0,
        _ => 9.0,
      };
      burnTotal += met * burnBodyweight * (mins / 60);
      burnCount++;
    }
    final avgBurn = burnCount == 0 ? null : (burnTotal / burnCount).round();

    setState(() {
      _loading = false;
      _avatarInitial =
          (name != null && name.isNotEmpty) ? name[0].toUpperCase() : 'A';
      _trainedDayKeys = trainedKeys;
      _streakCur = _currentStreakFrom(trainedKeys, today);
      _streakLongest = _longestStreakFrom(trainedKeys, today, windowDays: 84);
      _weekGoal = (prefs?.getInt(_kWeeklyGoalPref) ?? 5).clamp(1, 7);
      _last14 = _Last14.fromWorkouts(completedWorkouts.take(14));
      _newPrs = recentPrs.length;
      _avgBurnCal = avgBurn;
      _bodyweightKg =
          weightTrend.isNotEmpty ? weightTrend.last : profileBodyweight;
      _bodyweightTrend = weightTrend;
    });
  }

  // ─── streak math (logic.md §3) ────────────────────────────────────────────
  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int _currentStreakFrom(Set<String> trained, DateTime today) {
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

  static int _longestStreakFrom(Set<String> trained, DateTime today,
      {int windowDays = 84}) {
    var longest = 0, run = 0;
    for (var i = windowDays; i >= 0; i--) {
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

  /// Current week Sunday→Saturday (prototype week dots order).
  List<DateTime> get _weekDays {
    final today = DateUtils.dateOnly(DateTime.now());
    final sunday = today.subtract(Duration(days: today.weekday % 7));
    return [for (var i = 0; i < 7; i++) sunday.add(Duration(days: i))];
  }

  int get _weekCount {
    final today = DateUtils.dateOnly(DateTime.now());
    var n = 0;
    for (final d in _weekDays) {
      if (!d.isAfter(today) && _trainedDayKeys.contains(_ymd(d))) n++;
    }
    return n;
  }

  static double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  // ─── navigation (cards-and-actions.md) ────────────────────────────────────
  Future<void> _openStreakCalendar() async {
    // Prototype `openStreak` → Consistency overlay (sheetStreak, HTML 1096).
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ConsistencyScreen()),
    );
    // Manual day marks / weekly goal may have changed.
    if (mounted) await _load();
  }

  void _openProgress() {
    // Prototype `goProg` → Progress (isProg, HTML 592).
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ProgressScreen()),
    );
  }

  void _openCardioHistory() {
    // Prototype `openCardioHist` → Cardio history (screenCardioHist, HTML 908).
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CardioHistoryScreen()),
    );
  }

  void _startCardio(String mode) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
          builder: (_) => OutdoorTrackScreen(initialMode: mode)),
    );
  }

  Future<void> _editBodyweight() async {
    final messenger = ScaffoldMessenger.of(context);
    final nextKg = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BodyweightEditorSheet(initialKg: _bodyweightKg),
    );
    if (nextKg == null) return;
    setState(() {
      _bodyweightKg = nextKg;
      _bodyweightTrend = [..._bodyweightTrend, nextKg];
    });
    try {
      await _nutrition.updateWeight(nextKg, DateTime.now());
      try {
        await _profile.updateProfile(bodyweightKg: nextKg);
      } catch (_) {/* nutrition log stays the local source of truth */}
      if (!mounted) return;
      messenger
          .showSnackBar(const SnackBar(content: Text('Bodyweight updated')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: ZveltTokens.error,
      ));
    }
  }

  // ─── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: Stack(
        children: [
          RefreshIndicator(
            color: ZveltTokens.brand,
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.only(
                top: topPad + 8,
                bottom: ZveltMainNavBar.reservedBottomHeight(context),
              ),
              children: [
                _header(),
                if (_liveStats?.isTracking ?? false) _resumeBanner(_liveStats!),
                _sessionHeader(),
                _cardioTiles(),
                _sectionTitle('Consistency', topPad: 18),
                _consistencyCard(),
                _sectionTitle('Last 14 Workouts', topPad: 22),
                _volumeCard(),
                _statTrio(),
                _bodyweightCard(),
                _sectionTitle('Muscles', topPad: 22),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: MuscleMapCard(),
                ),
              ],
            ),
          ),
          // Day-menu popover + outside-tap barrier (layout-map ①).
          if (_dayMenuOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _dayMenuOpen = false),
              ),
            ),
            Positioned(
              top: topPad + 54,
              left: 22,
              child: _dayMenu(),
            ),
          ],
        ],
      ),
    );
  }

  // ① Header — "Today ▾" · avatar · streak badge
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: Row(
        children: [
          InkWell(
            onTap: () => setState(() => _dayMenuOpen = !_dayMenuOpen),
            borderRadius: BorderRadius.circular(10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Today', style: ZType.h1),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _dayMenuOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(AppIcons.angle_small_down,
                      size: 20, color: ZveltTokens.text2),
                ),
              ],
            ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: 'Open profile',
            child: ExcludeSemantics(
              child: InkWell(
                onTap: widget.onOpenProfile,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZveltTokens.chip,
                    border: Border.all(color: ZveltTokens.border, width: 1.5),
                  ),
                  child: Text(_avatarInitial,
                      style: ZType.bodyL.copyWith(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          // Static pill — the prototype's streak badge has NO action; the
          // Consistency card below is the way into the calendar.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x26F5820A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x6BF5820A)),
            ),
            child: Row(
              children: [
                const Icon(AppIcons.flame, size: 16, color: ZveltTokens.brand),
                const SizedBox(width: 5),
                Text('$_streakCur',
                    style: ZType.bodyM.copyWith(
                        color: ZveltTokens.brand, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ② Cardio resume banner — only while a live session is tracking
  // (prototype `cardioActive` → `resumeCardioScreen`, HTML 87–93).
  Widget _resumeBanner(TrackingStats live) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: InkWell(
        onTap: _resumeCardio,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            gradient: ZveltTokens.gradAccentDeep,
            borderRadius: BorderRadius.circular(18),
            boxShadow: ZveltTokens.glowLg,
          ),
          child: Row(
            children: [
              const _PulsingDot(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cardio in progress',
                        style: ZType.monoXS.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xD9FFFFFF))),
                    const SizedBox(height: 1),
                    Text(
                        '${live.durationLabel} · ${live.distanceKm.toStringAsFixed(2)} km',
                        style: ZType.num_.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: ZveltTokens.onBrand)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0x38FFFFFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Resume',
                    style: ZType.bodyS.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ZveltTokens.onBrand)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resumeCardio() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const OutdoorTrackScreen()),
    );
  }

  // ① Day-menu popover — weekday + date, Open calendar, Weekly progress.
  Widget _dayMenu() {
    final now = DateTime.now();
    const wk = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const mo = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    final weekday = wk[now.weekday - 1];
    final full = '${mo[now.month - 1]} ${now.day}, ${now.year}';

    Widget row(IconData icon, String label, VoidCallback onTap) => InkWell(
          onTap: () {
            setState(() => _dayMenuOpen = false);
            onTap();
          },
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: ZveltTokens.brand),
                const SizedBox(width: 12),
                Text(label,
                    style: ZType.bodyM.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surface2Grad,
          color: ZveltTokens.surface2,
          borderRadius: BorderRadius.circular(ZveltTokens.rBox),
          border: Border.all(color: ZveltTokens.border),
          boxShadow: const [
            BoxShadow(
                color: Color(0x8C000000),
                blurRadius: 54,
                offset: Offset(0, 22)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(weekday.toUpperCase(),
                      style: ZType.eyebrow.copyWith(color: ZveltTokens.brand)),
                  const SizedBox(height: 3),
                  Text(full,
                      style: ZType.bodyL
                          .copyWith(fontSize: 17, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Container(
                height: 1,
                margin: const EdgeInsets.fromLTRB(6, 0, 6, 5),
                color: ZveltTokens.hairline),
            row(AppIcons.calendar, 'Open calendar', _openStreakCalendar),
            row(AppIcons.chart_line_up, 'Weekly progress', _openProgress),
          ],
        ),
      ),
    );
  }

  // ③ START A SESSION + History ›
  Widget _sessionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: Row(
        children: [
          Text('START A SESSION', style: ZType.eyebrow.copyWith(fontSize: 12)),
          const Spacer(),
          InkWell(
            onTap: _openCardioHistory,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Text('Cardio history',
                    style: ZType.bodyS.copyWith(
                        color: ZveltTokens.brand, fontWeight: FontWeight.w700)),
                const Icon(AppIcons.angle_small_right,
                    size: 16, color: ZveltTokens.brand),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ④ Run / Ride tiles
  Widget _cardioTiles() {
    Widget tile({
      required String label,
      required IconData icon,
      required Gradient gradient,
      required List<BoxShadow> glow,
      required Color iconColor,
      required VoidCallback onTap,
    }) =>
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ZveltTokens.rControl),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: ZveltTokens.chip,
                borderRadius: BorderRadius.circular(ZveltTokens.rControl),
                border: Border.all(color: ZveltTokens.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: gradient,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: glow,
                    ),
                    child: Icon(icon, size: 19, color: iconColor),
                  ),
                  const SizedBox(width: 11),
                  Text(label,
                      style: ZType.bodyL.copyWith(
                          fontSize: 14.5, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 11, 20, 0),
      child: Row(
        children: [
          tile(
            label: 'Run',
            icon: AppIcons.running,
            gradient: ZveltTokens.gradAccentDeep,
            glow: ZveltTokens.glowSm,
            iconColor: ZveltTokens.onBrand,
            onTap: () => _startCardio('run'),
          ),
          const SizedBox(width: 10),
          tile(
            label: 'Ride',
            icon: AppIcons.bike,
            gradient: ZveltTokens.gradCardio,
            glow: const [
              BoxShadow(
                  color: Color(0x61C8963C),
                  offset: Offset(0, 5),
                  blurRadius: 12),
            ],
            iconColor: const Color(0xFF3A2A12),
            onTap: () => _startCardio('bike'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t, {required double topPad}) => Padding(
        padding: EdgeInsets.fromLTRB(22, topPad, 22, 0),
        child: Text(t, style: ZType.h3),
      );

  // ⑥ Consistency card
  Widget _consistencyCard() {
    final today = DateUtils.dateOnly(DateTime.now());
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: InkWell(
        onTap: _openStreakCalendar,
        borderRadius: BorderRadius.circular(ZveltTokens.rCardLg),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: ZveltTokens.surfaceGrad,
            borderRadius: BorderRadius.circular(ZveltTokens.rCardLg),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0x3DF5820A), Color(0x0FF5820A)],
                      ),
                      borderRadius: BorderRadius.circular(ZveltTokens.rControl),
                      border: Border.all(color: const Color(0x52F5820A)),
                    ),
                    child: const Icon(AppIcons.flame,
                        size: 26, color: ZveltTokens.brand),
                  ),
                  const SizedBox(width: 13),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DAY STREAK', style: ZType.eyebrow),
                      const SizedBox(height: 3),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('$_streakCur',
                              style: ZType.stat.copyWith(fontSize: 30)),
                          const SizedBox(width: 6),
                          Text('days', style: ZType.bodyS),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$_weekCount/$_weekGoal',
                          style: ZType.h4.copyWith(
                              fontSize: 22, color: ZveltTokens.brand)),
                      const SizedBox(height: 3),
                      Text('this week',
                          style: ZType.monoXS.copyWith(fontSize: 11)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 17),
              Row(
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    Expanded(child: _weekDot(_weekDays[i], labels[i], today)),
                    if (i < 6) const SizedBox(width: 7),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: ZveltTokens.hairline),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(AppIcons.target, size: 17, color: ZveltTokens.text2),
                  const SizedBox(width: 8),
                  Text('Longest $_streakLongest days',
                      style: ZType.bodyS.copyWith(fontSize: 12.5)),
                  const Spacer(),
                  Text('Open calendar ›',
                      style: ZType.bodyS.copyWith(
                          fontSize: 12.5,
                          color: ZveltTokens.brand,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weekDot(DateTime day, String label, DateTime today) {
    final trained = _trainedDayKeys.contains(_ymd(day));
    final isToday = day == today;

    final BoxDecoration deco;
    if (trained) {
      deco = BoxDecoration(
        gradient: ZveltTokens.gradAccentDeep,
        borderRadius: BorderRadius.circular(11),
        boxShadow: ZveltTokens.glowSm,
      );
    } else if (isToday) {
      deco = BoxDecoration(
        color: ZveltTokens.chip,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: ZveltTokens.brand, width: 2),
      );
    } else {
      deco = BoxDecoration(
        color: ZveltTokens.chip,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: ZveltTokens.border),
      );
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: deco,
            child: trained
                ? const Icon(AppIcons.check,
                    size: 13, color: ZveltTokens.onBrand)
                : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: ZType.monoXS.copyWith(
                fontSize: 10.5,
                color: isToday ? ZveltTokens.brand : ZveltTokens.text3,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ⑧ Volume card
  Widget _volumeCard() {
    final s = _last14;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: InkWell(
        onTap: _openProgress,
        borderRadius: BorderRadius.circular(ZveltTokens.rCard),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            gradient: ZveltTokens.surfaceGrad,
            borderRadius: BorderRadius.circular(ZveltTokens.rCard),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Volume', style: ZType.bodyS),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(_fmtVolume(s.volumeKg),
                                style: ZType.stat.copyWith(fontSize: 28)),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text('kg',
                            style: ZType.bodyM.copyWith(
                                fontWeight: FontWeight.w700,
                                color: ZveltTokens.text2)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(s.trendLabel,
                            style: ZType.bodyS.copyWith(fontSize: 12.5)),
                        const SizedBox(width: 7),
                        // Constant right-chevron in the orange circle — the
                        // prototype never swaps this glyph by trend (HTML 139).
                        Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                              color: ZveltTokens.brand, shape: BoxShape.circle),
                          child: const Icon(AppIcons.angle_small_right,
                              size: 11, color: ZveltTokens.onBrand),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 110,
                height: 62,
                child: CustomPaint(
                  painter: _VolumeBarsPainter(
                    values: s.volumeBars,
                    track: ZveltTokens.track,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⑨ Stat trio — display-only, no navigation (user QA: must open nothing).
  Widget _statTrio() {
    Widget box(String label, Widget value) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 15, 14, 15),
            decoration: BoxDecoration(
              gradient: ZveltTokens.surface2Grad,
              borderRadius: BorderRadius.circular(ZveltTokens.rBox),
              border: Border.all(color: ZveltTokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: ZType.monoXS
                        .copyWith(fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                value,
              ],
            ),
          ),
        );

    final s = _last14;
    final avg = s.avgSession;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          box(
            'Avg Session',
            Text(
              avg == null ? '—' : '${avg.inMinutes}m\n${avg.inSeconds % 60}s',
              style: ZType.h4.copyWith(fontSize: 19, height: 1.15),
            ),
          ),
          const SizedBox(width: 10),
          box(
            'New PRs',
            Text('$_newPrs', style: ZType.h2.copyWith(fontSize: 24)),
          ),
          const SizedBox(width: 10),
          box(
            'Avg Burn',
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(_avgBurnCal == null ? '—' : '$_avgBurnCal',
                    style: ZType.h2
                        .copyWith(fontSize: 24, color: ZveltTokens.brand)),
                if (_avgBurnCal != null) ...[
                  const SizedBox(width: 3),
                  Text('cal',
                      style:
                          ZType.monoXS.copyWith(fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ⑩ Bodyweight card
  Widget _bodyweightCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surfaceGrad,
          borderRadius: BorderRadius.circular(ZveltTokens.rCard),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Bodyweight', style: ZType.bodyS),
                const Spacer(),
                InkWell(
                  onTap: _editBodyweight,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ZveltTokens.chip,
                      border: Border.all(color: ZveltTokens.border),
                    ),
                    child:
                        Icon(AppIcons.plus, size: 16, color: ZveltTokens.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _bodyweightKg == null
                      ? '—'
                      : _bodyweightKg!.toStringAsFixed(1),
                  style: ZType.display,
                ),
                const SizedBox(width: 6),
                Text('kg',
                    style: ZType.bodyL.copyWith(
                        fontWeight: FontWeight.w700, color: ZveltTokens.text2)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(_bodyweightStatus(_bodyweightTrend),
                    style: ZType.bodyS.copyWith(fontSize: 12.5)),
                const SizedBox(width: 7),
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: ZveltTokens.brand, shape: BoxShape.circle),
                  child: const Icon(AppIcons.angle_small_right,
                      size: 11, color: ZveltTokens.onBrand),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtVolume(double v) {
    final s = v.toStringAsFixed(1);
    final parts = s.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '$buf.${parts[1]}';
  }

  static String _bodyweightStatus(List<double> values) {
    if (values.length < 2) return 'Stable Weight';
    final delta = values.last - values.first;
    if (delta.abs() < 0.3) return 'Stable Weight';
    return delta > 0 ? 'Trending Up' : 'Trending Down';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Last-14 aggregates (real data behind the Volume card + stat trio)
// ─────────────────────────────────────────────────────────────────────────────

class _Last14 {
  const _Last14({
    required this.volumeKg,
    required this.volumeBars,
    required this.sessionCount,
    required this.totalDuration,
    required this.trendLabel,
  });

  final double volumeKg;
  final List<double> volumeBars; // oldest → newest, up to 14
  final int sessionCount;
  final Duration totalDuration;
  final String trendLabel;

  Duration? get avgSession =>
      sessionCount == 0 || totalDuration == Duration.zero
          ? null
          : Duration(seconds: totalDuration.inSeconds ~/ sessionCount);

  static const empty = _Last14(
    volumeKg: 0,
    volumeBars: [],
    sessionCount: 0,
    totalDuration: Duration.zero,
    trendLabel: 'No workouts yet',
  );

  static _Last14 fromWorkouts(Iterable<WorkoutDto> workouts) {
    final list = workouts.toList();
    if (list.isEmpty) return empty;
    final bars = list.reversed.map(_volumeOf).toList();
    final volume = bars.fold<double>(0, (a, b) => a + b);
    var dur = Duration.zero;
    for (final w in list) {
      final end = w.endedAt;
      if (end == null) continue;
      final d = end.difference(w.startedAt);
      if (!d.isNegative && d <= const Duration(hours: 24)) dur += d;
    }
    return _Last14(
      volumeKg: volume,
      volumeBars: bars,
      sessionCount: list.length,
      totalDuration: dur,
      trendLabel: _trendFor(bars),
    );
  }

  static double _volumeOf(WorkoutDto w) {
    var sum = 0.0;
    for (final ex in w.exercises) {
      for (final set in ex.sets) {
        if (!set.isCompleted || set.tag != 'WORK') continue;
        sum += set.weightKg * set.reps;
      }
    }
    return sum;
  }

  static String _trendFor(List<double> bars) {
    final nonZero = bars.where((v) => v > 0).length;
    if (nonZero < 4) return 'Training Stable';
    final mid = bars.length ~/ 2;
    final prior = bars.take(mid).fold<double>(0, (a, b) => a + b);
    final latest = bars.skip(mid).fold<double>(0, (a, b) => a + b);
    if (prior <= 0) return 'Trending Up';
    final pct = (latest - prior) / prior;
    if (pct < -0.12) return 'Trending Down';
    if (pct > 0.12) return 'Trending Up';
    return 'Training Stable';
  }
}

/// White live dot with a soft ring, gently pulsing (prototype banner dot,
/// HTML 89).
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.45)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: 11,
        height: 11,
        decoration: const BoxDecoration(
          color: ZveltTokens.onBrand,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Color(0x47FFFFFF), spreadRadius: 4),
          ],
        ),
      ),
    );
  }
}

/// 14 mini bars — real sessions = orange gradient (peak bar glows), missing
/// slots = muted track (layout-map ⑧).
class _VolumeBarsPainter extends CustomPainter {
  const _VolumeBarsPainter({required this.values, required this.track});

  final List<double> values;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 14;
    const gap = 3.0;
    final barW = (size.width - gap * (count - 1)) / count;
    final maxV = values.fold<double>(0, (m, v) => v > m ? v : m);
    // Right-align real bars: missing history renders as muted leading slots.
    final offset = count - values.length;

    for (var i = 0; i < count; i++) {
      final vi = i - offset;
      final v = (vi >= 0 && vi < values.length) ? values[vi] : 0.0;
      final isReal = vi >= 0 && vi < values.length && v > 0;
      final pct = (maxV <= 0 || !isReal) ? 0.0 : (v / maxV).clamp(0.0, 1.0);
      final h = isReal ? (10 + pct * (size.height - 10)) : size.height * 0.22;
      final x = i * (barW + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h, barW, h),
        const Radius.circular(3),
      );
      if (isReal) {
        final paint = Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFA630), Color(0xFFEE6E08)],
          ).createShader(rect.outerRect);
        if (v >= maxV && maxV > 0) {
          canvas.drawRRect(
              rect.shift(const Offset(0, 2)),
              Paint()
                ..color = const Color(0x66F0780C)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        }
        canvas.drawRRect(rect, paint);
      } else {
        canvas.drawRRect(rect, Paint()..color = track);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VolumeBarsPainter old) =>
      old.values != values || old.track != track;
}

// ─────────────────────────────────────────────────────────────────────────────
// Bodyweight editor sheet (real "+" wiring — prototype marks this TBD; the
// app already has a working entry flow, which the docs say to wire in).
// ─────────────────────────────────────────────────────────────────────────────

class _BodyweightEditorSheet extends StatefulWidget {
  const _BodyweightEditorSheet({required this.initialKg});

  final double? initialKg;

  @override
  State<_BodyweightEditorSheet> createState() => _BodyweightEditorSheetState();
}

class _BodyweightEditorSheetState extends State<_BodyweightEditorSheet> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialKg;
    _controller = TextEditingController(
      text: initial == null ? '' : initial.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final raw = _controller.text.trim().replaceAll(',', '.');
    final kg = double.tryParse(raw);
    if (kg == null) {
      setState(() => _error = 'Enter a valid weight.');
      return;
    }
    if (kg < 30 || kg > 250) {
      setState(() => _error = 'Bodyweight must be between 30 and 250 kg.');
      return;
    }
    Navigator.of(context).pop(double.parse(kg.toStringAsFixed(1)));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          gradient: ZveltTokens.sheetGrad,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ZveltTokens.rSheet)),
          border: Border.all(color: ZveltTokens.border),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: ZveltTokens.track,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
              ),
            ),
            Text('Log bodyweight', style: ZType.h4.copyWith(fontSize: 19)),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              style: ZType.bodyL,
              decoration: InputDecoration(
                labelText: 'Bodyweight',
                suffixText: 'kg',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
