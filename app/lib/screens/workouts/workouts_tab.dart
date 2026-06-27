import 'package:fl_chart/fl_chart.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/activity_kind.dart';
import '../../services/activity_calendar_store.dart';
import '../../services/health_service.dart';
import '../../services/stats_charts_service.dart';
import '../../services/workout_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/z/z_card.dart';
import '../../widgets/z/z_eyebrow.dart';
import '../../widgets/zvelt_main_nav_bar.dart';
import '../calendar/activity_calendar_screen.dart';
import 'quick_launch_sheet.dart';
import 'exercise_library_screen.dart';
import 'program_builder_screen.dart';
import 'programs_library_screen.dart';
import 'program_detail_screen.dart';
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
  final HealthService _health = HealthService.instance;

  bool _loading = true;
  bool _starting = false;
  String? _error;

  int _cardioTab = 0;
  int _strengthTab = 0;
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
  List<WeeklyEffortPoint> _weeklyEffort = [];
  List<ManualCardioDayPoint> _manualCardio = [];
  Map<String, List<ActivityKind>> _activities = {};
  Map<String, List<PlannedWorkoutEntry>> _planned = {};
  HealthSummary _healthSummary = HealthSummary.empty;

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

    // Settle every fetch independently so one failing endpoint (e.g. a
    // getWorkouts 5xx) no longer collapses the whole screen into the error
    // state and throws away the other (often locally-cached) results. Each
    // future is guarded into a result-or-null; only the PRIMARY data
    // (workouts) failing surfaces the full error state. Secondary failures
    // keep the previously loaded values and render partial data.
    final settled = await Future.wait<Object?>([
      _settle(_workoutService.getWorkouts()),
      _settle(_stats.getDailyTraining(days: 30)),
      _settle(_stats.getWeeklyEffort(weeks: 6)),
      _settle(_calendarStore.loadManualCardioHistory(days: 30)),
      _settle(_calendarStore.loadAll()),
      _settle(_calendarStore.loadPlannedWorkouts()),
      _settle(_health.getSummary()),
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
      final weekly = settled[2] as _SettleResult;
      final cardio = settled[3] as _SettleResult;
      final activities = settled[4] as _SettleResult;
      final planned = settled[5] as _SettleResult;
      final health = settled[6] as _SettleResult;
      final routines = settled[7] as _SettleResult;
      if (routines.ok) _routines = routines.value as List<Routine>;
      if (daily.ok) _dailyTraining = daily.value as List<DailyTrainingPoint>;
      if (weekly.ok) _weeklyEffort = weekly.value as List<WeeklyEffortPoint>;
      if (cardio.ok) _manualCardio = cardio.value as List<ManualCardioDayPoint>;
      if (activities.ok) _activities = activities.value as Map<String, List<ActivityKind>>;
      if (planned.ok) _planned = planned.value as Map<String, List<PlannedWorkoutEntry>>;
      if (health.ok) _healthSummary = health.value as HealthSummary;
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
      return _SettleResult.failure(e.toString().replaceFirst('Exception: ', ''));
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
        builder: (_) => WorkoutTrackerScreen(workoutId: workoutId, onComplete: _load),
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
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
            : Column(
                children: [
                  _trainHeader(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH, 0,
                        ZveltTokens.screenPaddingH, ZveltTokens.s3),
                    child: _SegmentedControl(
                      labels: const ['Today', 'Programs', 'Exercises', 'History'],
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
      padding: const EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH, ZveltTokens.s3,
          ZveltTokens.screenPaddingH, ZveltTokens.s3),
      child: Row(
        children: [
          Expanded(
            child: Text('Fitness', style: ZType.h1.copyWith(color: ZveltTokens.text)),
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
              child: _trainVisited[i] ? _trainSubTab(i) : const SizedBox.shrink(),
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
        padding: EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH, ZveltTokens.s2,
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
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  int _currentStreak() {
    var streak = 0;
    var day = DateUtils.dateOnly(DateTime.now());
    // Today doesn't break the streak if not yet trained; start counting from
    // the most recent trained day.
    if (_activities[_ymdKey(day)]?.isEmpty ?? true) {
      day = day.subtract(const Duration(days: 1));
    }
    while (_activities[_ymdKey(day)]?.isNotEmpty ?? false) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // ── TODAY'S WORKOUT — planned session name (real) or honest fallback ───────
  Widget _todaysWorkoutHero() {
    final planned = _plannedToday();
    final title = planned?.title ?? 'Ready to train';
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
                  color: Colors.white.withValues(alpha: 0.85),
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
                style: ZType.h2.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
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
    final dur = w.endedAt != null ? _durLabel(w.endedAt!.difference(w.startedAt)) : '—';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZveltTokens.s5),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rXl),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LAST WORKOUT',
              style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _miniStat(_fmtInt(vol), 'kg volume')),
              Expanded(child: _miniStat('${w.exercises.length}', 'exercises')),
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
            style: ZType.h4.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 11)),
      ],
    );
  }

  // ── QUICK ACTIONS ──────────────────────────────────────────────────────────
  Widget _quickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('QUICK ACTIONS', style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
        const SizedBox(height: ZveltTokens.s3),
        _quickActionRow(AppIcons.plus, 'Start empty workout',
            _starting ? null : _startWorkout),
        const SizedBox(height: ZveltTokens.cardGap),
        _quickActionRow(AppIcons.gym, 'Choose a program', () => _selectTrainTab(1)),
        const SizedBox(height: ZveltTokens.cardGap),
        _quickActionRow(AppIcons.search, 'Browse exercises', () => _selectTrainTab(2)),
      ],
    );
  }

  Widget _quickActionRow(IconData icon, String label, VoidCallback? onTap) {
    return ZCard(
      onTap: onTap,
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
          Expanded(child: Text(label, style: ZType.bodyM.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w600))),
          Icon(AppIcons.angle_small_right, color: ZveltTokens.text3, size: 20),
        ],
      ),
    );
  }

  // ── THIS WEEK — real trained days + streak ─────────────────────────────────
  Widget _thisWeekCard() {
    final now = DateTime.now();
    final monday = DateUtils.dateOnly(now).subtract(Duration(days: now.weekday - 1));
    final today = DateUtils.dateOnly(now);
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final streak = _currentStreak();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZveltTokens.s5),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rXl),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('This week', style: ZType.h4.copyWith(color: ZveltTokens.text)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AppIcons.flame, color: ZveltTokens.brand, size: 16),
                  const SizedBox(width: 5),
                  Text('$streak day streak',
                      style: ZType.bodyS.copyWith(color: ZveltTokens.brand, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                _weekDay(labels[i], monday.add(Duration(days: i)), today),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weekDay(String label, DateTime day, DateTime today) {
    final trained = _activities[_ymdKey(day)]?.isNotEmpty ?? false;
    final isToday = day == today;
    return Column(
      children: [
        Text(label, style: ZType.bodyS.copyWith(color: ZveltTokens.text3, fontSize: 11)),
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
              leftChevronIcon: Icon(AppIcons.angle_small_left, color: ZveltTokens.text2),
              rightChevronIcon: Icon(AppIcons.angle_small_right, color: ZveltTokens.text2),
              titleTextStyle: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
            ),
            calendarStyle: CalendarStyle(
              defaultTextStyle: TextStyle(color: ZveltTokens.text),
              weekendTextStyle: TextStyle(color: ZveltTokens.text),
              outsideTextStyle: TextStyle(color: ZveltTokens.text4),
              selectedDecoration: const BoxDecoration(
                color: ZveltTokens.brand,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: ZveltTokens.brandTint,
                shape: BoxShape.circle,
              ),
              todayTextStyle: const TextStyle(color: ZveltTokens.brandDeep, fontWeight: FontWeight.w600),
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

  Future<void> _openTemplate(ProgramSummary t) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => ProgramDetailScreen(templateId: t.id)),
    );
    if (mounted) _load();
  }

  Widget _programeTab() {
    _programsFuture ??= ProgramService().getTemplates();
    return _subTabScroll([
      _AiPlanBuilderCard(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const ProgramBuilderScreen()),
        ),
      ),
      const SizedBox(height: ZveltTokens.s5),
      Text('CHOOSE A PROGRAM', style: ZType.eyebrow),
      const SizedBox(height: ZveltTokens.s3),
      FutureBuilder<List<ProgramSummary>>(
        future: _programsFuture,
        builder: (context, snap) {
          if (!snap.hasData && snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: ZveltTokens.s8),
              child: Center(child: CircularProgressIndicator(color: ZveltTokens.brand)),
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
          MaterialPageRoute<void>(builder: (_) => const ProgramsLibraryScreen()),
        ),
      ),
    ]);
  }

  // ── Exerciții — exercise library ──────────────────────────────────────────
  Widget _exercitiiTab() {
    return _subTabScroll([
      Text(
        'Search any exercise with a GIF demo, filter by muscle group and equipment, or add your own exercises.',
        style: ZType.bodyM.copyWith(color: ZveltTokens.text2),
      ),
      const SizedBox(height: ZveltTokens.s4),
      _ExerciseLibraryEntryCard(
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()),
        ),
      ),
      const SizedBox(height: ZveltTokens.s4),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _starting ? null : _startWorkout,
          icon: const Icon(AppIcons.play),
          label: const Text('Start an empty workout'),
        ),
      ),
    ]);
  }

  // ── Istoric — calendar + analytics ────────────────────────────────────────
  Widget _istoricTab() {
    final strainDelta = _strainDelta();
    final strainDeltaRounded = strainDelta.round();
    final strainDeltaLabel = '${strainDeltaRounded >= 0 ? '+' : ''}$strainDeltaRounded%';
    return _subTabScroll([
                            _SectionCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Activity Summary',
                                          style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
                                        ),
                                      ),
                                      Text(
                                        '${_totalStrengthMinutes()}m',
                                        style: ZType.num_.copyWith(color: ZveltTokens.text, fontSize: 34),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: ZveltTokens.s1),
                                  Text(
                                    'Sessions and volume across the last month.',
                                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                                  ),
                                  const SizedBox(height: ZveltTokens.s5),
                                  SizedBox(
                                    height: 220,
                                    child: _ActivitySummaryChart(points: _dailyTraining),
                                  ),
                                  const SizedBox(height: ZveltTokens.s4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _MiniStat(
                                          label: 'Sessions',
                                          value: '${_dailyTraining.fold<int>(0, (sum, item) => sum + item.sessions)}',
                                        ),
                                      ),
                                      const SizedBox(width: ZveltTokens.s3),
                                      Expanded(
                                        child: _MiniStat(
                                          label: 'Volume',
                                          value: '${_dailyTraining.fold<double>(0, (sum, item) => sum + item.volumeKg).round()} kg',
                                        ),
                                      ),
                                      const SizedBox(width: ZveltTokens.s3),
                                      Expanded(
                                        child: _MiniStat(
                                          label: 'Sets',
                                          value: '${_dailyTraining.fold<int>(0, (sum, item) => sum + item.workSets)}',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: ZveltTokens.s5),
                            _SectionCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Strain Performance',
                                          style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
                                        ),
                                      ),
                                      Text(
                                        strainDeltaLabel,
                                        style: ZType.num_.copyWith(
                                          color: strainDelta >= 0 ? ZveltTokens.success : ZveltTokens.warn,
                                          fontSize: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: ZveltTokens.s2),
                                  Text(
                                    strainDelta >= 0 ? 'Above recent target' : 'Below recent target',
                                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                                  ),
                                  const SizedBox(height: ZveltTokens.s4),
                                  SizedBox(
                                    height: 210,
                                    child: _StrainPerformanceChart(points: _weeklyEffort),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: ZveltTokens.s8),
                            Text(
                              'Cardio',
                              style: ZType.h1.copyWith(color: ZveltTokens.text),
                            ),
                            const SizedBox(height: ZveltTokens.s4),
                            _SegmentedControl(
                              labels: const ['Cardio Load', 'Cardio Focus', 'HRR'],
                              selected: _cardioTab,
                              onChanged: (index) => setState(() => _cardioTab = index),
                            ),
                            const SizedBox(height: ZveltTokens.s4),
                            _buildCardioPanel(),
                            const SizedBox(height: ZveltTokens.s8),
                            Text(
                              'Strength',
                              style: ZType.h1.copyWith(color: ZveltTokens.text),
                            ),
                            const SizedBox(height: ZveltTokens.s4),
                            _SegmentedControl(
                              labels: const ['Total Volume', 'Strength Progression'],
                              selected: _strengthTab,
                              onChanged: (index) => setState(() => _strengthTab = index),
                            ),
                            const SizedBox(height: ZveltTokens.s4),
                            _buildStrengthPanel(),
    ]);
  }

  Widget _buildCardioPanel() {
    switch (_cardioTab) {
      case 0:
        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cardio Load',
                      style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
                    ),
                  ),
                  Text(
                    '${_manualCardio.fold<int>(0, (sum, item) => sum + item.totalMinutes)} min',
                    style: ZType.num_.copyWith(color: ZveltTokens.text, fontSize: 20),
                  ),
                ],
              ),
              const SizedBox(height: ZveltTokens.s4),
              SizedBox(height: 210, child: _CardioLoadChart(points: _manualCardio)),
            ],
          ),
        );
      case 1:
        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cardio Focus',
                style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
              ),
              const SizedBox(height: ZveltTokens.s2),
              Text(
                'Distribution of logged non-gym activities.',
                style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
              ),
              const SizedBox(height: ZveltTokens.s5),
              SizedBox(height: 240, child: _CardioFocusChart(activityCounts: _activityCounts())),
            ],
          ),
        );
      default:
        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HRR',
                style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
              ),
              const SizedBox(height: ZveltTokens.s2),
              Text(
                'Resting heart-rate recovery window from your recent baseline.',
                style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
              ),
              const SizedBox(height: ZveltTokens.s5),
              _BaselineGauge(
                title: 'Resting HR',
                valueLabel: _healthSummary.restingHeartRateBpm == null
                    ? 'No data'
                    : '${_healthSummary.restingHeartRateBpm!.toStringAsFixed(0)} bpm',
                low: _healthSummary.rhrBaselineLowBpm,
                high: _healthSummary.rhrBaselineHighBpm,
                value: _healthSummary.restingHeartRateBpm,
                accent: ZveltTokens.recovery,
              ),
            ],
          ),
        );
    }
  }

  Widget _buildStrengthPanel() {
    if (_strengthTab == 0) {
      final muscleVolumes = _muscleVolumes();
      return _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total Volume',
              style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
            ),
            const SizedBox(height: ZveltTokens.s2),
            Text(
              'Body-part distribution built from completed workout sets.',
              style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
            ),
            const SizedBox(height: ZveltTokens.s5),
            _TotalVolumePanel(muscleVolumes: muscleVolumes),
          ],
        ),
      );
    }

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Strength Progression',
            style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
          ),
          const SizedBox(height: ZveltTokens.s2),
          Text(
            'Daily volume trend over the last month.',
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
          ),
          const SizedBox(height: ZveltTokens.s5),
          SizedBox(height: 220, child: _StrengthProgressionChart(points: _dailyTraining)),
        ],
      ),
    );
  }

  int _eventsForDay(DateTime day) {
    final key = _dayKey(day);
    var count = 0;
    count += _activities[key]?.length ?? 0;
    count += _planned[key]?.length ?? 0;
    count += _dailyTraining.where((item) => item.day == key).fold<int>(0, (sum, item) => sum + item.sessions);
    return count;
  }

  String _selectedDayLabel() {
    final key = _dayKey(_selectedDay);
    final labels = <String>[];
    final daily = _dailyTraining.where((item) => item.day == key).toList();
    if (daily.isNotEmpty) labels.add('${daily.first.sessions} strength');
    final cardio = _manualCardio.where((item) => _dayKey(item.date) == key).toList();
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
    return labels.isEmpty ? 'No activity logged for this day yet.' : labels.join(' • ');
  }

  int _totalStrengthMinutes() {
    var total = 0;
    for (final workout in _workouts) {
      if (workout.endedAt == null) continue;
      final dayCutoff = DateTime.now().subtract(const Duration(days: 30));
      if (workout.startedAt.isBefore(dayCutoff)) continue;
      total += workout.endedAt!.difference(workout.startedAt).inMinutes;
    }
    return total;
  }

  double _strainDelta() {
    if (_weeklyEffort.length < 2) return 0;
    final latest = _weeklyEffort.last.volumeKg;
    final previous = _weeklyEffort.sublist(0, _weeklyEffort.length - 1);
    if (previous.isEmpty) return 0;
    final baseline = previous.fold<double>(0, (sum, item) => sum + item.volumeKg) / previous.length;
    if (baseline == 0) return 0;
    return ((latest - baseline) / baseline) * 100;
  }

  Map<String, double> _muscleVolumes() {
    final map = <String, double>{
      'Chest': 0,
      'Back': 0,
      'Legs': 0,
      'Shoulders': 0,
      'Core': 0,
      'Arms': 0,
    };
    for (final workout in _workouts) {
      for (final exercise in workout.exercises) {
        final muscle = _normalizeMuscle(exercise.exercise.primaryMuscle);
        final volume = exercise.sets.fold<double>(
          0,
          (sum, set) => sum + (set.weightKg * set.reps),
        );
        map[muscle] = (map[muscle] ?? 0) + volume;
      }
    }
    return map;
  }

  Map<ActivityKind, int> _activityCounts() {
    final counts = <ActivityKind, int>{};
    for (final dayActivities in _activities.values) {
      for (final kind in dayActivities) {
        counts[kind] = (counts[kind] ?? 0) + 1;
      }
    }
    return counts;
  }

  String _normalizeMuscle(String? raw) {
    final value = (raw ?? '').toLowerCase();
    if (value.contains('chest') || value.contains('pec')) return 'Chest';
    if (value.contains('back') || value.contains('lat')) return 'Back';
    if (value.contains('leg') || value.contains('quad') || value.contains('glute') || value.contains('ham')) return 'Legs';
    if (value.contains('shoulder') || value.contains('delt')) return 'Shoulders';
    if (value.contains('core') || value.contains('ab') || value.contains('oblique')) return 'Core';
    if (value.contains('arm') || value.contains('bicep') || value.contains('tricep') || value.contains('forearm')) return 'Arms';
    return 'Core';
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
                child: const Icon(AppIcons.sparkles, color: ZveltTokens.onBrand, size: 22),
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
              const Icon(AppIcons.angle_small_right, color: ZveltTokens.onBrand),
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
            child: const Icon(AppIcons.gym, color: ZveltTokens.brandDeep, size: 22),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Program library', style: ZType.h4.copyWith(color: ZveltTokens.text)),
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
    final chips = <String>[
      '${summary.daysPerWeek}×/week',
      if (summary.exercisesPerDay.isNotEmpty && summary.exercisesPerDay != '—')
        '${summary.exercisesPerDay} ex/day',
      programSchemeLabel(summary.scheme),
      programLevelLabel(summary.level),
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZveltTokens.rXl),
        child: Container(
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rXl),
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
                      style: ZType.h3.copyWith(color: ZveltTokens.text),
                    ),
                  ),
                  Icon(AppIcons.angle_small_right, color: ZveltTokens.text3, size: 22),
                ],
              ),
              if (summary.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  summary.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2, height: 1.45),
                ),
              ],
              const SizedBox(height: ZveltTokens.s3),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: ZveltTokens.bg2,
                        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                      ),
                      child: Text(
                        c,
                        style: ZType.bodyS.copyWith(
                          color: ZveltTokens.text2,
                          fontWeight: FontWeight.w500,
                          fontSize: 12.5,
                        ),
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

/// Entry into the exercise library (the "Exerciții" sub-tab) — browse exercises
/// with GIF demos, filters, and per-muscle grouping.
class _ExerciseLibraryEntryCard extends StatelessWidget {
  const _ExerciseLibraryEntryCard({required this.onTap});

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
            child: const Icon(AppIcons.gym, color: ZveltTokens.brandDeep, size: 22),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Exercise library', style: ZType.h4.copyWith(color: ZveltTokens.text)),
                const SizedBox(height: 2),
                Text(
                  'Search exercises with GIF demos, by muscle group and equipment.',
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
          padding: const EdgeInsets.only(left: ZveltTokens.s1, bottom: ZveltTokens.s3),
          child: Text('Routines', style: ZType.h4.copyWith(color: ZveltTokens.text)),
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
  const _RoutineCard({required this.routine, required this.starting, required this.onStart});

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
                    style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 16)),
                if (routine.focus != null && routine.focus!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(routine.focus!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                ],
                const SizedBox(height: 4),
                Text('${routine.exerciseCount} exercise${routine.exerciseCount == 1 ? '' : 's'}',
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.onBrand),
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
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
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
    return Material(
      color: disabled ? ZveltTokens.brand.withValues(alpha: 0.6) : ZveltTokens.brand,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: disabled ? null : onTap,
        customBorder: const CircleBorder(),
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
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s4),
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
            child: const Icon(AppIcons.calendar_check, color: ZveltTokens.brand, size: 20),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${day.day}/${day.month}/${day.year}',
                  style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
                ),
                const SizedBox(height: ZveltTokens.s1),
                Text(
                  activityCount == 0 ? 'No activities' : '$activityCount logged items',
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 13),
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

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: ZType.stat.copyWith(color: ZveltTokens.text, fontSize: 20),
          ),
          const SizedBox(height: ZveltTokens.s2),
          ZEyebrow(label),
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
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s3, horizontal: ZveltTokens.s3),
                  decoration: BoxDecoration(
                    color: selected == i ? ZveltTokens.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                    boxShadow: selected == i ? ZveltTokens.shadowCard : null,
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: ZType.bodyS.copyWith(
                      color: selected == i ? ZveltTokens.text : ZveltTokens.text2,
                      fontWeight: selected == i ? FontWeight.w600 : FontWeight.w500,
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

class _ActivitySummaryChart extends StatelessWidget {
  const _ActivitySummaryChart({required this.points});

  final List<DailyTrainingPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const _EmptyChartState(label: 'No activity data yet');
    }
    final maxY = points.fold<double>(0, (max, item) => item.volumeKg > max ? item.volumeKg : max);
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY == 0 ? 10 : maxY * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: ZveltTokens.border),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) => Text(
                value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.toInt().toString(),
                style: ZType.monoXS.copyWith(color: ZveltTokens.text2, fontSize: 11),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length || index % 5 != 0) {
                  return const SizedBox.shrink();
                }
                final day = points[index].day;
                return Text(
                  day.length >= 10 ? day.substring(8) : day,
                  style: ZType.monoXS.copyWith(color: ZveltTokens.text2, fontSize: 11),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: points[i].volumeKg,
                  width: 8,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [ZveltTokens.brand, ZveltTokens.info],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StrainPerformanceChart extends StatelessWidget {
  const _StrainPerformanceChart({required this.points});

  final List<WeeklyEffortPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const _EmptyChartState(label: 'No strain performance data yet');
    }
    final values = points.map((item) => item.volumeKg).toList();
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final avg = values.fold<double>(0, (sum, item) => sum + item) / values.length;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (values.length - 1).toDouble(),
        minY: 0,
        maxY: maxY == 0 ? 10 : maxY * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: ZveltTokens.border),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.toInt().toString(),
                style: ZType.monoXS.copyWith(color: ZveltTokens.text2, fontSize: 11),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) return const SizedBox.shrink();
                final label = points[index].weekStart;
                return Text(
                  label.length >= 10 ? label.substring(5, 10) : label,
                  style: ZType.monoXS.copyWith(color: ZveltTokens.text2, fontSize: 11),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: avg,
              color: ZveltTokens.warn.withValues(alpha: 0.6),
              dashArray: const [6, 4],
              strokeWidth: 1.4,
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            barWidth: 3.5,
            color: ZveltTokens.brand,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: index == values.length - 1 ? 6 : 3,
                color: ZveltTokens.surface,
                strokeWidth: 2.5,
                strokeColor: ZveltTokens.brand,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ZveltTokens.brand.withValues(alpha: 0.28),
                  ZveltTokens.brand.withValues(alpha: 0.02),
                ],
              ),
            ),
            spots: [
              for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardioLoadChart extends StatelessWidget {
  const _CardioLoadChart({required this.points});

  final List<ManualCardioDayPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.every((item) => item.totalMinutes == 0)) {
      return const _EmptyChartState(label: 'No cardio sessions logged yet');
    }
    final maxY = points.fold<int>(0, (max, item) => item.totalMinutes > max ? item.totalMinutes : max);
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: (maxY == 0 ? 10 : maxY * 1.25).toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: ZveltTokens.border),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: ZType.monoXS.copyWith(color: ZveltTokens.text2, fontSize: 11),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length || index % 5 != 0) {
                  return const SizedBox.shrink();
                }
                return Text(
                  '${points[index].date.day}',
                  style: ZType.monoXS.copyWith(color: ZveltTokens.text2, fontSize: 11),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: points[i].totalMinutes.toDouble(),
                  width: 8,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  color: ZveltTokens.strength,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CardioFocusChart extends StatelessWidget {
  const _CardioFocusChart({required this.activityCounts});

  final Map<ActivityKind, int> activityCounts;

  @override
  Widget build(BuildContext context) {
    if (activityCounts.isEmpty) {
      return const _EmptyChartState(label: 'No activity mix available yet');
    }
    final entries = activityCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final colors = <Color>[
      ZveltTokens.strength,
      ZveltTokens.recovery,
      ZveltTokens.warn,
      ZveltTokens.cardio,
      ZveltTokens.sleep,
    ];
    return Column(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 48,
              sectionsSpace: 3,
              sections: [
                for (var i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: entries[i].value.toDouble(),
                    color: colors[i % colors.length],
                    radius: 46,
                    title: '${entries[i].value}',
                    titleStyle: ZType.num_.copyWith(
                      color: ZveltTokens.onBrand,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: ZveltTokens.s4),
        Wrap(
          spacing: ZveltTokens.s3,
          runSpacing: ZveltTokens.s3,
          children: [
            for (var i = 0; i < entries.length; i++)
              _LegendPill(
                color: colors[i % colors.length],
                label: '${entries[i].key.label} (${entries[i].value})',
              ),
          ],
        ),
      ],
    );
  }
}

class _StrengthProgressionChart extends StatelessWidget {
  const _StrengthProgressionChart({required this.points});

  final List<DailyTrainingPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const _EmptyChartState(label: 'No progression data yet');
    }
    final values = points.map((item) => item.volumeKg).toList();
    final maxY = values.fold<double>(0, (max, item) => item > max ? item : max);
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (values.length - 1).toDouble(),
        minY: 0,
        maxY: maxY == 0 ? 10 : maxY * 1.25,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: ZveltTokens.border),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: ZType.monoXS.copyWith(color: ZveltTokens.text2, fontSize: 11),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length || index % 5 != 0) {
                  return const SizedBox.shrink();
                }
                final label = points[index].day;
                return Text(
                  label.length >= 10 ? label.substring(8) : label,
                  style: ZType.monoXS.copyWith(color: ZveltTokens.text2, fontSize: 11),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            color: ZveltTokens.recovery,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ZveltTokens.recovery.withValues(alpha: 0.2),
                  ZveltTokens.recovery.withValues(alpha: 0.03),
                ],
              ),
            ),
            spots: [
              for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalVolumePanel extends StatelessWidget {
  const _TotalVolumePanel({required this.muscleVolumes});

  final Map<String, double> muscleVolumes;

  @override
  Widget build(BuildContext context) {
    final entries = muscleVolumes.entries.toList();
    final total = entries.fold<double>(0, (sum, item) => sum + item.value);
    final colors = <Color>[
      ZveltTokens.strength,
      ZveltTokens.recovery,
      ZveltTokens.warn,
      ZveltTokens.cardio,
      ZveltTokens.sleep,
      ZveltTokens.info,
    ];

    return Column(
      children: [
        SizedBox(
          height: 250,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: 62,
                  sectionsSpace: 4,
                  sections: [
                    for (var i = 0; i < entries.length; i++)
                      PieChartSectionData(
                        value: total == 0 ? 1 : entries[i].value,
                        color: colors[i % colors.length].withValues(
                          alpha: total == 0 ? 0.12 : 1,
                        ),
                        radius: 42,
                        title: '',
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total',
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                  ),
                  const SizedBox(height: ZveltTokens.s1),
                  Text(
                    '${total.round()} kg',
                    style: ZType.num_.copyWith(color: ZveltTokens.text, fontSize: 24),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: ZveltTokens.s2),
        Wrap(
          spacing: ZveltTokens.s3,
          runSpacing: ZveltTokens.s3,
          children: [
            for (var i = 0; i < entries.length; i++)
              SizedBox(
                width: 150,
                child: _VolumeLegendTile(
                  color: colors[i % colors.length],
                  label: entries[i].key,
                  value: '${entries[i].value.round()} kg',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BaselineGauge extends StatelessWidget {
  const _BaselineGauge({
    required this.title,
    required this.valueLabel,
    required this.low,
    required this.high,
    required this.value,
    required this.accent,
  });

  final String title;
  final String valueLabel;
  final double? low;
  final double? high;
  final double? value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final hasRange = low != null && high != null && high! > low!;
    final normalized = hasRange && value != null ? ((value! - low!) / (high! - low!)).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s5),
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: ZType.h4.copyWith(color: ZveltTokens.text, fontSize: 15),
          ),
          const SizedBox(height: ZveltTokens.s3),
          Text(
            valueLabel,
            style: ZType.num_.copyWith(color: ZveltTokens.text, fontSize: 28),
          ),
          const SizedBox(height: ZveltTokens.s5),
          SizedBox(
            height: 150,
            child: PieChart(
              PieChartData(
                startDegreeOffset: 180,
                sectionsSpace: 0,
                centerSpaceRadius: 50,
                sections: [
                  PieChartSectionData(
                    value: normalized * 100,
                    color: accent,
                    radius: 18,
                    title: '',
                  ),
                  PieChartSectionData(
                    value: 100 - (normalized * 100),
                    color: ZveltTokens.border,
                    radius: 18,
                    title: '',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: ZveltTokens.s2),
          Row(
            children: [
              Expanded(
                child: Text(
                  low == null ? 'Low --' : 'Low ${low!.toStringAsFixed(0)}',
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                ),
              ),
              Text(
                high == null ? 'High --' : 'High ${high!.toStringAsFixed(0)}',
                style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  const _LegendPill({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: ZveltTokens.s2),
          Text(
            label,
            style: ZType.bodyS.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _VolumeLegendTile extends StatelessWidget {
  const _VolumeLegendTile({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: ZType.bodyS.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(value, style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChartState extends StatelessWidget {
  const _EmptyChartState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
      ),
    );
  }
}
