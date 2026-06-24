import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';
import '../../services/_crash_reporter.dart';
import '../../services/workout_service.dart';

/// Calendar heatmap stil GitHub — arată densitatea antrenamentelor pe ultimele
/// 365 zile, alimentat din `GET /v1/me/workouts/heatmap?year=YYYY` (QA P1.13).
///
/// Comportament:
///   - Loading: shimmer subtil pe grilă (celulele păstrează structura).
///   - 404 (backend not shipped): grid gol, fără mesaj de eroare — feature
///     degradează curat până la livrarea endpoint-ului.
///   - Eroare auth/rețea/5xx: grid gol + notă inline discretă.
///   - Success: scala 0 / 1–2 / 3–5 / 6+ peste accentul amber al temei.
class WorkoutConsistencyHeatmap extends StatefulWidget {
  const WorkoutConsistencyHeatmap({super.key});

  @override
  State<WorkoutConsistencyHeatmap> createState() => _WorkoutConsistencyHeatmapState();
}

class _WorkoutConsistencyHeatmapState extends State<WorkoutConsistencyHeatmap> {
  final _workouts = WorkoutService();
  bool _loading = true;
  bool _loadFailed = false;
  Map<String, int> _workoutDays = {};
  int _totalWorkouts = 0;
  int _currentStreak = 0;
  int _longestStreak = 0;

  // Memoized heatmap grid. _buildWeeks walks ~365 days + ~53 week records and
  // depends only on (_workoutDays, today's date), so we cache it and recompute
  // only when _workoutDays changes (in _load) or the day rolls over (detected
  // in build via a different today-ymd).
  List<({String monthName, bool showMonthLabel, List<({int sessions})> days})> _weeks =
      const [];
  String? _weeksTodayYmd;

  static const int _gridDays = 365;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    try {
      // Heatmap covers a rolling 365-day window. If that window straddles
      // year boundaries we fetch both years and merge — backend is the truth.
      final thisYear = await _workouts.getWorkoutHeatmap(year: now.year);
      Map<String, int> prevYear = const {};
      final windowStart = now.subtract(const Duration(days: _gridDays - 1));
      if (windowStart.year != now.year) {
        try {
          prevYear = await _workouts.getWorkoutHeatmap(year: windowStart.year);
        } on HeatmapRequestException {
          // Best-effort: if previous year fails we still show current year.
          prevYear = const {};
        }
      }

      final merged = <String, int>{...prevYear, ...thisYear};
      final streaks = _calculateStreaks(merged, now);
      final total = merged.values.fold<int>(0, (a, b) => a + b);

      if (!mounted) return;
      setState(() {
        _workoutDays = merged;
        _totalWorkouts = total;
        _currentStreak = streaks.current;
        _longestStreak = streaks.longest;
        _loading = false;
        _loadFailed = false;
        // Rebuild the memoized grid now that _workoutDays changed.
        _weeksTodayYmd = _ymd(now);
        _weeks = _buildWeeks(now);
      });
    } on HeatmapRequestException {
      // Auth / server failure — show empty grid + inline note (no snackbar).
      if (!mounted) return;
      setState(() {
        _workoutDays = const {};
        _totalWorkouts = 0;
        _currentStreak = 0;
        _longestStreak = 0;
        _loading = false;
        _loadFailed = true;
        _weeksTodayYmd = _ymd(now);
        _weeks = _buildWeeks(now);
      });
    } catch (e, st) {
      reportError(e, st, reason: 'heatmap:load');
      // Network / timeout / unexpected — same graceful path.
      if (!mounted) return;
      setState(() {
        _workoutDays = const {};
        _totalWorkouts = 0;
        _currentStreak = 0;
        _longestStreak = 0;
        _loading = false;
        _loadFailed = true;
        _weeksTodayYmd = _ymd(now);
        _weeks = _buildWeeks(now);
      });
    }
  }

  ({int current, int longest}) _calculateStreaks(Map<String, int> workoutDays, DateTime today) {
    int currentStreak = 0;
    int longestStreak = 0;
    int tempStreak = 0;
    bool currentLocked = false;

    for (int i = 0; i < _gridDays; i++) {
      final date = today.subtract(Duration(days: i));
      final dateStr = _ymd(date);
      if (workoutDays.containsKey(dateStr)) {
        tempStreak++;
        if (!currentLocked) currentStreak = tempStreak;
        if (tempStreak > longestStreak) longestStreak = tempStreak;
      } else {
        if (i == 0) {
          // No workout today yet — current streak is whatever we accrued
          // counting backwards from yesterday; keep walking but stop updating
          // `currentStreak` after the first gap.
        } else {
          currentLocked = true;
        }
        tempStreak = 0;
      }
    }

    return (current: currentStreak, longest: longestStreak);
  }

  static String _ymd(DateTime d) {
    final l = DateTime(d.year, d.month, d.day);
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return _buildHeatmap();
  }

  Widget _buildHeatmap() {
    final today = DateTime.now();
    // Render the memoized grid. Recompute only if it was never built or the day
    // rolled over since the last computation (memo key = today-ymd + the
    // _workoutDays that produced it, which _load refreshes on data change).
    final todayYmd = _ymd(today);
    if (_weeksTodayYmd != todayYmd) {
      _weeksTodayYmd = todayYmd;
      _weeks = _buildWeeks(today);
    }
    final weeks = _weeks;

    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Workout Consistency',
                style: ZType.h4.copyWith(fontWeight: FontWeight.w700),
              ),
              Row(
                children: [
                  _buildStatBadge('🔥 $_currentStreak', 'Current'),
                  const SizedBox(width: ZveltTokens.s2),
                  _buildStatBadge('⭐ $_longestStreak', 'Best'),
                ],
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            _loading
                ? 'Loading activity…'
                : '$_totalWorkouts sessions in last 365 days',
            style: ZType.monoS,
          ),
          const SizedBox(height: ZveltTokens.s4),

          // Heatmap grid (renders structure even while loading / on failure;
          // intensities just stay at level 0).
          Semantics(
            label:
                '$_totalWorkouts sessions in the last 365 days, current streak $_currentStreak days',
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      const SizedBox(height: 20),
                      ...['Mon', 'Wed', 'Fri'].map((day) => SizedBox(
                            height: 14,
                            child: Text(
                              day,
                              style: TextStyle(
                                fontSize: 11,
                                color: ZveltTokens.text2,
                              ),
                            ),
                          )),
                    ],
                  ),
                  const SizedBox(width: 4),
                  ...weeks.map((week) => Column(
                        children: [
                          SizedBox(
                            height: 20,
                            child: week.showMonthLabel
                                ? Text(
                                    week.monthName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: ZveltTokens.text2,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          ...week.days.map((day) => Container(
                                width: 12,
                                height: 12,
                                margin: const EdgeInsets.only(bottom: 2),
                                decoration: BoxDecoration(
                                  color: _loading
                                      ? ZveltTokens.surface3.withValues(alpha: 0.45)
                                      : _getHeatmapColor(day.sessions),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              )),
                        ],
                      )),
                ],
              ),
            ),
          ),

          const SizedBox(height: ZveltTokens.s3),

          // Legend + (optional) inline failure note. No SnackBar / dialog —
          // QA spec requires a non-intrusive message when load fails.
          Row(
            children: [
              if (_loadFailed)
                Expanded(
                  child: Text(
                    "Couldn't load activity history",
                    style: TextStyle(fontSize: 11, color: ZveltTokens.text2),
                  ),
                )
              else
                const Spacer(),
              Text(
                'Less',
                style: TextStyle(fontSize: 11, color: ZveltTokens.text2),
              ),
              const SizedBox(width: 4),
              ...[0, 1, 3, 6, 9].map((level) => Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: _getHeatmapColor(level),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )),
              const SizedBox(width: 4),
              Text(
                'More',
                style: TextStyle(fontSize: 11, color: ZveltTokens.text2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<({String monthName, bool showMonthLabel, List<({int sessions})> days})> _buildWeeks(DateTime today) {
    final weeks = <({String monthName, bool showMonthLabel, List<({int sessions})> days})>[];
    final startDate = today.subtract(const Duration(days: _gridDays - 1));
    var currentDate = startDate;
    int lastMonth = -1;
    const monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    while (currentDate.isBefore(today) || _sameDay(currentDate, today)) {
      final weekDays = <({int sessions})>[];
      final weekFirstMonth = currentDate.month;

      for (int i = 0; i < 7; i++) {
        if (currentDate.isAfter(today)) break;
        final dateStr = _ymd(currentDate);
        final sessions = _workoutDays[dateStr] ?? 0;
        weekDays.add((sessions: sessions));
        currentDate = currentDate.add(const Duration(days: 1));
      }

      if (weekDays.isEmpty) continue;
      final showMonth = weekFirstMonth != lastMonth;
      lastMonth = weekFirstMonth;
      weeks.add((
        monthName: monthNames[weekFirstMonth],
        showMonthLabel: showMonth,
        days: weekDays,
      ));
    }

    return weeks;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Color scale matches the QA spec brief: 0 empty, 1–2 light, 3–5 medium,
  /// 6+ max — mapped onto ZveltTokens.brand to match the brand.
  Color _getHeatmapColor(int sessions) {
    if (sessions <= 0) return ZveltTokens.surface3.withValues(alpha: 0.85);
    if (sessions <= 2) return ZveltTokens.brand.withValues(alpha: 0.3);
    if (sessions <= 5) return ZveltTokens.brand.withValues(alpha: 0.6);
    return ZveltTokens.brand; // 6+
  }

  Widget _buildStatBadge(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s2, vertical: ZveltTokens.s1),
      decoration: BoxDecoration(
        color: ZveltTokens.brand.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: ZType.monoS.copyWith(
              fontWeight: FontWeight.w700,
              color: ZveltTokens.brand,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: ZveltTokens.text2,
            ),
          ),
        ],
      ),
    );
  }
}
