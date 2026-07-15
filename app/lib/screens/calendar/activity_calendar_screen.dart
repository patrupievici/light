import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../theme/zvelt_tokens.dart';
import '../../models/activity_kind.dart';
import '../../services/_crash_reporter.dart';
import '../../services/workout_service.dart';
import '../../services/activities_service.dart';
import '../../services/activity_calendar_store.dart';
import '../../services/planned_workout_reminder_service.dart';
import '../../services/planned_workouts_service.dart';
import '../../widgets/zvelt_secondary_button.dart';

/// Calendar: gym days from server + alergare, înot, etc. logate local.
/// UI: [table_calendar](https://pub.dev/packages/table_calendar) — Apache-2.0.
class ActivityCalendarScreen extends StatefulWidget {
  const ActivityCalendarScreen({super.key});

  @override
  State<ActivityCalendarScreen> createState() => _ActivityCalendarScreenState();
}

class _ActivityCalendarScreenState extends State<ActivityCalendarScreen> {
  final _workouts = WorkoutService();
  final _activitiesApi = ActivitiesService();
  final _store = ActivityCalendarStore();
  final _plannedApi = PlannedWorkoutsService();

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  /// Cheie `yyyy-MM-dd` (local civil, aliniat cu server + tzOffset) → tipuri.
  Map<String, Set<ActivityKind>> _byDay = {};
  Map<String, List<ManualCardioSession>> _manualByDay = {};
  Map<String, List<PlannedWorkoutEntry>> _plannedByDay = {};
  Map<String, NutritionDayEntry> _nutritionByDay = {};
  bool _loading = true;

  /// True after a server sync attempt failed and we're rendering cached data
  /// only — surfaces a discrete badge instead of an annoying SnackBar.
  bool _offlineCached = false;

  /// Avoid hammering the backend when the user pages quickly between months.
  /// Forced (pull-to-refresh) calls bypass this window. QA P1.2.
  static const Duration _kSyncThrottle = Duration(minutes: 5);

  static String _ymdLocal(DateTime d) {
    final l = d.toLocal();
    final m = l.month.toString().padLeft(2, '0');
    final day = l.day.toString().padLeft(2, '0');
    return '${l.year}-$m-$day';
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _reload();
    // Fire-and-forget: hydrate from server in background; local data is
    // already rendering. QA P1.2 — cross-device history sync.
    _syncCalendarRange(force: false);
  }

  String _monthStr(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}';
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final next = <String, Set<ActivityKind>>{};
    var manualMap = <String, List<ManualCardioSession>>{};
    var plannedMap = <String, List<PlannedWorkoutEntry>>{};
    var nutritionMap = <String, NutritionDayEntry>{};

    final tzOff = DateTime.now().timeZoneOffset.inMinutes;

    // Cross-device server gym days (cached locally after first sync).
    // Renders immediately so calendar dots show before the network call returns.
    // QA P1.2.
    try {
      final cachedServerDays = await _store.loadServerGymDays();
      for (final key in cachedServerDays) {
        next.putIfAbsent(key, () => {}).add(ActivityKind.gym);
      }
    } catch (e, st) {
      reportError(e, st, reason: 'calendar:load-workouts');
    }

    try {
      final days = await _activitiesApi.getCalendarMonth(
        _monthStr(_focusedDay),
        tzOffsetMinutes: tzOff,
        refresh: true,
      );
      days.forEach((key, v) {
        final types = (v['types'] as List<dynamic>?) ?? [];
        for (final t in types) {
          final kind = ActivityKind.tryParse(t?.toString());
          if (kind != null) next.putIfAbsent(key, () => {}).add(kind);
        }
        final p = (v['planned'] as List<dynamic>?) ?? const [];
        if (p.isNotEmpty) {
          plannedMap[key] = p
              .whereType<Map>()
              .map(
                (e) => PlannedWorkoutEntry(
                  id: e['id']?.toString() ?? '',
                  dayYmd: key,
                  title: e['title']?.toString() ?? 'Planned session',
                  kind: ActivityKind.tryParse(e['kind']?.toString()) ??
                      ActivityKind.gym,
                  completed: e['status']?.toString() == 'completed',
                ),
              )
              .toList();
          for (final entry in plannedMap[key]!) {
            next.putIfAbsent(key, () => {}).add(entry.kind);
          }
        }

        // Parse nutrition data
        final nutritionData = v['nutrition'];
        if (nutritionData != null) {
          final nutritionEntry = NutritionDayEntry.fromJson(nutritionData);
          if (nutritionEntry != null) {
            nutritionMap[key] = nutritionEntry;
          }
        }
      });
    } catch (e, st) {
      reportError(e, st, reason: 'calendar:summary-load');
      try {
        var page = 1;
        const maxPages = 25;
        const limit = 50;
        final completedGymDays = <String>{};
        while (page <= maxPages) {
          final res = await _workouts.getWorkouts(page: page, limit: limit);
          for (final w in res.data) {
            if (w.status == 'draft') continue;
            final key = _ymdLocal(w.startedAt);
            next.putIfAbsent(key, () => {}).add(ActivityKind.gym);
            completedGymDays.add(key);
          }
          if (page >= res.meta.totalPages || res.data.isEmpty) break;
          page++;
        }
        await _store.markGymPlannedCompletedForDays(completedGymDays);
      } catch (e2, st2) {
        reportError(e2, st2, reason: 'calendar:fallback-paged-load');
      }
    }

    try {
      final manual = await _store.loadAll();
      manual.forEach((key, kinds) {
        next.putIfAbsent(key, () => {});
        next[key]!.addAll(kinds);
      });
    } catch (e, st) {
      reportError(e, st, reason: 'calendar:store-load-all');
    }

    try {
      manualMap = await _store.loadSyncedManualSessions();
      manualMap.forEach((key, sessions) {
        next.putIfAbsent(key, () => {});
        for (final s in sessions) {
          next[key]!.add(s.kind);
        }
      });
    } catch (e, st) {
      reportError(e, st, reason: 'calendar:store-load-manual');
    }

    if (!mounted) return;
    setState(() {
      _byDay = next;
      _manualByDay = manualMap;
      _plannedByDay = plannedMap;
      _nutritionByDay = nutritionMap;
      _loading = false;
    });
  }

  /// Background sync: pulls gym workout dates (visible month ± 2) from the
  /// server, merges into the local sqflite/prefs cache, and re-renders.
  /// Silent on failure (calendar stays usable offline). QA P1.2.
  ///
  /// Backend dependency: `GET /v1/me/workouts/calendar` — see [WorkoutService.getWorkoutCalendar].
  Future<void> _syncCalendarRange({required bool force}) async {
    try {
      if (!force) {
        final last = await _store.getLastCalendarSync();
        if (last != null &&
            DateTime.now().toUtc().difference(last) < _kSyncThrottle) {
          return;
        }
      }
      final anchor = DateTime(_focusedDay.year, _focusedDay.month, 1);
      final from = DateTime(anchor.year, anchor.month - 2, 1);
      final to =
          DateTime(anchor.year, anchor.month + 3, 0); // last day of +2 month
      final dates = await _workouts.getWorkoutCalendar(from: from, to: to);
      if (dates.isEmpty) {
        // 404 / empty range — backend may not have the endpoint yet. Still a
        // "success" from the sync standpoint; clear any prior offline badge.
        await _store.setLastCalendarSync(DateTime.now().toUtc());
        if (!mounted) return;
        if (_offlineCached) setState(() => _offlineCached = false);
        return;
      }
      final keys = dates.map(_ymdLocal).toSet();
      await _store.mergeServerGymDays(keys);
      await _store.setLastCalendarSync(DateTime.now().toUtc());
      if (!mounted) return;
      setState(() {
        for (final k in keys) {
          _byDay.putIfAbsent(k, () => {}).add(ActivityKind.gym);
        }
        _offlineCached = false;
      });
    } on CalendarAuthException {
      // Silently leave cached data in place; AuthGate will redirect if needed.
      if (!mounted) return;
      setState(() => _offlineCached = true);
    } catch (e, st) {
      reportError(e, st, reason: 'calendar:server-sync');
      if (!mounted) return;
      setState(() => _offlineCached = true);
    }
  }

  Future<void> _refreshAll() async {
    await _reload();
    await _syncCalendarRange(force: true);
  }

  List<ActivityKind> _kindsForDay(DateTime day) {
    final key = _ymdLocal(day);
    final set = _byDay[key];
    if (set == null || set.isEmpty) return [];
    const order = ActivityKind.values;
    final list = set.toList();
    list.sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    return list;
  }

  Future<void> _logActivity(DateTime day) async {
    final picked = await showModalBottomSheet<ActivityKind>(
      context: context,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(ZveltTokens.s5,
                    ZveltTokens.s2, ZveltTokens.s5, ZveltTokens.s3),
                child: Text(
                  'Log activity',
                  style: TextStyle(
                    color: ZveltTokens.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...ActivityKind.values
                  .where((k) => k != ActivityKind.gym)
                  .map((k) {
                return ListTile(
                  leading: Icon(k.icon, color: k.color),
                  title:
                      Text(k.label, style: TextStyle(color: ZveltTokens.text)),
                  onTap: () => Navigator.pop(ctx, k),
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final key = _ymdLocal(day);
    await _store.add(key, picked);
    await _reload();
  }

  Widget _macroBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: ZveltTokens.s2, vertical: ZveltTokens.s1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _logManualSessionWithStats(DateTime day) async {
    final key = _ymdLocal(day);
    final distCtrl = TextEditingController();
    final durCtrl = TextEditingController();

    ActivityKind selected = ActivityKind.run;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: ZveltTokens.surface,
          title: Text('Log cardio session',
              style: TextStyle(color: ZveltTokens.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Optional: distance (km) and duration (min)',
                  style: TextStyle(color: ZveltTokens.text2, fontSize: 13),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ActivityKind>(
                  initialValue: selected,
                  dropdownColor: ZveltTokens.bg2,
                  style: TextStyle(color: ZveltTokens.text),
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: ActivityKind.values
                      .where((k) => k != ActivityKind.gym)
                      .map((k) =>
                          DropdownMenuItem(value: k, child: Text(k.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setSt(() => selected = v);
                  },
                ),
                TextField(
                  controller: distCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: ZveltTokens.text),
                  decoration: const InputDecoration(labelText: 'Distance (km)'),
                ),
                TextField(
                  controller: durCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: ZveltTokens.text),
                  decoration:
                      const InputDecoration(labelText: 'Duration (min)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) {
      distCtrl.dispose();
      durCtrl.dispose();
      return;
    }

    final dist = double.tryParse(distCtrl.text.replaceAll(',', '.'));
    final dur = int.tryParse(durCtrl.text.trim());
    distCtrl.dispose();
    durCtrl.dispose();

    await _store.addManualSession(
      key,
      ManualCardioSession(kind: selected, distanceKm: dist, durationMin: dur),
    );
    await _reload();
  }

  void _showDayDetails(DateTime day) {
    final key = _ymdLocal(day);
    final kinds = _kindsForDay(day);
    final sessions = List<ManualCardioSession>.from(_manualByDay[key] ?? []);
    final planned = List<PlannedWorkoutEntry>.from(_plannedByDay[key] ?? []);
    final nutrition = _nutritionByDay[key];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(ZveltTokens.s5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  key,
                  style: TextStyle(
                    color: ZveltTokens.text2,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                // Nutrition section
                if (nutrition != null) ...[
                  Container(
                    padding: const EdgeInsets.all(ZveltTokens.s3),
                    decoration: BoxDecoration(
                      color: ZveltTokens.bg2,
                      borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🔥 Daily Nutrition Target',
                          style: TextStyle(
                            color: ZveltTokens.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${nutrition.calories} calories',
                          style: const TextStyle(
                            color: ZveltTokens.brand,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _macroBadge('🥩 ${nutrition.proteinG}g protein',
                                ZveltTokens.info),
                            const SizedBox(width: 6),
                            _macroBadge('🌾 ${nutrition.carbsG}g carbs',
                                ZveltTokens.warn),
                            const SizedBox(width: 6),
                            _macroBadge(
                                '🥑 ${nutrition.fatG}g fat', ZveltTokens.sleep),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Goal: ${nutrition.goal.replaceAll('_', ' ').toUpperCase()}',
                          style: TextStyle(
                            color: ZveltTokens.text2,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (kinds.isEmpty &&
                    sessions.isEmpty &&
                    planned.isEmpty &&
                    nutrition == null)
                  Text(
                    'No activities logged this day.',
                    style: TextStyle(color: ZveltTokens.text2),
                  )
                else ...[
                  ...planned.map((p) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        p.kind.icon,
                        color: p.completed
                            ? ZveltTokens.success
                            : ZveltTokens.brand,
                      ),
                      title: Text(p.title,
                          style: TextStyle(color: ZveltTokens.text)),
                      subtitle: Text(
                        p.completed ? 'Completed' : 'Pending',
                        style: TextStyle(
                          color: p.completed
                              ? ZveltTokens.success
                              : ZveltTokens.brand,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: p.completed
                                ? 'Mark as not done'
                                : 'Mark as completed',
                            icon: Icon(
                              p.completed
                                  ? AppIcons.badge_check
                                  : AppIcons.circle,
                              color: p.completed
                                  ? ZveltTokens.success
                                  : ZveltTokens.text2,
                            ),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              final nextCompleted = !p.completed;
                              try {
                                await _plannedApi.updateStatus(
                                  p.id,
                                  nextCompleted ? 'completed' : 'pending',
                                );
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          "Couldn't update status. ${e.toString().replaceFirst('Exception: ', '')}"),
                                    ),
                                  );
                                }
                                return;
                              }
                              if (nextCompleted) {
                                await PlannedWorkoutReminderService.instance
                                    .cancelForPlan(p.id);
                              } else {
                                await PlannedWorkoutReminderService.instance
                                    .scheduleForPlannedEntries(
                                        [p.copyWith(completed: false)]);
                              }
                              await _reload();
                            },
                          ),
                          IconButton(
                            tooltip: 'Remove planned session',
                            icon: Icon(AppIcons.cross_small,
                                color: ZveltTokens.text2, size: 20),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              try {
                                await _plannedApi.remove(p.id);
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          "Couldn't remove plan. ${e.toString().replaceFirst('Exception: ', '')}"),
                                    ),
                                  );
                                }
                                return;
                              }
                              await PlannedWorkoutReminderService.instance
                                  .cancelForPlan(p.id);
                              await _reload();
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  ...kinds.asMap().entries.map((e) {
                    final k = e.value;
                    final isGym = k == ActivityKind.gym;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(k.icon, color: k.color),
                      title: Text(k.label,
                          style: TextStyle(color: ZveltTokens.text)),
                      trailing: isGym
                          ? null
                          : IconButton(
                              tooltip: 'Remove activity',
                              icon: Icon(AppIcons.cross_small,
                                  color: ZveltTokens.text2, size: 20),
                              onPressed: () async {
                                Navigator.pop(ctx);
                                final manual = await _store.loadAll();
                                final list =
                                    List<ActivityKind>.from(manual[key] ?? []);
                                final idx = list.indexOf(k);
                                if (idx >= 0) {
                                  await _store.removeAt(key, idx);
                                  await _reload();
                                }
                              },
                            ),
                    );
                  }),
                  ...sessions.asMap().entries.map((e) {
                    final i = e.key;
                    final s = e.value;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(s.kind.icon, color: s.kind.color),
                      title: Text(s.kind.label,
                          style: TextStyle(color: ZveltTokens.text)),
                      subtitle: Text(s.subtitle,
                          style: TextStyle(
                              color: ZveltTokens.text2, fontSize: 12)),
                      trailing: IconButton(
                        tooltip: 'Remove session',
                        icon: Icon(AppIcons.cross_small,
                            color: ZveltTokens.text2, size: 20),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _store.removeManualSessionAt(key, i);
                          await _reload();
                        },
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 12),
                ZveltSecondaryButton(
                  label: 'Quick tag',
                  icon: AppIcons.plus,
                  onTap: () {
                    Navigator.pop(ctx);
                    _logActivity(day);
                  },
                ),
                const SizedBox(height: 8),
                ZveltSecondaryButton(
                  label: 'Log distance / time',
                  icon: AppIcons.ruler_horizontal,
                  onTap: () {
                    Navigator.pop(ctx);
                    _logManualSessionWithStats(day);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        title: const Text('Activity calendar'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.refresh),
            tooltip: 'Refresh & sync',
            onPressed: _loading ? null : _refreshAll,
          ),
        ],
      ),
      floatingActionButton: _selectedDay != null
          ? FloatingActionButton.extended(
              onPressed: () => _logActivity(_selectedDay!),
              backgroundColor: ZveltTokens.brand,
              foregroundColor: ZveltTokens.onBrand,
              icon: const Icon(AppIcons.plus),
              label: const Text('Log activity'),
            )
          : null,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: ZveltTokens.brand))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      ZveltTokens.s4, ZveltTokens.s2, ZveltTokens.s4, 0),
                  child: Row(
                    children: [
                      Expanded(child: _Legend()),
                      if (_offlineCached)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: ZveltTokens.s2,
                              vertical: ZveltTokens.s1),
                          decoration: BoxDecoration(
                            color: ZveltTokens.text2.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(ZveltTokens.rPill),
                          ),
                          child: Text(
                            'Offline — cached',
                            style: TextStyle(
                              color: ZveltTokens.text2,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TableCalendar<ActivityKind>(
                    firstDay: DateTime.utc(2019, 1, 1),
                    lastDay: DateTime.utc(2032, 12, 31),
                    focusedDay: _focusedDay,
                    calendarFormat: _calendarFormat,
                    selectedDayPredicate: (d) =>
                        _selectedDay != null && isSameDay(_selectedDay!, d),
                    eventLoader: _kindsForDay,
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      weekendTextStyle: TextStyle(color: ZveltTokens.text2),
                      defaultTextStyle: TextStyle(color: ZveltTokens.text),
                      disabledTextStyle: TextStyle(
                          color: ZveltTokens.text2.withValues(alpha: 0.4)),
                      selectedDecoration: const BoxDecoration(
                        color: ZveltTokens.brand,
                        shape: BoxShape.circle,
                      ),
                      selectedTextStyle: const TextStyle(
                          color: ZveltTokens.onBrand,
                          fontWeight: FontWeight.w700),
                      todayDecoration: BoxDecoration(
                        border:
                            Border.all(color: ZveltTokens.brand, width: 1.5),
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle: TextStyle(
                          color: ZveltTokens.text, fontWeight: FontWeight.w600),
                      defaultDecoration:
                          const BoxDecoration(shape: BoxShape.circle),
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonVisible: true,
                      titleCentered: true,
                      formatButtonShowsNext: false,
                      formatButtonDecoration: BoxDecoration(
                        color: ZveltTokens.bg2,
                        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                      ),
                      formatButtonTextStyle:
                          TextStyle(color: ZveltTokens.text, fontSize: 13),
                      titleTextStyle: TextStyle(
                          color: ZveltTokens.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                      leftChevronIcon: Icon(AppIcons.angle_small_left,
                          color: ZveltTokens.text2),
                      rightChevronIcon: Icon(AppIcons.angle_small_right,
                          color: ZveltTokens.text2),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle:
                          TextStyle(color: ZveltTokens.text2, fontSize: 12),
                      weekendStyle:
                          TextStyle(color: ZveltTokens.text2, fontSize: 12),
                    ),
                    onDaySelected: (selected, focused) {
                      setState(() {
                        _selectedDay = selected;
                        _focusedDay = focused;
                      });
                      _showDayDetails(selected);
                    },
                    onFormatChanged: (f) => setState(() => _calendarFormat = f),
                    onPageChanged: (f) {
                      setState(() => _focusedDay = f);
                      _reload();
                      _syncCalendarRange(force: false);
                    },
                    calendarBuilders: CalendarBuilders(
                      markerBuilder: (context, day, events) {
                        final key = _ymdLocal(day);
                        final planned =
                            _plannedByDay[key] ?? const <PlannedWorkoutEntry>[];
                        if (events.isEmpty && planned.isEmpty) return null;
                        if (planned.isNotEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 1),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: planned.take(3).map((p) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 1),
                                  child: Icon(
                                    p.kind.icon,
                                    size: 10,
                                    color: p.completed
                                        ? ZveltTokens.success
                                        : ZveltTokens.brand,
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: events.take(4).map((e) {
                              return Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 1.5),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: e.color,
                                  shape: BoxShape.circle,
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const chips = [
      ActivityKind.gym,
      ActivityKind.run,
      ActivityKind.swim,
      ActivityKind.cycle,
      ActivityKind.walk,
      ActivityKind.other,
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: chips
          .map(
            (k) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: k.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  k == ActivityKind.gym ? 'Gym' : k.label.split(' ').first,
                  style: TextStyle(color: ZveltTokens.text2, fontSize: 11),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}
