import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/activity_kind.dart';
import '../../services/activity_calendar_store.dart';
import '../../services/workout_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';

class StreakCalendarScreen extends StatefulWidget {
  const StreakCalendarScreen({super.key});

  @override
  State<StreakCalendarScreen> createState() => _StreakCalendarScreenState();
}

class _StreakCalendarScreenState extends State<StreakCalendarScreen> {
  final _workouts = WorkoutService();
  final _activityStore = ActivityCalendarStore();

  bool _loading = true;
  String? _error;
  _StreakData _data = _StreakData.empty();

  static const _orange = Color(0xFFC55D1B);
  static const _flame = Color(0xFFFFA51E);
  static const _softOrange = Color(0xFFFFE0A7);
  static const _calendarSoft = Color(0xFFE9E9F6);

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
      final results = await Future.wait<Object>([
        _loadCompletedWorkouts(),
        _activityStore.loadManualSessions(),
        _activityStore.loadAll(),
      ]);

      final workouts = results[0] as List<WorkoutDto>;
      final manual = results[1] as Map<String, List<ManualCardioSession>>;
      final activities = results[2] as Map<String, List<ActivityKind>>;

      final trained = <String>{};
      for (final w in workouts) {
        trained.add(_ymd(DateUtils.dateOnly(w.endedAt ?? w.startedAt)));
      }
      manual.forEach((day, sessions) {
        if (sessions.isNotEmpty) trained.add(day);
      });
      activities.forEach((day, items) {
        if (items.isNotEmpty) trained.add(day);
      });

      if (!mounted) return;
      setState(() {
        _data = _StreakData.fromTrainedDays(trained);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<List<WorkoutDto>> _loadCompletedWorkouts() async {
    final out = <WorkoutDto>[];
    for (var page = 1; page <= 6; page++) {
      final res = await _workouts.getWorkouts(page: page, limit: 50);
      out.addAll(res.data.where((w) => w.status != 'draft'));
      if (page >= res.meta.totalPages) break;
    }
    return out;
  }

  Future<void> _share() async {
    final text = _data.currentStreak == 1
        ? 'I am on a 1 day streak in Zvelt.'
        : 'I am on a ${_data.currentStreak} day streak in Zvelt.';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: RefreshIndicator(
        color: _flame,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _hero(context)),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                ZveltTokens.screenPaddingH,
                ZveltTokens.s6,
                ZveltTokens.screenPaddingH,
                MediaQuery.paddingOf(context).bottom + ZveltTokens.s6,
              ),
              sliver: SliverList.list(
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(
                        child: CircularProgressIndicator(color: _flame),
                      ),
                    )
                  else if (_error != null)
                    _ErrorCard(message: _error!, onRetry: _load)
                  else ...[
                    Text(
                      'Season Calendar',
                      style: ZType.h1.copyWith(
                        color: ZveltTokens.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: ZveltTokens.s4),
                    for (final month in _data.calendarMonths) ...[
                      _MonthCalendar(
                        month: month,
                        trainedDays: _data.trainedDays,
                        today: _data.today,
                        streakAtRisk: _data.isAtRiskToday,
                      ),
                      const SizedBox(height: ZveltTokens.s5),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    return Container(
      color: _orange,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 74,
              child: Row(
                children: [
                  const SizedBox(width: ZveltTokens.s2),
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(AppIcons.arrow_small_left,
                        color: _softOrange, size: 30),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      'Streaks',
                      textAlign: TextAlign.center,
                      style: ZType.h2.copyWith(
                        color: _softOrange,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(AppIcons.refresh,
                        color: Colors.white, size: 25),
                    onPressed: _load,
                  ),
                  IconButton(
                    tooltip: 'Share',
                    icon: const Icon(AppIcons.share,
                        color: Colors.white, size: 25),
                    onPressed: _loading || _error != null ? null : _share,
                  ),
                  const SizedBox(width: ZveltTokens.s2),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0x40FFFFFF)),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ZveltTokens.screenPaddingH,
                ZveltTokens.s8,
                ZveltTokens.screenPaddingH,
                ZveltTokens.s10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _loading ? '...' : '${_data.currentStreak}',
                          style: ZType.displayXL.copyWith(
                            color: Colors.white,
                            fontSize: 74,
                            fontWeight: FontWeight.w900,
                            height: 0.92,
                          ),
                        ),
                        const SizedBox(height: ZveltTokens.s4),
                        Text(
                          'current streak!',
                          style: ZType.h1.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _BigFlame(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.trainedDays,
    required this.today,
    required this.streakAtRisk,
  });

  final DateTime month;
  final Set<String> trainedDays;
  final DateTime today;
  final bool streakAtRisk;

  static const _weekdays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  @override
  Widget build(BuildContext context) {
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final first = DateTime(month.year, month.month, 1);
    final leading = first.weekday % 7;
    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++)
        _DayCell(
          day: DateTime(month.year, month.month, d),
          trained:
              trainedDays.contains(_ymd(DateTime(month.year, month.month, d))),
          isToday:
              DateUtils.isSameDay(today, DateTime(month.year, month.month, d)),
          atRisk: streakAtRisk &&
              DateUtils.isSameDay(today, DateTime(month.year, month.month, d)),
        ),
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ZveltTokens.borderStrong),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: _StreakCalendarScreenState._calendarSoft,
            padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4),
            child: Text(
              '${_monthName(month.month)} ${month.year}',
              textAlign: TextAlign.center,
              style: ZType.h2.copyWith(
                color: ZveltTokens.text2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZveltTokens.s4,
              ZveltTokens.s4,
              ZveltTokens.s4,
              ZveltTokens.s5,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final day in _weekdays)
                      Expanded(
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: ZType.h3.copyWith(
                            color: ZveltTokens.text4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: ZveltTokens.s4),
                GridView.count(
                  crossAxisCount: 7,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1,
                  children: cells,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.trained,
    required this.isToday,
    required this.atRisk,
  });

  final DateTime day;
  final bool trained;
  final bool isToday;
  final bool atRisk;

  @override
  Widget build(BuildContext context) {
    if (atRisk && !trained) {
      return Center(
        child: Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: Color(0xFFFFE21B),
            shape: BoxShape.circle,
          ),
          child: const Icon(AppIcons.exclamation,
              color: Color(0xFF111827), size: 22),
        ),
      );
    }

    final bg = trained
        ? _StreakCalendarScreenState._flame
        : isToday
            ? const Color(0xFFFFE6BB)
            : ZveltTokens.surface3;
    final fg =
        trained ? Colors.white : ZveltTokens.onBrand.withValues(alpha: 0.82);

    return Center(
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: isToday && trained
              ? Border.all(color: const Color(0xFFFFE21B), width: 3)
              : null,
        ),
        child: trained
            ? (isToday
                ? const Icon(AppIcons.flame, color: Colors.white, size: 20)
                : Text(
                    '${day.day}',
                    style: ZType.h4.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ))
            : Text(
                '${day.day}',
                style: ZType.h4.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

class _BigFlame extends StatelessWidget {
  const _BigFlame();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 112,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFD43B), Color(0xFFFF6B00)],
        ),
      ),
      child: const Icon(AppIcons.flame, color: Colors.white, size: 62),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Row(
        children: [
          const Icon(AppIcons.exclamation, color: ZveltTokens.error),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Text(
              message,
              style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _StreakData {
  _StreakData({
    required this.today,
    required this.calendarStart,
    required this.calendarEnd,
    required this.trainedDays,
    required this.currentStreak,
    required this.longestStreak,
  });

  final DateTime today;
  final DateTime calendarStart;
  final DateTime calendarEnd;
  final Set<String> trainedDays;
  final int currentStreak;
  final int longestStreak;

  bool get isAtRiskToday =>
      currentStreak > 0 && !trainedDays.contains(_ymd(today));

  List<DateTime> get calendarMonths {
    final months = <DateTime>[];
    var cursor = DateTime(calendarStart.year, calendarStart.month, 1);
    while (!cursor.isAfter(calendarEnd)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return months;
  }

  static _StreakData empty() => fromTrainedDays(const {});

  static _StreakData fromTrainedDays(Set<String> trained) {
    final today = DateUtils.dateOnly(DateTime.now());
    final calendarStart = DateTime(today.year, today.month - 2, 1);
    final calendarEnd = DateTime(today.year, today.month + 1, 0);
    final normalized = <String>{
      for (final day in trained)
        if (_parseYmd(day) != null) _ymd(_parseYmd(day)!),
    };

    return _StreakData(
      today: today,
      calendarStart: calendarStart,
      calendarEnd: calendarEnd,
      trainedDays: normalized,
      currentStreak: _currentStreak(normalized, today),
      longestStreak: _longestStreak(normalized),
    );
  }

  static int _currentStreak(Set<String> trained, DateTime today) {
    var day = DateUtils.dateOnly(today);
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

  static int _longestStreak(Set<String> trained) {
    final days = trained.map(_parseYmd).whereType<DateTime>().toList()..sort();
    var best = 0;
    var current = 0;
    DateTime? previous;
    for (final day in days) {
      if (previous != null && day.difference(previous).inDays == 1) {
        current++;
      } else {
        current = 1;
      }
      if (current > best) best = current;
      previous = day;
    }
    return best;
  }
}

DateTime? _parseYmd(String s) {
  final p = s.split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _monthName(int month) => const [
      '',
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
      'December',
    ][month];
