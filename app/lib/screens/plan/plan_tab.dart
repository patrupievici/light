import 'package:flutter/material.dart';

import '../../models/activity_kind.dart';
import '../../services/activity_calendar_store.dart';
import '../../services/feed_refresh_notifier.dart';
import '../../services/program_service.dart';
import '../../services/workout_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/zvelt_main_nav_bar.dart';
import '../workouts/program_builder_screen.dart';
import '../workouts/program_detail_screen.dart';
import '../workouts/workout_tracker_screen.dart';

/// PLAN ("Plan Your Day") — 1:1 with the ZVELT handoff prototype (screen A2).
///
/// Segment **Today / Programs**. Today: Today's-Workout hero (Start Workout),
/// Empty / Repeat-last quick tiles, Workout↔Nutrition mode + Auto-Plan row,
/// date row with prev/next, week strip, Agenda (+ Add, swipe-to-delete,
/// tap-to-complete). Programs: ACTIVE-PROGRAM card, "Build a program with AI"
/// banner, "Choose your split" template list. Nothing else.
///
/// Everything is wired to REAL app systems: ProgramService (active program,
/// templates, start-day), WorkoutService (empty / repeat-last drafts),
/// ActivityCalendarStore planned entries (agenda, persisted).
class PlanTab extends StatefulWidget {
  const PlanTab({super.key});

  @override
  State<PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<PlanTab> {
  final _programs = ProgramService();
  final _workouts = WorkoutService();
  final _store = ActivityCalendarStore();

  bool _loading = true;
  bool _starting = false;
  int _tab = 0; // 0 Today · 1 Programs
  int _mode = 0; // 0 Workout · 1 Nutrition (agenda filter)
  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());

  ActiveProgramView? _active;
  List<ProgramSummary> _templates = const [];
  Map<String, List<PlannedWorkoutEntry>> _planned = const {};
  WorkoutDto? _lastCompleted;

  @override
  void initState() {
    super.initState();
    FeedRefreshNotifier.instance
        .notifier(RefreshScope.home)
        .addListener(_onBump);
    _load();
  }

  @override
  void dispose() {
    FeedRefreshNotifier.instance
        .notifier(RefreshScope.home)
        .removeListener(_onBump);
    super.dispose();
  }

  void _onBump() {
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
      _safe(_programs.getActive()),
      _safe(_programs.getTemplates()),
      _safe(_store.loadPlannedWorkouts()),
      _safe(_workouts.getWorkouts(limit: 10)),
    ]);
    if (!mounted) return;
    final workoutsRes = results[3] as WorkoutsResponse?;
    WorkoutDto? last;
    for (final w in workoutsRes?.data ?? const <WorkoutDto>[]) {
      if (w.status != 'draft' && w.exercises.isNotEmpty) {
        last = w;
        break;
      }
    }
    setState(() {
      _loading = false;
      _active = results[0] as ActiveProgramView?;
      _templates = (results[1] as List<ProgramSummary>?) ?? const [];
      _planned =
          (results[2] as Map<String, List<PlannedWorkoutEntry>>?) ?? const {};
      _lastCompleted = last;
    });
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ─── actions ──────────────────────────────────────────────────────────────
  Future<void> _openTracker(String workoutId) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => WorkoutTrackerScreen(workoutId: workoutId, onComplete: _load),
    ));
    _load();
  }

  Future<void> _startWorkout() async {
    final program = _active?.program;
    if (program == null) {
      setState(() => _tab = 1); // choose-a-program affordance
      return;
    }
    if (_starting) return;
    setState(() => _starting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final workoutId = await _programs.startProgramDay(program.id);
      if (!mounted) return;
      await _openTracker(workoutId);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: ZveltTokens.error,
      ));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _startEmpty() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final w = await _workouts.createWorkout(label: 'Empty Workout');
      if (!mounted) return;
      await _openTracker(w.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: ZveltTokens.error,
      ));
    }
  }

  Future<void> _repeatLast() async {
    final last = _lastCompleted;
    if (last == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final w = await _workouts.createWorkout(label: 'Repeat last');
      for (final ex in last.exercises) {
        await _workouts.addExercise(w.id, ex.exerciseId);
      }
      if (!mounted) return;
      await _openTracker(w.id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: ZveltTokens.error,
      ));
    }
  }

  /// Auto-Plan — fills the selected day's agenda from the active program
  /// (today's session at 18:00). Real data only; no invention.
  Future<void> _autoPlan() async {
    final messenger = ScaffoldMessenger.of(context);
    final title = _active?.today?.title ??
        (_active?.program?.title != null ? 'Workout' : null);
    if (title == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Pick a program first — then Auto-Plan can fill your day.')));
      return;
    }
    final day = _ymd(_selectedDay);
    final existing = _planned[day] ?? const <PlannedWorkoutEntry>[];
    if (existing.any((e) => e.title == title && !e.completed)) {
      messenger.showSnackBar(const SnackBar(content: Text('Already planned for this day.')));
      return;
    }
    await _store.addPlannedWorkout(PlannedWorkoutEntry(
      id: 'plan_${DateTime.now().millisecondsSinceEpoch}',
      dayYmd: day,
      title: title,
      kind: ActivityKind.gym,
      time: '18:00',
    ));
    messenger.showSnackBar(const SnackBar(content: Text('Added to agenda')));
    _load();
  }

  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlanAddSheet(
        dayYmd: _ymd(_selectedDay),
        mode: _mode == 0 ? 'workout' : 'nutrition',
      ),
    );
    if (added == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZveltTokens.rSm)),
        content: const Text('Added to agenda'),
      ));
      _load();
    }
  }

  Future<void> _toggleDone(PlannedWorkoutEntry e) async {
    await _store.updatePlannedWorkoutStatus(
        dayYmd: e.dayYmd, id: e.id, completed: !e.completed);
    _load();
  }

  Future<void> _deleteEntry(PlannedWorkoutEntry e) async {
    final list = _planned[e.dayYmd] ?? const <PlannedWorkoutEntry>[];
    final idx = list.indexWhere((x) => x.id == e.id);
    if (idx >= 0) await _store.removePlannedWorkoutAt(e.dayYmd, idx);
    if (mounted) {
      // Prototype `_rmAg` shows a 'Removed' toast after the swipe-delete.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZveltTokens.rSm)),
        content: const Text('Removed'),
      ));
    }
    _load();
  }

  // ─── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: RefreshIndicator(
        color: ZveltTokens.brand,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.only(
            top: topPad + 8,
            bottom: ZveltMainNavBar.reservedBottomHeight(context),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Text('Plan Your Day',
                  style: ZType.h2.copyWith(fontSize: 23)),
            ),
            _segment(),
            if (_tab == 0) ..._todayBlocks() else ..._programBlocks(),
          ],
        ),
      ),
    );
  }

  Widget _segment() {
    Widget item(String label, int i) => Expanded(
          child: InkWell(
            onTap: () => setState(() => _tab = i),
            borderRadius: BorderRadius.circular(13),
            child: AnimatedContainer(
              duration: ZMotion.quick,
              curve: ZMotion.emphasized,
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _tab == i ? ZveltTokens.brand : Colors.transparent,
                borderRadius: BorderRadius.circular(13),
                boxShadow: _tab == i ? ZveltTokens.glowSm : null,
              ),
              child: Text(
                label,
                style: ZType.bodyM.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _tab == i ? ZveltTokens.onBrand : ZveltTokens.text2,
                ),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: ZveltTokens.chip,
          borderRadius: BorderRadius.circular(ZveltTokens.rControl),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Row(children: [item('Today', 0), const SizedBox(width: 4), item('Programs', 1)]),
      ),
    );
  }

  // ─── TODAY sub-tab ────────────────────────────────────────────────────────
  List<Widget> _todayBlocks() => [
        _heroCard(),
        _quickTiles(),
        _modeAutoPlanRow(),
        _dateRow(),
        _weekStrip(),
        _agendaHeader(),
        ..._agendaList(),
      ];

  Widget _heroCard() {
    final program = _active?.program;
    final today = _active?.today;
    final hasProgram = program != null;
    final exCount = today?.exercises.length ?? 0;
    final mins = exCount > 0 ? exCount * 12 : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: ZveltTokens.heroGrad,
          borderRadius: BorderRadius.circular(ZveltTokens.rCard),
          border: Border.all(color: ZveltTokens.heroBorder),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 150,
                height: 150,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Color(0x47F58214), Color(0x00F58214)]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasProgram
                        ? "TODAY'S WORKOUT · ${program.title.toUpperCase()}"
                        : "TODAY'S WORKOUT",
                    style: ZType.eyebrow.copyWith(color: ZveltTokens.brand),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    hasProgram ? (today?.title ?? 'Rest day') : 'No program yet',
                    style: ZType.h2.copyWith(fontSize: 25),
                  ),
                  const SizedBox(height: 12),
                  if (hasProgram && today != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ZveltTokens.border),
                      ),
                      child: Text(
                        'Week ${today.week}${today.isDeload ? ' · Deload' : ''}',
                        style: ZType.monoXS.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: ZveltTokens.text),
                      ),
                    )
                  else
                    Text('Pick a split and ZVELT plans every session for you.',
                        style: ZType.bodyS),
                  const SizedBox(height: 12),
                  if (hasProgram && today != null)
                    Row(
                      children: [
                        Text('$exCount exercises',
                            style: ZType.bodyS.copyWith(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 16),
                        if (mins != null)
                          Text('$mins min',
                              style: ZType.bodyS.copyWith(
                                  fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _starting ? null : _startWorkout,
                      style: FilledButton.styleFrom(
                        backgroundColor: ZveltTokens.brand,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(ZveltTokens.rControl)),
                      ),
                      child: _starting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: ZveltTokens.onBrand))
                          : Text(hasProgram ? 'Start Workout' : 'Choose a program',
                              style: ZType.bodyM.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: ZveltTokens.onBrand)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickTiles() {
    Widget tile(String label, VoidCallback? onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ZveltTokens.rChip),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ZveltTokens.chip,
                borderRadius: BorderRadius.circular(ZveltTokens.rChip),
                border: Border.all(color: ZveltTokens.border),
              ),
              child: Opacity(
                opacity: onTap == null ? 0.4 : 1,
                child: Text(label,
                    style: ZType.bodyS.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: ZveltTokens.text)),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          tile('Empty', _startEmpty),
          const SizedBox(width: 8),
          tile('Repeat last', _lastCompleted == null ? null : _repeatLast),
        ],
      ),
    );
  }

  Widget _modeAutoPlanRow() {
    Widget modeItem(String label, IconData icon, int i) => InkWell(
          onTap: () => setState(() => _mode = i),
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: ZMotion.quick,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _mode == i ? ZveltTokens.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Icon(icon,
                    size: 14,
                    color: _mode == i ? ZveltTokens.brand : ZveltTokens.text3),
                const SizedBox(width: 5),
                Text(label,
                    style: ZType.bodyS.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color:
                            _mode == i ? ZveltTokens.text : ZveltTokens.text3)),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: ZveltTokens.chip,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ZveltTokens.border),
            ),
            child: Row(
              children: [
                modeItem('Workout', AppIcons.gym, 0),
                const SizedBox(width: 2),
                modeItem('Nutrition', AppIcons.leaf, 1),
              ],
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: _autoPlan,
            borderRadius: BorderRadius.circular(ZveltTokens.rControl),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: ZveltTokens.brand,
                borderRadius: BorderRadius.circular(ZveltTokens.rControl),
                boxShadow: ZveltTokens.glowMd,
              ),
              child: Row(
                children: [
                  const Icon(AppIcons.sparkles,
                      size: 14, color: ZveltTokens.onBrand),
                  const SizedBox(width: 5),
                  Text('Auto-Plan',
                      style: ZType.bodyS.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: ZveltTokens.onBrand)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateRow() {
    final today = DateUtils.dateOnly(DateTime.now());
    final sel = _selectedDay;
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final label = sel == today
        ? 'Today, ${mo[sel.month - 1]} ${sel.day}'
        : '${mo[sel.month - 1]} ${sel.day}';

    Widget navBtn(IconData icon, VoidCallback onTap) => InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ZveltTokens.chip,
              border: Border.all(color: ZveltTokens.borderStrong),
            ),
            child: Icon(icon, size: 15, color: ZveltTokens.text2),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      child: Row(
        children: [
          Text(label, style: ZType.h4.copyWith(fontSize: 19)),
          const Spacer(),
          navBtn(AppIcons.angle_small_left,
              () => setState(() => _selectedDay = sel.subtract(const Duration(days: 1)))),
          const SizedBox(width: 8),
          navBtn(AppIcons.angle_small_right,
              () => setState(() => _selectedDay = sel.add(const Duration(days: 1)))),
        ],
      ),
    );
  }

  Widget _weekStrip() {
    final today = DateUtils.dateOnly(DateTime.now());
    final sunday =
        _selectedDay.subtract(Duration(days: _selectedDay.weekday % 7));
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++) ...[
            Expanded(child: _stripCell(sunday.add(Duration(days: i)), labels[i], today)),
            if (i < 6) const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }

  Widget _stripCell(DateTime day, String label, DateTime today) {
    final selected = day == _selectedDay;
    final entries = _planned[_ymd(day)] ?? const <PlannedWorkoutEntry>[];
    final hasWorkout = entries.any((e) => e.kind != ActivityKind.gym || true);

    return InkWell(
      onTap: () => setState(() => _selectedDay = day),
      borderRadius: BorderRadius.circular(ZveltTokens.rChip),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? ZveltTokens.brandTint : ZveltTokens.chip,
          borderRadius: BorderRadius.circular(ZveltTokens.rChip),
          border: Border.all(
              color: selected
                  ? ZveltTokens.brand
                  : (day == today ? ZveltTokens.borderStrong : ZveltTokens.border),
              width: selected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Text('${day.day}',
                style: ZType.bodyM.copyWith(
                    fontWeight: FontWeight.w800,
                    color: selected ? ZveltTokens.brand : ZveltTokens.text)),
            const SizedBox(height: 2),
            Text(label,
                style: ZType.monoXS.copyWith(fontSize: 11)),
            SizedBox(
              height: 14,
              child: entries.isNotEmpty && hasWorkout
                  ? Icon(AppIcons.gym,
                      size: 12,
                      color: selected ? ZveltTokens.brand : ZveltTokens.text3)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _agendaHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      child: Row(
        children: [
          Text('Agenda', style: ZType.h4.copyWith(fontSize: 20)),
          const Spacer(),
          InkWell(
            onTap: _openAddSheet,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: ZveltTokens.chip,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: ZveltTokens.borderStrong),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.plus, size: 14, color: ZveltTokens.text),
                  const SizedBox(width: 6),
                  Text('Add',
                      style: ZType.bodyS.copyWith(
                          fontWeight: FontWeight.w600, color: ZveltTokens.text)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _agendaList() {
    final all = _planned[_ymd(_selectedDay)] ?? const <PlannedWorkoutEntry>[];
    // Prototype: agenda[planMode] — each mode has its own bucket.
    final wanted = _mode == 0 ? 'workout' : 'nutrition';
    final items = [
      for (final e in all)
        if (e.agendaType == wanted) e,
    ];

    if (items.isEmpty) {
      // Prototype empty state: dashed border, centered hint (HTML 365).
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: ZveltTokens.borderStrong,
              radius: ZveltTokens.rBox,
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
              alignment: Alignment.center,
              child: Text('Nothing planned yet — use Auto-Plan or Add.',
                  style: ZType.bodyS.copyWith(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
      ];
    }

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Column(
          children: [
            for (final e in items) ...[
              _AgendaRow(
                key: ValueKey('agenda-${e.id}'),
                entry: e,
                onToggle: () => _toggleDone(e),
                onDelete: () => _deleteEntry(e),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    ];
  }

  // ─── PROGRAMS sub-tab ─────────────────────────────────────────────────────
  List<Widget> _programBlocks() {
    final program = _active?.program;
    return [
      if (program != null) _activeProgramCard(program),
      _aiProgramCard(),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
        child: Text('Choose your split', style: ZType.h4.copyWith(fontSize: 20)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Column(
          children: [
            if (_loading && _templates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: ZveltTokens.brand),
              )
            else
              for (final t in _templates) ...[
                _splitCard(t, active: t.id == program?.templateId),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    ];
  }

  Widget _activeProgramCard(ActiveProgram program) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: ZveltTokens.heroGrad,
          borderRadius: BorderRadius.circular(ZveltTokens.rCardSm),
          border: Border.all(color: ZveltTokens.heroBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ACTIVE PROGRAM',
                      style: ZType.eyebrow.copyWith(color: ZveltTokens.brand)),
                  const SizedBox(height: 3),
                  Text(program.title,
                      style: ZType.bodyL.copyWith(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                      'Week ${program.currentWeek}/${program.totalWeeks} · ${program.daysPerWeek}×/week',
                      style: ZType.bodyS.copyWith(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 13),
            FilledButton(
              onPressed: () => setState(() => _tab = 0),
              style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.brand,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZveltTokens.rChip)),
              ),
              child: Text('Continue',
                  style: ZType.bodyS.copyWith(
                      fontWeight: FontWeight.w700, color: ZveltTokens.onBrand)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiProgramCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: InkWell(
        onTap: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (_) => const ProgramBuilderScreen())),
        borderRadius: BorderRadius.circular(ZveltTokens.rCardSm),
        child: Container(
          clipBehavior: Clip.antiAlias,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment(-1, -0.3),
              end: Alignment(1, 0.6),
              colors: [Color(0xFFF58A11), Color(0xFFEE6E08), Color(0xFFD85F04)],
            ),
            borderRadius: BorderRadius.circular(ZveltTokens.rCardSm),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x80EE6E08),
                  blurRadius: 30,
                  offset: Offset(0, 14),
                  spreadRadius: -8),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Build a program with AI',
                        style: ZType.bodyL.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: ZveltTokens.onBrand)),
                    const SizedBox(height: 3),
                    Text(
                      'Tell it your goal — judo grip, a dunk, a big squat — it writes the plan.',
                      style: ZType.bodyS.copyWith(
                          fontSize: 12, color: const Color(0xEBFFFFFF)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 13),
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Color(0x38FFFFFF)),
                child: const Icon(AppIcons.sparkles,
                    size: 24, color: ZveltTokens.onBrand),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _splitCard(ProgramSummary t, {required bool active}) {
    Widget chip(String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: ZveltTokens.chip,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Text(label,
              style: ZType.monoXS.copyWith(
                  fontSize: 11, fontWeight: FontWeight.w600)),
        );

    return InkWell(
      onTap: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder: (_) => ProgramDetailScreen(templateId: t.id))),
      borderRadius: BorderRadius.circular(ZveltTokens.rBox),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
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
                Flexible(
                  child: Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZType.bodyL.copyWith(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                if (active) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x29F5820A),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0x66F5820A)),
                    ),
                    child: Text('ACTIVE',
                        style: ZType.monoXS.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: ZveltTokens.brand)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 11),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                chip('${t.daysPerWeek}×/week'),
                chip(t.scheme),
                chip(t.level),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Agenda row — prototype swipe-to-delete (HTML 370–382 + JS agDown/agMove/agUp):
// row follows the finger RIGHT (0..140px), a red gradient Delete layer fades in
// behind (opacity = dx/90); release >90px deletes, a plain tap toggles done.
// ─────────────────────────────────────────────────────────────────────────────

class _AgendaRow extends StatefulWidget {
  const _AgendaRow({
    super.key,
    required this.entry,
    required this.onToggle,
    required this.onDelete,
  });

  final PlannedWorkoutEntry entry;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  State<_AgendaRow> createState() => _AgendaRowState();
}

class _AgendaRowState extends State<_AgendaRow> {
  double _dx = 0;
  bool _dragging = false;

  void _onStart(DragStartDetails _) {
    setState(() => _dragging = true);
  }

  void _onUpdate(DragUpdateDetails d) {
    setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, 140.0));
  }

  void _onEnd(DragEndDetails _) {
    final moved = _dx;
    setState(() {
      _dragging = false;
      _dx = 0;
    });
    if (moved > 90) widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final isNutrition = e.agendaType == 'nutrition';

    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        gradient: ZveltTokens.surface2Grad,
        borderRadius: BorderRadius.circular(ZveltTokens.rBox),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 23,
            height: 21,
            child: Icon(
              e.completed
                  ? AppIcons.check
                  : (isNutrition ? AppIcons.restaurant : AppIcons.gym),
              size: 20,
              color: e.completed ? ZveltTokens.text : ZveltTokens.text,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodyL.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    decoration:
                        e.completed ? TextDecoration.lineThrough : null,
                    color: e.completed ? ZveltTokens.text2 : ZveltTokens.text,
                  ),
                ),
                if (e.sub != null && e.sub!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(e.sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZType.bodyS.copyWith(
                          fontSize: 12.5, fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
          if (e.time != null) ...[
            const SizedBox(width: 8),
            Text(e.time!,
                style: ZType.bodyS.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ZveltTokens.text3)),
          ],
          const SizedBox(width: 13),
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: e.completed ? ZveltTokens.brand : null,
              border: Border.all(
                  color: e.completed ? ZveltTokens.brand : ZveltTokens.border,
                  width: 1.5),
            ),
            child: e.completed
                ? const Icon(AppIcons.check,
                    size: 13, color: ZveltTokens.onBrand)
                : null,
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(ZveltTokens.rBox),
      child: Stack(
        children: [
          // Red delete layer behind — fades in with the drag (delStyle).
          Positioned.fill(
            child: Opacity(
              opacity: _dragging ? (_dx / 90).clamp(0.0, 1.0) : 0,
              child: Container(
                padding: const EdgeInsets.only(left: 20),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFC0392B), Color(0xFFE0592B)],
                  ),
                  borderRadius: BorderRadius.circular(ZveltTokens.rBox),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(AppIcons.trash,
                        size: 18, color: ZveltTokens.onBrand),
                    const SizedBox(width: 8),
                    Text('Delete',
                        style: ZType.bodyS.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: ZveltTokens.onBrand)),
                  ],
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onToggle,
              onHorizontalDragStart: _onStart,
              onHorizontalDragUpdate: _onUpdate,
              onHorizontalDragEnd: _onEnd,
              child: row,
            ),
          ),
        ],
      ),
    );
  }
}

// Dashed rounded border for the prototype's empty-agenda card (HTML 365).
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 6.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
            metric.extractPath(d, (d + dash).clamp(0, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

// ─────────────────────────────────────────────────────────────────────────────
// Add-agenda sheet — 1:1 with the prototype `sheetPlanAdd` (HTML 790–816):
// grabber · "Add to agenda"+subtitle+close · ADD YOUR OWN card (title input,
// time picker, accent Add button) · TAP A BLOCK TO EDIT & ADD presets that
// PREFILL the form (pickPreset), per plan mode.
// ─────────────────────────────────────────────────────────────────────────────

class _PlanAddSheet extends StatefulWidget {
  const _PlanAddSheet({required this.dayYmd, required this.mode});
  final String dayYmd;

  /// 'workout' | 'nutrition' — selects the preset list (prototype addPresets).
  final String mode;

  @override
  State<_PlanAddSheet> createState() => _PlanAddSheetState();
}

class _PlanAddSheetState extends State<_PlanAddSheet> {
  final _title = TextEditingController();
  TimeOfDay _time = const TimeOfDay(hour: 12, minute: 0);
  String _sub = '';
  bool _saving = false;

  // Prototype addPresets (HTML/JS 1992–1995), verbatim.
  static const _workoutPresets = [
    (time: '07:30', title: 'Mobility', sub: '10 min warm-up'),
    (time: '09:00', title: 'Strength', sub: 'Full Body'),
    (time: '17:00', title: 'Cardio', sub: '30 min run'),
    (time: '20:00', title: 'Yoga', sub: 'Recovery flow'),
  ];
  static const _nutritionPresets = [
    (time: '08:30', title: 'Breakfast', sub: 'Oats & fruit'),
    (time: '13:00', title: 'Lunch', sub: 'Chicken & rice'),
    (time: '16:30', title: 'Snack', sub: 'Protein shake'),
    (time: '19:30', title: 'Dinner', sub: 'Salmon & greens'),
  ];

  List<({String time, String title, String sub})> get _presets =>
      widget.mode == 'nutrition' ? _nutritionPresets : _workoutPresets;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _timeLabel =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  void _pickPreset(({String time, String title, String sub}) p) {
    final parts = p.time.split(':');
    setState(() {
      _title.text = p.title;
      _sub = p.sub;
      _time = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 12,
        minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
      );
    });
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null && mounted) setState(() => _time = t);
  }

  ActivityKind get _kind {
    if (widget.mode == 'nutrition') return ActivityKind.other;
    final t = _title.text.trim().toLowerCase();
    if (t.contains('run') || t.contains('cardio')) return ActivityKind.run;
    if (t.contains('walk')) return ActivityKind.walk;
    return ActivityKind.gym;
  }

  Future<void> _add() async {
    final title = _title.text.trim();
    if (_saving) return;
    if (title.isEmpty) {
      // Prototype addCustom: empty title → 'Enter a title' toast.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZveltTokens.rSm)),
        content: const Text('Enter a title'),
      ));
      return;
    }
    setState(() => _saving = true);
    await ActivityCalendarStore().addPlannedWorkout(PlannedWorkoutEntry(
      id: 'plan_${DateTime.now().millisecondsSinceEpoch}',
      dayYmd: widget.dayYmd,
      title: title,
      kind: _kind,
      time: _timeLabel,
      sub: _sub.trim().isEmpty ? 'Custom' : _sub.trim(),
      agendaType: widget.mode,
    ));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
        ),
        decoration: BoxDecoration(
          gradient: ZveltTokens.sheetGrad,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ZveltTokens.rSheet)),
          border: Border.all(color: ZveltTokens.border),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
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
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add to agenda',
                          style: ZType.h4.copyWith(
                              fontSize: 19, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('Add a custom block or pick a preset',
                          style: ZType.bodyS.copyWith(
                              fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.of(context).pop(false),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ZveltTokens.chip,
                      border: Border.all(color: ZveltTokens.border),
                    ),
                    child: Icon(AppIcons.cross_small,
                        size: 16, color: ZveltTokens.text2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ADD YOUR OWN (HTML 798–805)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: ZveltTokens.surface2Grad,
                        borderRadius:
                            BorderRadius.circular(ZveltTokens.rControl),
                        border: Border.all(color: ZveltTokens.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ADD YOUR OWN',
                              style: ZType.eyebrow.copyWith(fontSize: 11)),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _title,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => _sub = '',
                            onSubmitted: (_) => _add(),
                            style: ZType.bodyM.copyWith(
                                fontSize: 14, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              hintText: 'Title (e.g. Yoga, Meal prep)',
                              hintStyle: ZType.bodyM.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: ZveltTokens.text3),
                              isDense: true,
                              filled: true,
                              fillColor: ZveltTokens.chip,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 13, vertical: 11),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    BorderSide(color: ZveltTokens.borderStrong),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: ZveltTokens.brand),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              InkWell(
                                onTap: _pickTime,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: ZveltTokens.chip,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: ZveltTokens.borderStrong),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(AppIcons.clock,
                                          size: 15, color: ZveltTokens.text2),
                                      const SizedBox(width: 7),
                                      Text(_timeLabel,
                                          style: ZType.bodyM.copyWith(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: InkWell(
                                  onTap: _saving ? null : _add,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: ZveltTokens.brand,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: ZveltTokens.glowSm,
                                    ),
                                    child: _saving
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: ZveltTokens.onBrand))
                                        : Text('Add to agenda',
                                            style: ZType.bodyS.copyWith(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: ZveltTokens.onBrand)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 15, 2, 0),
                      child: Text('TAP A BLOCK TO EDIT & ADD',
                          style: ZType.eyebrow.copyWith(
                              fontSize: 11, color: ZveltTokens.text3)),
                    ),
                    const SizedBox(height: 9),
                    for (var i = 0; i < _presets.length; i++) ...[
                      _presetRow(_presets[i]),
                      if (i < _presets.length - 1) const SizedBox(height: 9),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Preset row (HTML 807–813)
  Widget _presetRow(({String time, String title, String sub}) p) {
    return InkWell(
      onTap: () => _pickPreset(p),
      borderRadius: BorderRadius.circular(ZveltTokens.rControl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surface2Grad,
          borderRadius: BorderRadius.circular(ZveltTokens.rControl),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(p.time,
                  style: ZType.bodyS.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ZveltTokens.brand)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title,
                      style: ZType.bodyM.copyWith(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(p.sub,
                      style: ZType.bodyS.copyWith(
                          fontSize: 11.5, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x26F58214),
                border: Border.all(color: const Color(0x66F58214)),
              ),
              child:
                  const Icon(AppIcons.plus, size: 14, color: ZveltTokens.brand),
            ),
          ],
        ),
      ),
    );
  }
}
