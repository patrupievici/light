import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/activity_kind.dart';
import '../../services/activity_calendar_store.dart';
import '../../services/feed_refresh_notifier.dart';
import '../../services/stats_charts_service.dart';
import '../../services/workout_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/z/z_card.dart';
import '../../widgets/z/z_loading.dart';
import '../../widgets/z/z_pressable.dart';
import '../../widgets/zvelt_main_nav_bar.dart';
import '../calendar/activity_calendar_screen.dart';
import 'quick_launch_sheet.dart';
import 'exercise_library_screen.dart';
import 'train/train_exercises_tab.dart';
import 'train/train_exercise_detail.dart';
import 'train/train_history_tab.dart';
import 'train/create_custom_exercise_screen.dart';
import 'program_builder_screen.dart';
import 'programs_library_screen.dart';
import 'program_detail_screen.dart';
import 'active_program_screen.dart';
import '../../services/program_service.dart';
import 'workout_tracker_screen.dart';
import '../../services/routine_service.dart';
// workout_tracker_screen import removed — QuickLaunchSheet handles the tracker.

class WorkoutsTab extends StatefulWidget {
  const WorkoutsTab({super.key});

  @override
  State<WorkoutsTab> createState() => _WorkoutsTabState();
}

class _WorkoutsTabState extends State<WorkoutsTab> {
  final WorkoutService _workoutService = WorkoutService();
  final RoutineService _routineService = RoutineService();
  final StatsChartsService _stats = StatsChartsService();
  final ActivityCalendarStore _calendarStore = ActivityCalendarStore();

  bool _loading = true;
  bool _starting = false;
  String? _error;

  // Train sub-tabs: 0 Azi · 1 Programe · 2 Exerciții · 3 Istoric. Each pane is
  // built lazily on first visit, then kept alive (Offstage) so scroll + state
  // survive switches.
  int _trainTab = 0;
  final List<bool> _trainVisited = [true, false, false, false];
  DateTime _focusedDay = DateUtils.dateOnly(DateTime.now());
  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());

  List<WorkoutDto> _workouts = [];
  List<Routine> _routines = [];
  Routine? _startingRoutine;
  List<DailyTrainingPoint> _dailyTraining = [];
  List<ManualCardioDayPoint> _manualCardio = [];
  Map<String, List<ActivityKind>> _activities = {};
  Map<String, List<PlannedWorkoutEntry>> _planned = {};

  // Derived view-models for the Exercises + History sub-tabs, recomputed from
  // the loaded workouts in [_computeDerived]. _exDtos / _exDetailBars run
  // parallel to _exVms so a tapped Exercises row opens its real detail.
  List<TrainExerciseVM> _exVms = const [];
  List<ExerciseDto> _exDtos = const [];
  List<List<double>> _exDetailBars = const [];
  int _histStreak = 0;
  int _histWorkoutsThisWeek = 0;
  int _lastWorkoutPrs = 0;
  Set<DateTime> _histTrainedDays = const {};
  List<HistorySession> _histSessions = const [];
  List<HistoryLogEntry> _histLog = const [];
  List<HistoryPr> _histPrs = const [];
  List<HistoryProgress> _histProgress = const [];

  @override
  void initState() {
    super.initState();
    // Reload when a session completes anywhere in the app (quick-launch ⚡,
    // Home hero, GPS run) — WorkoutService / ActivityCalendarStore bump
    // [RefreshScope.home] on save so the cached tab can't go stale.
    FeedRefreshNotifier.instance
        .notifier(RefreshScope.home)
        .addListener(_onHomeBump);
    _load();
  }

  @override
  void dispose() {
    FeedRefreshNotifier.instance
        .notifier(RefreshScope.home)
        .removeListener(_onHomeBump);
    super.dispose();
  }

  void _onHomeBump() {
    if (!mounted || _loading) return;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Drop the memoized Programs futures so pull-to-refresh refetches templates
    // + the active-program banner instead of showing stale data.
    _programsFuture = null;
    _activeFuture = null;

    // Settle every fetch independently so one failing endpoint (e.g. a
    // getWorkouts 5xx) no longer collapses the whole screen into the error
    // state and throws away the other (often locally-cached) results. Each
    // future is guarded into a result-or-null; only the PRIMARY data
    // (workouts) failing surfaces the full error state. Secondary failures
    // keep the previously loaded values and render partial data.
    final settled = await Future.wait<Object?>([
      _settle(_workoutService.getWorkouts()),
      _settle(_stats.getDailyTraining(days: 30)),
      _settle(_calendarStore.loadManualCardioHistory(days: 30)),
      _settle(_calendarStore.loadAll()),
      _settle(_calendarStore.loadPlannedWorkouts()),
      _settle(_routineService.getRoutines()),
    ]);

    if (!mounted) return;

    final workoutsResult = settled[0] as _SettleResult;
    if (!workoutsResult.ok) {
      // Primary data failed — surface the error state, mirroring the prior
      // behavior when getWorkouts threw.
      setState(() {
        _error = workoutsResult.error ?? 'Could not load workouts.';
        _loading = false;
      });
      return;
    }

    setState(() {
      _workouts = (workoutsResult.value as WorkoutsResponse).data;
      final daily = settled[1] as _SettleResult;
      final cardio = settled[2] as _SettleResult;
      final activities = settled[3] as _SettleResult;
      final planned = settled[4] as _SettleResult;
      final routines = settled[5] as _SettleResult;
      if (routines.ok) {
        _routines = routines.value as List<Routine>;
      }
      if (daily.ok) {
        _dailyTraining = daily.value as List<DailyTrainingPoint>;
      }
      if (cardio.ok) {
        _manualCardio = cardio.value as List<ManualCardioDayPoint>;
      }
      if (activities.ok) {
        _activities = activities.value as Map<String, List<ActivityKind>>;
      }
      if (planned.ok) {
        _planned = planned.value as Map<String, List<PlannedWorkoutEntry>>;
      }
      _computeDerived();
      _error = null;
      _loading = false;
    });
  }

  // Awaits [future] and reports success-with-value or failure-with-message,
  // so each _load() fetch settles independently instead of one throw aborting
  // Future.wait. A null result can't be used to signal failure here because
  // some fetches may legitimately resolve to null in the future; a dedicated
  // result type keeps the distinction unambiguous.
  Future<_SettleResult> _settle(Future<Object?> future) async {
    try {
      return _SettleResult.success(await future);
    } catch (e) {
      return _SettleResult.failure(
          e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _startRoutine(Routine r) async {
    if (_startingRoutine != null) return;
    setState(() => _startingRoutine = r);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final workoutId = await _routineService.startRoutine(r.id);
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) =>
            WorkoutTrackerScreen(workoutId: workoutId, onComplete: _load),
      ));
      if (mounted) _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: ZveltTokens.error,
      ));
    } finally {
      if (mounted) setState(() => _startingRoutine = null);
    }
  }

  Future<void> _startWorkout() async {
    if (_starting) return;
    // Route every "Start workout" through the QuickLaunch sheet so users see
    // the same preset picker no matter which screen they tapped from. Was:
    // silent blank-workout creation that diverged from the home FAB path.
    setState(() => _starting = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const QuickLaunchSheet(),
        ),
      );
      if (mounted) {
        setState(() => _starting = false);
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      final raw = e.toString().replaceFirst('Exception: ', '');
      final friendly = _friendlyStartWorkoutError(raw);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendly),
          backgroundColor: ZveltTokens.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  String _friendlyStartWorkoutError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('not signed in')) {
      return 'Session expired. Sign in again to start a workout.';
    }
    if (lower.contains('timed out') ||
        lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('connection refused') ||
        lower.contains('failed host lookup')) {
      return "Can't reach the server. Check your connection and try again.";
    }
    return "Couldn't start the workout: $raw";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        // Full-screen spinner only on the FIRST load — on pull-to-refresh the
        // lazy Offstage panes stay mounted so their search/calendar/scroll
        // state survives (and the RefreshIndicator isn't torn down mid-gesture).
        child: _loading && _workouts.isEmpty
            ? ZPageSkeleton(
                itemCount: 5,
                padding: EdgeInsets.fromLTRB(
                  ZveltTokens.screenPaddingH,
                  ZveltTokens.s3,
                  ZveltTokens.screenPaddingH,
                  ZveltMainNavBar.reservedBottomHeight(context) +
                      ZveltTokens.s4,
                ),
              )
            : Column(
                children: [
                  _trainHeader(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        ZveltTokens.screenPaddingH,
                        0,
                        ZveltTokens.screenPaddingH,
                        ZveltTokens.s3),
                    child: _SegmentedControl(
                      labels: const [
                        'Today',
                        'Programs',
                        'Exercises',
                        'History'
                      ],
                      selected: _trainTab,
                      onChanged: _selectTrainTab,
                    ),
                  ),
                  Expanded(child: _trainBody()),
                ],
              ),
      ),
    );
  }

  void _selectTrainTab(int i) {
    setState(() {
      _trainVisited[i] = true;
      _trainTab = i;
    });
  }

  Widget _trainHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH,
          ZveltTokens.s3, ZveltTokens.screenPaddingH, ZveltTokens.s3),
      child: Row(
        children: [
          Expanded(
            child: Text('Fitness',
                style: ZType.h1.copyWith(color: ZveltTokens.text)),
          ),
          _CircleIconButton(
            icon: AppIcons.plus,
            loading: _starting,
            onTap: _starting ? null : _startWorkout,
          ),
        ],
      ),
    );
  }

  // Lazy + state-preserving sub-tabs (zvelt-flutter perf guidance): a pane is
  // built on first visit and then kept in the tree (Offstage preserves its
  // scroll + state); off-screen panes pause their animations (TickerMode).
  Widget _trainBody() {
    return Stack(
      // Tight constraints for the active pane so its ListView always has a
      // bounded height (no "unbounded height" ambiguity from a loose Stack).
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < 4; i++)
          Offstage(
            offstage: _trainTab != i,
            child: TickerMode(
              enabled: _trainTab == i,
              child:
                  _trainVisited[i] ? _trainSubTab(i) : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }

  Widget _trainSubTab(int i) {
    switch (i) {
      case 0:
        return _aziTab();
      case 1:
        return _programeTab();
      case 2:
        return _exercitiiTab();
      case 3:
        return _istoricTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _subTabScroll(List<Widget> children) {
    return RefreshIndicator(
      onRefresh: _load,
      color: ZveltTokens.brand,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Bottom reserves the nav-pill height so the last item clears it.
        padding: EdgeInsets.fromLTRB(
            ZveltTokens.screenPaddingH,
            ZveltTokens.s2,
            ZveltTokens.screenPaddingH,
            ZveltMainNavBar.reservedBottomHeight(context) + ZveltTokens.s4),
        children: children,
      ),
    );
  }

  // ── Azi — train now ───────────────────────────────────────────────────────
  Widget _aziTab() {
    final last = _lastCompletedWorkout();
    return _subTabScroll([
      if (_error != null) ...[
        _InlineWarning(message: _error!),
        const SizedBox(height: ZveltTokens.s4),
      ],
      _todayCoachBubble(),
      const SizedBox(height: ZveltTokens.s4),
      _todaysWorkoutHero(),
      const SizedBox(height: ZveltTokens.s4),
      if (last != null) ...[
        _lastWorkoutCard(last),
        const SizedBox(height: ZveltTokens.s4),
      ],
      _quickActionsSection(),
      const SizedBox(height: ZveltTokens.s4),
      _thisWeekCard(),
      const SizedBox(height: ZveltTokens.s5),
      _calendarCard(),
      const SizedBox(height: ZveltTokens.s5),
      _RoutinesSection(
        routines: _routines,
        startingId: _startingRoutine?.id,
        onStart: _startRoutine,
      ),
    ]);
  }

  // ── Today data helpers (real data, honest fallbacks) ───────────────────────
  String _ymdKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  PlannedWorkoutEntry? _plannedToday() {
    final list = _planned[_ymdKey(DateUtils.dateOnly(DateTime.now()))];
    if (list == null) return null;
    for (final e in list) {
      if (!e.completed) return e;
    }
    return null;
  }

  WorkoutDto? _lastCompletedWorkout() {
    WorkoutDto? best;
    for (final w in _workouts) {
      if (w.status != 'completed' && w.endedAt == null) continue;
      final t = w.endedAt ?? w.startedAt;
      final bt = best == null ? null : (best.endedAt ?? best.startedAt);
      if (bt == null || t.isAfter(bt)) best = w;
    }
    return best;
  }

  double _workoutVolume(WorkoutDto w) {
    var v = 0.0;
    for (final ex in w.exercises) {
      for (final s in ex.sets) {
        if (s.tag == 'WARMUP') continue;
        v += s.weightKg * s.reps;
      }
    }
    return v;
  }

  String _fmtInt(num n) {
    final s = n.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  String _durLabel(Duration d) {
    // Never render a misleading "0m": non-positive → em-dash (unknown),
    // genuine sub-minute sessions → "<1m".
    if (d.inSeconds <= 0) return '—';
    final h = d.inHours, m = d.inMinutes % 60;
    if (h == 0 && m == 0) return '<1m';
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  // UTC server timestamps → LOCAL day, matching the Activity calendar.
  String _workoutDayKey(WorkoutDto w) =>
      _ymdKey(DateUtils.dateOnly((w.endedAt ?? w.startedAt).toLocal()));

  Map<String, int> _completedWorkoutCountsByDay([List<WorkoutDto>? completed]) {
    final counts = <String, int>{};
    for (final w in completed ?? _completedWorkouts()) {
      final key = _workoutDayKey(w);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  Set<String> _trainedDayKeys([List<WorkoutDto>? completed]) {
    final keys = <String>{};
    for (final w in completed ?? _completedWorkouts()) {
      keys.add(_workoutDayKey(w));
    }
    for (final p in _dailyTraining) {
      if (p.sessions > 0) {
        final dt = _parseYmd(p.day);
        if (dt != null) keys.add(_ymdKey(dt));
      }
    }
    for (final p in _manualCardio) {
      if (p.sessionCount > 0) keys.add(_ymdKey(DateUtils.dateOnly(p.date)));
    }
    _activities.forEach((k, v) {
      if (v.isNotEmpty) {
        final dt = _parseYmd(k);
        if (dt != null) keys.add(_ymdKey(dt));
      }
    });
    return keys;
  }

  int _currentStreak({Set<String>? trainedKeys}) {
    final keys = trainedKeys ?? _trainedDayKeys();
    var streak = 0;
    var day = DateUtils.dateOnly(DateTime.now());
    // Today doesn't break the streak if not yet trained; start counting from
    // the most recent trained day.
    if (!keys.contains(_ymdKey(day))) {
      day = day.subtract(const Duration(days: 1));
    }
    while (keys.contains(_ymdKey(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // ── Zvelt Coach bubble (spec A) — m8 mascot + a line of dry coach copy ─────
  Widget _todayCoachBubble() {
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      child: Row(
        children: [
          Image.asset(
            'assets/mascot/m8.png',
            height: 74,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(width: 74),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ZVELT COACH',
                  style: ZType.bodyS.copyWith(
                    color: ZveltTokens.brand,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.06 * 11,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Show up and start light. Keep it clean, not heroic.',
                  style: ZType.bodyS.copyWith(
                    color: ZveltTokens.text,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TODAY'S WORKOUT — planned session name (real) or honest fallback ───────
  Widget _todaysWorkoutHero() {
    final planned = _plannedToday();
    final title = planned?.title ?? 'Ready to train';
    final routine = _matchedRoutineForToday();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _starting ? null : _startWorkout,
        borderRadius: BorderRadius.circular(ZveltTokens.rXl),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: ZveltTokens.gradBrand,
            borderRadius: BorderRadius.circular(ZveltTokens.rXl),
            boxShadow: ZveltTokens.glowBrand,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "TODAY'S WORKOUT",
                style: ZType.bodyS.copyWith(
                  color: ZveltTokens.onBrand.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.1 * 12,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ZType.h2.copyWith(
                    color: ZveltTokens.onBrand,
                    fontWeight: FontWeight.w700,
                    fontSize: 26,
                    letterSpacing: -0.02 * 26),
              ),
              if (routine != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(AppIcons.gym,
                        size: 15,
                        color: ZveltTokens.onBrand.withValues(alpha: 0.9)),
                    const SizedBox(width: 6),
                    Text(
                      '${routine.exerciseCount} exercise${routine.exerciseCount == 1 ? '' : 's'}',
                      style: ZType.bodyS.copyWith(
                        color: ZveltTokens.onBrand.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if ((routine.focus ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in _focusChips(routine.focus!))
                        _heroMetaChip(c),
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ZveltTokens.onBrand,
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                ),
                child: Text(
                  _starting ? 'Starting…' : 'Start Workout →',
                  style: ZType.bodyM.copyWith(
                    color: ZveltTokens.brand,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── LAST WORKOUT — real volume / exercises / duration ──────────────────────
  Widget _lastWorkoutCard(WorkoutDto w) {
    final vol = _workoutVolume(w);
    final dur =
        w.endedAt != null ? _durLabel(w.endedAt!.difference(w.startedAt)) : '—';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LAST WORKOUT',
              style: ZType.bodyS.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.1 * 12,
                  color: ZveltTokens.text2)),
          const SizedBox(height: 6),
          Text(_sessionLabel(w),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZType.h4.copyWith(
                  color: ZveltTokens.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _miniStat(_fmtInt(vol), 'kg volume')),
              Expanded(child: _miniStat('$_lastWorkoutPrs', 'PRs')),
              Expanded(child: _miniStat(dur, 'duration')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String value, String label) {
    return Column(
      children: [
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ZType.h4.copyWith(
                color: ZveltTokens.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label,
            style:
                ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 11)),
      ],
    );
  }

  // ── QUICK ACTIONS ──────────────────────────────────────────────────────────
  Widget _quickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('QUICK ACTIONS',
            style: ZType.bodyS.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.1 * 12,
                color: ZveltTokens.text2)),
        const SizedBox(height: ZveltTokens.s3),
        _quickActionRow(AppIcons.plus, 'Start empty workout',
            _starting ? null : _startWorkout),
        const SizedBox(height: ZveltTokens.cardGap),
        _quickActionRow(
            AppIcons.gym, 'Choose a program', () => _selectTrainTab(1)),
        const SizedBox(height: ZveltTokens.cardGap),
        _quickActionRow(
            AppIcons.search, 'Browse exercises', () => _selectTrainTab(2)),
      ],
    );
  }

  Widget _quickActionRow(IconData icon, String label, VoidCallback? onTap) {
    return ZCard(
      onTap: onTap,
      radius: 18,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ZveltTokens.brandTint,
              borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            ),
            child: Icon(icon, color: ZveltTokens.brand, size: 20),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
              child: Text(label,
                  style: ZType.bodyM.copyWith(
                      color: ZveltTokens.text, fontWeight: FontWeight.w600))),
          Icon(AppIcons.angle_small_right, color: ZveltTokens.text3, size: 20),
        ],
      ),
    );
  }

  // ── THIS WEEK — real trained days + streak ─────────────────────────────────
  Widget _thisWeekCard() {
    final now = DateTime.now();
    final monday =
        DateUtils.dateOnly(now).subtract(Duration(days: now.weekday - 1));
    final today = DateUtils.dateOnly(now);
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final trainedKeys = _trainedDayKeys();
    final streak = _currentStreak(trainedKeys: trainedKeys);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('This week',
                  style: ZType.h4.copyWith(color: ZveltTokens.text)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AppIcons.flame,
                      color: ZveltTokens.brand, size: 16),
                  const SizedBox(width: 5),
                  Text('$streak day streak',
                      style: ZType.bodyS.copyWith(
                          color: ZveltTokens.brand,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                _weekDay(labels[i], monday.add(Duration(days: i)), today,
                    trainedKeys),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weekDay(
      String label, DateTime day, DateTime today, Set<String> trainedKeys) {
    final trained = trainedKeys.contains(_ymdKey(day));
    final isToday = day == today;
    return Column(
      children: [
        Text(label,
            style:
                ZType.bodyS.copyWith(color: ZveltTokens.text3, fontSize: 11)),
        const SizedBox(height: 8),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: trained ? ZveltTokens.brand : ZveltTokens.surface3,
            border: (isToday && !trained)
                ? Border.all(color: ZveltTokens.brand, width: 2)
                : null,
          ),
          child: trained
              ? const Icon(AppIcons.check, size: 15, color: ZveltTokens.onBrand)
              : null,
        ),
      ],
    );
  }

  // Coach card — 3D rabbit mascot + a line of honest, dry coach copy.
  /// Calendar + selected-day summary. Lives in Azi so "what's on for today" is
  /// in the Today tab, not buried in historical analytics.
  Widget _calendarCard() {
    final selectedDayEvents = _eventsForDay(_selectedDay);
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calendar',
            style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
          ),
          const SizedBox(height: ZveltTokens.s4),
          TableCalendar<int>(
            firstDay: DateTime.utc(2023, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(day, _selectedDay),
            headerStyle: HeaderStyle(
              titleCentered: false,
              formatButtonVisible: false,
              leftChevronIcon:
                  Icon(AppIcons.angle_small_left, color: ZveltTokens.text2),
              rightChevronIcon:
                  Icon(AppIcons.angle_small_right, color: ZveltTokens.text2),
              titleTextStyle:
                  ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
            ),
            calendarStyle: CalendarStyle(
              defaultTextStyle: ZType.bodyM.copyWith(color: ZveltTokens.text),
              weekendTextStyle: ZType.bodyM.copyWith(color: ZveltTokens.text),
              outsideTextStyle: ZType.bodyM.copyWith(color: ZveltTokens.text4),
              selectedDecoration: const BoxDecoration(
                color: ZveltTokens.brand,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: ZveltTokens.brandTint,
                shape: BoxShape.circle,
              ),
              todayTextStyle: ZType.bodyM.copyWith(
                  color: ZveltTokens.brandDeep, fontWeight: FontWeight.w600),
              markerDecoration: const BoxDecoration(
                color: ZveltTokens.brand,
                shape: BoxShape.circle,
              ),
            ),
            eventLoader: (day) {
              final count = _eventsForDay(day);
              return List<int>.generate(count, (index) => index);
            },
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = DateUtils.dateOnly(selectedDay);
                _focusedDay = DateUtils.dateOnly(focusedDay);
              });
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const ActivityCalendarScreen(),
                ),
              );
            },
            onPageChanged: (focusedDay) {
              _focusedDay = DateUtils.dateOnly(focusedDay);
            },
          ),
          const SizedBox(height: ZveltTokens.s4),
          _SelectedDaySummary(
            day: _selectedDay,
            activityCount: selectedDayEvents,
            label: _selectedDayLabel(),
          ),
        ],
      ),
    );
  }

  // ── Programe — multi-week programs ────────────────────────────────────────
  // Program templates for the Programs sub-tab — fetched once, memoized so the
  // lazy/kept-alive pane doesn't refetch on every rebuild.
  Future<List<ProgramSummary>>? _programsFuture;
  Future<ActiveProgramView>? _activeFuture;

  Future<void> _openTemplate(ProgramSummary t) async {
    // ProgramDetailScreen pops `true` once the program is actually started.
    // Route straight into the active program (where "Începe sesiunea" launches
    // the tracked session) — without this the tap looked like it did nothing.
    final started = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
          builder: (_) => ProgramDetailScreen(templateId: t.id)),
    );
    if (!mounted) return;
    if (started == true) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const ActiveProgramScreen()),
      );
      if (!mounted) return;
    }
    _load();
  }

  // Continue-program banner (spec A) — only when there's a real active program.
  Widget _continueProgramBanner() {
    return FutureBuilder<ActiveProgramView>(
      future: _activeFuture,
      builder: (context, snap) {
        final prog = snap.data?.program;
        if (prog == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: ZveltTokens.s5),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                    builder: (_) => const ActiveProgramScreen()),
              ),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                padding: const EdgeInsets.all(ZveltTokens.s4),
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: ZveltTokens.brand,
                        boxShadow: ZveltTokens.glowBrand,
                      ),
                      child: const Icon(AppIcons.gym,
                          color: ZveltTokens.onBrand, size: 24),
                    ),
                    const SizedBox(width: ZveltTokens.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Continue program',
                              style: ZType.bodyS.copyWith(
                                  color: ZveltTokens.brand,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(prog.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ZType.h4.copyWith(
                                  color: ZveltTokens.text,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('Week ${prog.currentWeek} of ${prog.totalWeeks}',
                              style: ZType.bodyS
                                  .copyWith(color: ZveltTokens.text2)),
                        ],
                      ),
                    ),
                    const Icon(AppIcons.angle_small_right,
                        color: ZveltTokens.brand, size: 22),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _programeTab() {
    _programsFuture ??= ProgramService().getTemplates();
    _activeFuture ??= ProgramService().getActive();
    return _subTabScroll([
      _continueProgramBanner(),
      _AiPlanBuilderCard(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const ProgramBuilderScreen()),
        ),
      ),
      const SizedBox(height: ZveltTokens.s5),
      Text('CHOOSE A PROGRAM',
          style: ZType.bodyS.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.1 * 11,
              color: ZveltTokens.text2)),
      const SizedBox(height: ZveltTokens.s3),
      FutureBuilder<List<ProgramSummary>>(
        future: _programsFuture,
        builder: (context, snap) {
          if (!snap.hasData && snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: ZveltTokens.s8),
              child: Center(
                  child: CircularProgressIndicator(color: ZveltTokens.brand)),
            );
          }
          if (snap.hasError) {
            return Text('Could not load programs. Pull to retry.',
                style: ZType.bodyS.copyWith(color: ZveltTokens.text2));
          }
          final programs = snap.data ?? const <ProgramSummary>[];
          if (programs.isEmpty) {
            return Text('No programs available yet.',
                style: ZType.bodyS.copyWith(color: ZveltTokens.text2));
          }
          return Column(
            children: [
              for (final p in programs) ...[
                _ProgramSummaryCard(summary: p, onTap: () => _openTemplate(p)),
                const SizedBox(height: ZveltTokens.cardGap),
              ],
            ],
          );
        },
      ),
      const SizedBox(height: ZveltTokens.s2),
      _ProgramsEntryCard(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
              builder: (_) => const ProgramsLibraryScreen()),
        ),
      ),
    ]);
  }

  // ── Exerciții — exercise library (design handoff: inline list, real data) ──
  Widget _exercitiiTab() {
    return _subTabScroll([
      TrainExercisesTab(
        exercises: _exVms,
        onOpenExercise: _openExerciseDetail,
        onBrowseLibrary: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()),
        ),
        onCreateCustom: _openCreateCustom,
      ),
    ]);
  }

  // Opens the real create-custom-exercise form; on success surface a confirm.
  Future<void> _openCreateCustom() async {
    final messenger = ScaffoldMessenger.of(context);
    final created = await Navigator.of(context).push<ExerciseDto>(
      MaterialPageRoute(builder: (_) => const CreateCustomExerciseScreen()),
    );
    if (created == null || !mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Created "${created.name}".'),
        backgroundColor: ZveltTokens.success,
      ),
    );
  }

  // Opens the tapped exercise's real detail. [index] is the position in the
  // _exVms list passed to [TrainExercisesTab]; _exDtos / _exDetailBars run
  // parallel to it.
  void _openExerciseDetail(int index) {
    if (index < 0 || index >= _exDtos.length) return;
    final ex = _exDtos[index];
    final vm = _exVms[index];
    final muscles = <String>[
      if ((ex.primaryMuscle ?? '').trim().isNotEmpty) ex.primaryMuscle!.trim(),
      ...ex.secondaryMuscles.where((m) => m.trim().isNotEmpty),
    ];
    final instructions = ex.instructions.isNotEmpty
        ? ex.instructions.join('\n')
        : (ex.description ??
            'No instructions available for this exercise yet.');
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => TrainExerciseDetailScreen(
        name: ex.name,
        lastSet: vm.lastLabel,
        best: vm.bestLabel,
        volumeDeltaLabel: '${vm.trendLabel} mo.',
        bars: index < _exDetailBars.length && _exDetailBars[index].isNotEmpty
            ? _exDetailBars[index]
            : const [0.4, 0.55, 0.48, 0.7, 0.6, 0.88, 1.0],
        muscles: muscles.isEmpty ? const ['Full body'] : muscles,
        instructions: instructions,
        onAddToWorkout: _starting
            ? null
            : () {
                Navigator.of(context).maybePop();
                _startWorkout();
              },
      ),
    ));
  }

  // ── Istoric — design handoff bound to real workouts. Monthly summary / log /
  // PRs / progress all derive from completed workouts; the coach card uses the
  // real streak + workouts-this-week.
  Widget _istoricTab() {
    return _subTabScroll([
      TrainHistoryTab(
        dayStreak: _histStreak,
        workoutsThisWeek: _histWorkoutsThisWeek,
        trainedDays: _histTrainedDays,
        monthSessions: _histSessions,
        workoutLog: _histLog,
        personalRecords: _histPrs,
        progressCharts: _histProgress,
        onOpenWorkout: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const ActivityCalendarScreen()),
        ),
        onOpenExerciseProgress: () => _selectTrainTab(2),
      ),
    ]);
  }

  // ════════════════════════════════════════════════════════════════════════
  // Derived data for the Exercises + History sub-tabs. Real where the API has
  // it; honest logic where it doesn't — a workout carries no name, so the log
  // label comes from the dominant muscle group, and there's no PR table, so PRs
  // are computed from Epley e1RM (CLAUDE.md ranking spec).
  // ════════════════════════════════════════════════════════════════════════
  void _computeDerived() {
    final completed = _completedWorkouts(); // newest first

    final meta = <String, ExerciseDto>{};
    final sessionCount = <String, int>{};
    final bestE1rm = <String, double>{};
    final bestWReps = <String, (double, int)>{};
    final bestReps = <String, int>{};
    final exSessionVols = <String, List<double>>{}; // oldest → newest

    for (final w in completed.reversed) {
      for (final we in w.exercises) {
        meta[we.exerciseId] = we.exercise;
        sessionCount[we.exerciseId] = (sessionCount[we.exerciseId] ?? 0) + 1;
        var sv = 0.0;
        for (final s in we.sets) {
          if (s.tag != 'WARMUP') sv += s.weightKg * s.reps;
          if (s.tag == 'WORK') {
            final e = _setE1rm(s);
            if (e > (bestE1rm[we.exerciseId] ?? 0)) {
              bestE1rm[we.exerciseId] = e;
              bestWReps[we.exerciseId] = (s.weightKg, s.reps);
            }
            // Only track best reps for genuine bodyweight sets (weight ≤ 0) so a
            // loaded high-rep lift (e.g. 60 kg × 15, out of the e1RM window) is
            // never shown as "BW × N" in Personal Records.
            if (s.weightKg <= 0 && s.reps > (bestReps[we.exerciseId] ?? 0)) {
              bestReps[we.exerciseId] = s.reps;
            }
          }
        }
        exSessionVols.putIfAbsent(we.exerciseId, () => []).add(sv);
      }
    }

    // PR count per workout: oldest → newest, count exercises beating their
    // running-best e1RM.
    final running = <String, double>{};
    final prCountById = <String, int>{};
    for (final w in completed.reversed) {
      final wBest = <String, double>{};
      for (final we in w.exercises) {
        for (final s in we.sets) {
          final e = _setE1rm(s);
          if (e > (wBest[we.exerciseId] ?? 0)) wBest[we.exerciseId] = e;
        }
      }
      var prs = 0;
      wBest.forEach((id, b) {
        if (b > (running[id] ?? 0)) {
          prs++;
          running[id] = b;
        }
      });
      prCountById[w.id] = prs;
    }
    _lastWorkoutPrs =
        completed.isNotEmpty ? (prCountById[completed.first.id] ?? 0) : 0;

    // Exercises tab VMs (+ parallel dtos / detail bars), most-trained first.
    final order = meta.keys.toList()
      ..sort((a, b) {
        final va = exSessionVols[a]?.fold<double>(0, (s, x) => s + x) ?? 0;
        final vb = exSessionVols[b]?.fold<double>(0, (s, x) => s + x) ?? 0;
        return vb.compareTo(va);
      });
    final vms = <TrainExerciseVM>[];
    final dtos = <ExerciseDto>[];
    final detailBars = <List<double>>[];
    for (final id in order) {
      final ex = meta[id]!;
      WorkoutSetDto? top;
      for (final w in completed) {
        WorkoutExerciseDto? we;
        for (final x in w.exercises) {
          if (x.exerciseId == id) {
            we = x;
            break;
          }
        }
        if (we == null) continue;
        for (final s in we.sets) {
          if (s.tag != 'WORK') continue;
          if (top == null ||
              s.weightKg > top.weightKg ||
              (s.weightKg == top.weightKg && s.reps > top.reps)) {
            top = s;
          }
        }
        break; // most recent session only
      }
      final lastLabel = top == null ? '—' : _fmtSet(top.weightKg, top.reps);
      final bestLabel = (bestE1rm[id] ?? 0) > 0
          ? _fmtSet(bestWReps[id]!.$1, bestWReps[id]!.$2)
          : lastLabel;
      final vols = exSessionVols[id] ?? const <double>[];
      final recent = vols.length > 7 ? vols.sublist(vols.length - 7) : vols;
      vms.add(TrainExerciseVM(
        name: ex.name,
        equipment: (ex.equipment ?? '').trim(),
        level: ex.beginnerSuitable ? 'Beginner' : '',
        lastLabel: lastLabel,
        bestLabel: bestLabel,
        trendLabel: _trendPct(recent),
        group: _muscleGroup(ex.primaryMuscle).toLowerCase(),
        bars: _normalizeBars(recent),
      ));
      dtos.add(ex);
      detailBars.add(_normalizeBarsD(recent));
    }

    // Personal records: weighted by e1RM first, bodyweight by reps to fill.
    final prs = <HistoryPr>[];
    final weighted = bestE1rm.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in weighted.take(5)) {
      final wr = bestWReps[e.key]!;
      prs.add(HistoryPr(
        exercise: meta[e.key]!.name,
        value: _fmtSet(wr.$1, wr.$2),
        category: 'Best e1RM',
      ));
    }
    if (prs.length < 5) {
      final bw = bestReps.entries
          .where((e) => (bestE1rm[e.key] ?? 0) == 0 && e.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in bw.take(5 - prs.length)) {
        prs.add(HistoryPr(
          exercise: meta[e.key]!.name,
          value: 'BW × ${e.value}',
          category: 'Best reps',
        ));
      }
    }

    // Progress charts: top 2 exercises with ≥2 sessions.
    final progress = <HistoryProgress>[];
    final topEx = sessionCount.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in topEx.take(2)) {
      final vols = exSessionVols[e.key]!;
      final recent = vols.length > 7 ? vols.sublist(vols.length - 7) : vols;
      progress.add(HistoryProgress(
        name: meta[e.key]!.name,
        trendLabel: _trendPct(recent),
        bars: _normalizeBarsD(recent),
      ));
    }

    // Monthly sessions for the calendar's monthly summary (filtered per month
    // inside the widget).
    final sessions = <HistorySession>[];
    for (final w in completed) {
      var vol = 0.0;
      var sets = 0;
      final mv = <String, double>{};
      for (final we in w.exercises) {
        final g = _muscleGroup(we.exercise.primaryMuscle);
        for (final s in we.sets) {
          if (s.tag == 'WARMUP') continue;
          vol += s.weightKg * s.reps;
          sets++;
          if (g != 'Other') mv[g] = (mv[g] ?? 0) + s.weightKg * s.reps + s.reps;
        }
      }
      sessions.add(HistorySession(
        date: DateUtils.dateOnly((w.endedAt ?? w.startedAt).toLocal()),
        volumeKg: vol,
        sets: sets,
        muscleVolume: mv,
      ));
    }

    // Workout log (newest 10).
    final log = <HistoryLogEntry>[];
    for (final w in completed.take(10)) {
      final d = (w.endedAt ?? w.startedAt).toLocal();
      final dur = w.endedAt != null
          ? _durLabel(w.endedAt!.difference(w.startedAt))
          : '—';
      log.add(HistoryLogEntry(
        label: _sessionLabel(w),
        subtitle:
            '${_monShort(d.month)} ${d.day} · $dur · ${_fmtInt(_workoutVolume(w))} kg',
        prCount: prCountById[w.id] ?? 0,
      ));
    }

    // Trained days (strength + tracked activities), for the calendar.
    final trainedKeys = _trainedDayKeys(completed);
    final trained = <DateTime>{};
    for (final key in trainedKeys) {
      final dt = _parseYmd(key);
      if (dt != null) trained.add(dt);
    }

    // Workouts this week (Monday-anchored).
    final now = DateTime.now();
    final monday =
        DateUtils.dateOnly(now).subtract(Duration(days: now.weekday - 1));
    var wtw = 0;
    for (final w in completed) {
      final d = DateUtils.dateOnly((w.endedAt ?? w.startedAt).toLocal());
      if (!d.isBefore(monday)) wtw++;
    }

    _exVms = vms;
    _exDtos = dtos;
    _exDetailBars = detailBars;
    _histStreak = _currentStreak(trainedKeys: trainedKeys);
    _histWorkoutsThisWeek = wtw;
    _histTrainedDays = trained;
    _histSessions = sessions;
    _histLog = log;
    _histPrs = prs;
    _histProgress = progress;
  }

  List<WorkoutDto> _completedWorkouts() {
    return _workouts
        .where((w) => w.status == 'completed' || w.endedAt != null)
        .toList()
      ..sort((a, b) =>
          (b.endedAt ?? b.startedAt).compareTo(a.endedAt ?? a.startedAt));
  }

  // Epley e1RM for a WORK set in the 1..12 window (CLAUDE.md ranking spec); 0
  // for warmup/drop, out-of-window reps, or bodyweight (0 kg).
  double _setE1rm(WorkoutSetDto s) {
    if (s.tag != 'WORK' || s.reps < 1 || s.reps > 12 || s.weightKg <= 0) {
      return 0;
    }
    return s.weightKg * (1 + s.reps / 30);
  }

  String _muscleGroup(String? raw) {
    final v = (raw ?? '').toLowerCase();
    if (v.contains('chest') || v.contains('pec')) return 'Chest';
    if (v.contains('back') ||
        v.contains('lat') ||
        v.contains('trap') ||
        v.contains('rhom')) {
      return 'Back';
    }
    if (v.contains('quad') ||
        v.contains('glute') ||
        v.contains('ham') ||
        v.contains('calf') ||
        v.contains('leg')) {
      return 'Legs';
    }
    if (v.contains('delt') || v.contains('shoulder')) return 'Shoulders';
    if (v.contains('bicep') ||
        v.contains('tricep') ||
        v.contains('forearm') ||
        v.contains('arm')) {
      return 'Arms';
    }
    if (v.contains('ab') || v.contains('core') || v.contains('oblique')) {
      return 'Core';
    }
    return 'Other';
  }

  String _fmtSet(double weightKg, int reps) =>
      weightKg <= 0 ? 'BW × $reps' : '${_fmtWeight(weightKg)} kg × $reps';

  String _fmtWeight(double kg) =>
      kg % 1 == 0 ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1);

  String _monShort(int m) => const [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][m];

  String _trendPct(List<double> oldestToNewest) {
    if (oldestToNewest.length < 2) return '0%';
    final first = oldestToNewest.firstWhere((x) => x > 0, orElse: () => 0.0);
    final last = oldestToNewest.last;
    if (first <= 0) return '0%';
    final pct = ((last - first) / first * 100).round();
    return '${pct > 0 ? '+' : ''}$pct%';
  }

  List<int> _normalizeBars(List<double> v) {
    if (v.isEmpty) return const [];
    final max = v.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return List<int>.filled(v.length, 6);
    return v
        .map((x) => ((x / max) * 100).round().clamp(6, 100).toInt())
        .toList();
  }

  List<double> _normalizeBarsD(List<double> v) {
    if (v.isEmpty) return const [];
    final max = v.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return List<double>.filled(v.length, 0.06);
    return v.map((x) => (x / max).clamp(0.06, 1.0).toDouble()).toList();
  }

  DateTime? _parseYmd(String s) {
    final p = s.split('-');
    if (p.length < 3) return null;
    final y = int.tryParse(p[0]);
    final mo = int.tryParse(p[1]);
    final da = int.tryParse(p[2].length > 2 ? p[2].substring(0, 2) : p[2]);
    if (y == null || mo == null || da == null) return null;
    return DateTime(y, mo, da);
  }

  // No workout name in the API → label from the dominant muscle group.
  String _sessionLabel(WorkoutDto w) {
    // Program/planned sessions carry their real title ("From plan: <name>") —
    // show that instead of the generic "<Muscle> Day".
    final sessionTitle = w.sessionTitle;
    if (sessionTitle != null) return sessionTitle;
    final vol = <String, double>{};
    for (final we in w.exercises) {
      final g = _muscleGroup(we.exercise.primaryMuscle);
      if (g == 'Other') continue;
      var sv = 0.0;
      for (final s in we.sets) {
        if (s.tag == 'WARMUP') continue;
        sv += s.weightKg * s.reps + s.reps;
      }
      vol[g] = (vol[g] ?? 0) + sv;
    }
    if (vol.isEmpty) return 'Workout';
    final top = vol.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return '$top Day';
  }

  // Maps today's planned session to a saved routine (so the hero can show its
  // real exercise count + focus chips); null when nothing matches.
  Routine? _matchedRoutineForToday() {
    final title = (_plannedToday()?.title ?? '').toLowerCase().trim();
    if (title.isEmpty) return null;
    for (final r in _routines) {
      if (r.name.toLowerCase().trim() == title) return r;
    }
    for (final r in _routines) {
      final n = r.name.toLowerCase().trim();
      if (n.isNotEmpty && (title.contains(n) || n.contains(title))) return r;
    }
    return null;
  }

  List<String> _focusChips(String focus) {
    return focus
        .split(RegExp(r'[,/·•&]|\band\b'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(3)
        .toList();
  }

  Widget _heroMetaChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ZveltTokens.onBrand.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
      ),
      child: Text(
        label,
        style: ZType.bodyS.copyWith(
          color: ZveltTokens.onBrand,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  int _eventsForDay(DateTime day) {
    final key = _dayKey(day);
    var count = 0;
    final dailyStrength = _dailyTraining
        .where((item) => item.day == key)
        .fold<int>(0, (sum, item) => sum + item.sessions);
    final workoutStrength = _completedWorkoutCountsByDay()[key] ?? 0;
    count += dailyStrength > workoutStrength ? dailyStrength : workoutStrength;
    count += _activities[key]?.length ?? 0;
    count += _planned[key]?.length ?? 0;
    count += _manualCardio
        .where((item) => _dayKey(item.date) == key)
        .fold<int>(0, (sum, item) => sum + item.sessionCount);
    return count;
  }

  String _selectedDayLabel() {
    final key = _dayKey(_selectedDay);
    final labels = <String>[];
    final daily = _dailyTraining.where((item) => item.day == key).toList();
    final dailyStrength =
        daily.fold<int>(0, (sum, item) => sum + item.sessions);
    final workoutStrength = _completedWorkoutCountsByDay()[key] ?? 0;
    final strength =
        dailyStrength > workoutStrength ? dailyStrength : workoutStrength;
    if (strength > 0) labels.add('$strength strength');
    final cardio =
        _manualCardio.where((item) => _dayKey(item.date) == key).toList();
    if (cardio.isNotEmpty && cardio.first.totalMinutes > 0) {
      labels.add('${cardio.first.totalMinutes} min cardio');
    }
    final nonGym = _activities[key];
    if (nonGym != null && nonGym.isNotEmpty) {
      labels.add('${nonGym.length} activities');
    }
    final planned = _planned[key];
    if (planned != null && planned.isNotEmpty) {
      labels.add('${planned.length} planned');
    }
    return labels.isEmpty
        ? 'No activity logged for this day yet.'
        : labels.join(' • ');
  }

  String _dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

/// Outcome of a single guarded fetch in [_WorkoutsTabState._load]. [ok]
/// distinguishes a successful (possibly null) [value] from a [failure] whose
/// [error] carries the cleaned-up message for the primary error banner.
class _SettleResult {
  const _SettleResult.success(this.value)
      : ok = true,
        error = null;
  const _SettleResult.failure(this.error)
      : ok = false,
        value = null;

  final bool ok;
  final Object? value;
  final String? error;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // V2 wrapper — drops the V1 dark border + heavy shadow in favor of
    // the standard ZCard (white surface, soft shadow, 24px radius).
    return ZCard(
      padding: const EdgeInsets.all(ZveltTokens.s5),
      child: child,
    );
  }
}

/// Contextual AI entry (brief §11 / mockup 8) — "AI is a button, not a tab".
/// Pushes the existing [ProgramBuilderScreen] (goal · days · experience ·
/// equipment · focus → Generate Plan → Save as routine).
class _AiPlanBuilderCard extends StatelessWidget {
  const _AiPlanBuilderCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        child: Container(
          padding: const EdgeInsets.all(ZveltTokens.s4),
          decoration: BoxDecoration(
            gradient: ZveltTokens.gradBrand,
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            boxShadow: [
              BoxShadow(
                color: ZveltTokens.brand.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ZveltTokens.onBrand.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                ),
                child: const Icon(AppIcons.sparkles,
                    color: ZveltTokens.onBrand, size: 22),
              ),
              const SizedBox(width: ZveltTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Plan Builder',
                        style: ZType.h4.copyWith(color: ZveltTokens.onBrand)),
                    const SizedBox(height: 2),
                    Text(
                      'Let AI build a workout plan for you',
                      style: ZType.bodyS.copyWith(
                        color: ZveltTokens.onBrand.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(AppIcons.angle_small_right,
                  color: ZveltTokens.onBrand),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entry to the multi-week program library ("Programe"): 5x5, PPL, 5/3/1,
/// nSuns, etc. Opens [ProgramsLibraryScreen].
class _ProgramsEntryCard extends StatelessWidget {
  const _ProgramsEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ZveltTokens.brandTint,
              borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            ),
            child: const Icon(AppIcons.gym,
                color: ZveltTokens.brandDeep, size: 22),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Program library',
                    style: ZType.h4.copyWith(color: ZveltTokens.text)),
                const SizedBox(height: 2),
                Text(
                  'Search, filter & sort all plans',
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                ),
              ],
            ),
          ),
          Icon(AppIcons.angle_small_right, color: ZveltTokens.text3, size: 22),
        ],
      ),
    );
  }
}

/// A single program template card in the Programs sub-tab list. Opens the
/// program detail/preview. Periwinkle: soft card + meta chips.
class _ProgramSummaryCard extends StatelessWidget {
  const _ProgramSummaryCard({required this.summary, required this.onTap});

  final ProgramSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chips = <(IconData, String)>[
      (
        AppIcons.calendar_check,
        '${summary.daysPerWeek}×/week · ${summary.defaultWeeks} wks'
      ),
      (AppIcons.chart_line_up, programSchemeLabel(summary.scheme)),
      (AppIcons.trophy, programLevelLabel(summary.level)),
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: ZveltTokens.shadowCard,
          ),
          padding: const EdgeInsets.all(ZveltTokens.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      summary.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZType.h3.copyWith(
                          color: ZveltTokens.text,
                          fontSize: 21,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(AppIcons.angle_small_right,
                      color: ZveltTokens.text3, size: 22),
                ],
              ),
              if (summary.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  summary.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodyS.copyWith(
                      color: ZveltTokens.text2, fontSize: 14, height: 1.45),
                ),
              ],
              const SizedBox(height: ZveltTokens.s3),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 9),
                      decoration: BoxDecoration(
                        color: ZveltTokens.bg2,
                        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(c.$1, size: 14, color: ZveltTokens.text2),
                          const SizedBox(width: 7),
                          Text(
                            c.$2,
                            style: ZType.bodyS.copyWith(
                              color: ZveltTokens.text2,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Saved routines list on the Train tab (mockup 4). Each card starts the
/// routine as a pre-filled draft workout.
class _RoutinesSection extends StatelessWidget {
  const _RoutinesSection({
    required this.routines,
    required this.startingId,
    required this.onStart,
  });

  final List<Routine> routines;
  final String? startingId;
  final ValueChanged<Routine> onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: ZveltTokens.s1, bottom: ZveltTokens.s3),
          child: Text('Routines',
              style: ZType.h4.copyWith(color: ZveltTokens.text)),
        ),
        if (routines.isEmpty)
          _SectionCard(
            child: Row(
              children: [
                Icon(AppIcons.gym, size: 20, color: ZveltTokens.text3),
                const SizedBox(width: ZveltTokens.s3),
                Expanded(
                  child: Text(
                    'No routines yet — generate one with AI Plan Builder, then save it as a routine.',
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                  ),
                ),
              ],
            ),
          )
        else
          for (final r in routines)
            Padding(
              padding: const EdgeInsets.only(bottom: ZveltTokens.cardGap),
              child: _RoutineCard(
                routine: r,
                starting: startingId == r.id,
                onStart: () => onStart(r),
              ),
            ),
      ],
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard(
      {required this.routine, required this.starting, required this.onStart});

  final Routine routine;
  final bool starting;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(routine.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZType.h4
                        .copyWith(color: ZveltTokens.text, fontSize: 16)),
                if (routine.focus != null && routine.focus!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(routine.focus!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                ],
                const SizedBox(height: 4),
                Text(
                    '${routine.exerciseCount} exercise${routine.exerciseCount == 1 ? '' : 's'}',
                    style: ZType.monoXS.copyWith(color: ZveltTokens.text3)),
              ],
            ),
          ),
          const SizedBox(width: ZveltTokens.s3),
          SizedBox(
            height: 40,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.brand,
                foregroundColor: ZveltTokens.onBrand,
                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                ),
              ),
              onPressed: starting ? null : onStart,
              child: starting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: ZveltTokens.onBrand),
                    )
                  : const Text('Start'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
      decoration: BoxDecoration(
        color: ZveltTokens.warn.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
      ),
      child: Row(
        children: [
          const Icon(AppIcons.info, color: ZveltTokens.warn),
          const SizedBox(width: ZveltTokens.s2),
          Expanded(
            child: Text(
              message,
              style: ZType.bodyS.copyWith(color: ZveltTokens.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null || loading;
    // V2 primary CTA: solid brand circle with subtle shadow, white icon.
    return ZPressable(
      onTap: disabled ? null : onTap,
      pressedScale: 0.94,
      semanticLabel: 'Start workout',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: disabled
              ? ZveltTokens.brand.withValues(alpha: 0.6)
              : ZveltTokens.brand,
          shape: BoxShape.circle,
          boxShadow: disabled ? null : ZveltTokens.glowBrand,
        ),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: ZveltTokens.onBrand,
                    ),
                  )
                : Icon(icon, color: ZveltTokens.onBrand, size: 28),
          ),
        ),
      ),
    );
  }
}

class _SelectedDaySummary extends StatelessWidget {
  const _SelectedDaySummary({
    required this.day,
    required this.activityCount,
    required this.label,
  });

  final DateTime day;
  final int activityCount;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: ZveltTokens.s4, vertical: ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ZveltTokens.brandTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(AppIcons.calendar_check,
                color: ZveltTokens.brand, size: 20),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${day.day}/${day.month}/${day.year}',
                  style:
                      ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
                ),
                const SizedBox(height: ZveltTokens.s1),
                Text(
                  activityCount == 0
                      ? 'No activities'
                      : '$activityCount logged items',
                  style: ZType.bodyS
                      .copyWith(color: ZveltTokens.text2, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s1),
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: ZPressable(
                onTap: () => onChanged(i),
                selected: selected == i,
                semanticLabel: '${labels[i]} tab',
                pressedScale: 0.98,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      vertical: ZveltTokens.s3, horizontal: ZveltTokens.s3),
                  decoration: BoxDecoration(
                    color: selected == i
                        ? ZveltTokens.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                    boxShadow: selected == i ? ZveltTokens.shadowCard : null,
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: ZType.bodyS.copyWith(
                      color:
                          selected == i ? ZveltTokens.text : ZveltTokens.text2,
                      fontSize: 12,
                      fontWeight:
                          selected == i ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
