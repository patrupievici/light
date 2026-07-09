import 'package:flutter/material.dart';

import '../../../theme/app_icons.dart';
import '../../../theme/zvelt_tokens.dart';
import '../../../widgets/z/z_card.dart';

/// A single completed training session, used to compute the monthly summary.
class HistorySession {
  const HistorySession({
    required this.date,
    required this.volumeKg,
    required this.sets,
    required this.muscleVolume,
  });

  /// Date-only day the session happened.
  final DateTime date;
  final double volumeKg;

  /// Work sets.
  final int sets;

  /// Capitalized muscle group → volume, e.g. `{'Back': 1234}`.
  final Map<String, double> muscleVolume;
}

/// A row in the Workout Log list.
class HistoryLogEntry {
  const HistoryLogEntry({
    required this.label,
    required this.subtitle,
    required this.prCount,
  });

  /// e.g. "Push Day".
  final String label;

  /// e.g. "Jun 23 · 48 min · 8,420 kg".
  final String subtitle;
  final int prCount;
}

/// A personal record row.
class HistoryPr {
  const HistoryPr({
    required this.exercise,
    required this.value,
    required this.category,
  });

  final String exercise, value, category;
}

/// An exercise progress chart.
class HistoryProgress {
  const HistoryProgress({
    required this.name,
    required this.trendLabel,
    required this.bars,
  });

  final String name, trendLabel;

  /// Bar heights, each in 0..1.
  final List<double> bars;
}

/// HISTORY sub-tab of the Train screen — 1:1 with the design handoff.
///
/// Returns a [Column] (not a Scaffold / scroll view): the parent supplies the
/// scrolling ListView. Every section is data-driven via constructor params and
/// renders honest empty states. Sections top→bottom (~20px gaps): Zvelt Coach
/// card · Full Calendar · Monthly Summary · Workout Log · Personal Records ·
/// Exercise Progress charts.
class TrainHistoryTab extends StatefulWidget {
  const TrainHistoryTab({
    super.key,
    this.dayStreak = 0,
    this.workoutsThisWeek = 0,
    this.trainedDays = const <DateTime>{},
    this.monthSessions = const <HistorySession>[],
    this.workoutLog = const <HistoryLogEntry>[],
    this.personalRecords = const <HistoryPr>[],
    this.progressCharts = const <HistoryProgress>[],
    this.onOpenWorkout,
    this.onOpenExerciseProgress,
  });

  final int dayStreak, workoutsThisWeek;

  /// Date-only days that had training (in ANY month).
  final Set<DateTime> trainedDays;
  final List<HistorySession> monthSessions;
  final List<HistoryLogEntry> workoutLog;
  final List<HistoryPr> personalRecords;
  final List<HistoryProgress> progressCharts;

  /// Tap a workout-log row.
  final VoidCallback? onOpenWorkout;

  /// Tap a progress chart.
  final VoidCallback? onOpenExerciseProgress;

  @override
  State<TrainHistoryTab> createState() => _TrainHistoryTabState();
}

class _TrainHistoryTabState extends State<TrainHistoryTab> {
  // Recomputed per access so the "today" highlight + displayed month don't go
  // stale if this kept-alive pane lives past midnight without a rebuild.
  DateTime get _today => DateUtils.dateOnly(DateTime.now());
  int _calOffset = 0;

  static const List<String> _monthNames = [
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
  ];
  static const List<String> _dow = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  DateTime get _displayedMonth =>
      DateTime(_today.year, _today.month + _calOffset);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _coachCard(),
        const SizedBox(height: 20),
        _calendarCard(),
        const SizedBox(height: 20),
        _monthlySummary(),
        const SizedBox(height: 20),
        _workoutLog(),
        const SizedBox(height: 20),
        _personalRecords(),
        const SizedBox(height: 20),
        _exerciseProgress(),
      ],
    );
  }

  // ── A. Zvelt Coach card ─────────────────────────────────────────────────────
  Widget _coachCard() {
    return ZCard(
      padding: EdgeInsets.zero,
      radius: ZveltTokens.rXl,
      shadow: ZveltTokens.shadowHero,
      child: SizedBox(
        width: double.infinity,
        height: 188,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -44,
              top: -44,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Mascot — behind/right so the copy stays readable.
            Positioned(
              right: -2,
              top: 8,
              bottom: -8,
              child: Image.asset(
                'assets/mascot/m-like.png',
                height: 175,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 132, 18),
              child: FractionallySizedBox(
                widthFactor: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'This Month',
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: ZveltTokens.brandDeep,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Keep it up, Athlete! 🔥',
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        height: 1.12,
                        color: ZveltTokens.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.workoutsThisWeek == 0
                          ? 'A fresh week — your next session starts the momentum.'
                          : "You're building real momentum. ${widget.workoutsThisWeek} ${widget.workoutsThisWeek == 1 ? 'session' : 'sessions'} logged this week.",
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontWeight: FontWeight.w400,
                        fontSize: 13,
                        height: 1.5,
                        color: ZveltTokens.text2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Flexible(
                          child:
                              _coachStat('${widget.dayStreak}', 'Day Streak'),
                        ),
                        Container(
                          width: 1,
                          height: 38,
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          color: ZveltTokens.hairline,
                        ),
                        Flexible(
                          child: _coachStat('${widget.workoutsThisWeek}',
                              'Workouts This Week'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coachStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: ZveltTokens.fontPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 26,
            height: 1.1,
            color: ZveltTokens.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: ZveltTokens.fontPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: ZveltTokens.text2,
          ),
        ),
      ],
    );
  }

  // ── B. Full Calendar ────────────────────────────────────────────────────────
  Widget _calendarCard() {
    final month = _displayedMonth;
    final label = '${_monthNames[month.month - 1]} ${month.year}';
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    // Dart weekday: Mon=1..Sun=7. Grid starts on Sunday → Sun maps to 0.
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;

    // Build a flat list of cells: leading blanks + day numbers, padded to a
    // whole number of 7-wide rows.
    final cells = <int?>[
      for (var i = 0; i < firstWeekday; i++) null,
      for (var d = 1; d <= daysInMonth; d++) d,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final rowCount = cells.length ~/ 7;

    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: ZveltTokens.shadowCard,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month nav row.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _navChevron(AppIcons.angle_small_left,
                  () => setState(() => _calOffset--)),
              Text(
                label,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: ZveltTokens.text,
                ),
              ),
              _navChevron(AppIcons.angle_small_right,
                  () => setState(() => _calOffset++)),
            ],
          ),
          const SizedBox(height: 12),
          // Day-of-week labels.
          Row(
            children: [
              for (final d in _dow)
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: ZveltTokens.text2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // Day grid.
          for (var r = 0; r < rowCount; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _dayCell(cells[r * 7 + c], month)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _navChevron(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 24, color: ZveltTokens.text2),
        ),
      ),
    );
  }

  Widget _dayCell(int? day, DateTime month) {
    if (day == null) return const SizedBox(height: 42);

    final date = DateUtils.dateOnly(DateTime(month.year, month.month, day));
    final isToday = date == _today;
    final isCompleted = widget.trainedDays.contains(date);

    Color? bg;
    BoxShape shape = BoxShape.rectangle;
    Color numColor = ZveltTokens.text;
    if (isToday) {
      bg = ZveltTokens.brand;
      shape = BoxShape.circle;
      numColor = Colors.white;
    } else if (isCompleted) {
      bg = ZveltTokens.brandTint;
    }

    return SizedBox(
      height: 42,
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: bg == null
              ? null
              : BoxDecoration(
                  color: bg,
                  shape: shape,
                  borderRadius: shape == BoxShape.rectangle
                      ? BorderRadius.circular(10)
                      : null,
                ),
          child: Text(
            '$day',
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
              color: numColor,
            ),
          ),
        ),
      ),
    );
  }

  // ── C. Monthly Summary ──────────────────────────────────────────────────────
  Widget _monthlySummary() {
    final month = _displayedMonth;
    final sessions = widget.monthSessions
        .where((s) => s.date.year == month.year && s.date.month == month.month)
        .toList();

    final workouts = sessions.length;
    final totalVolume = sessions.fold<double>(0, (sum, s) => sum + s.volumeKg);
    final totalSets = sessions.fold<int>(0, (sum, s) => sum + s.sets);

    final muscleTotals = <String, double>{};
    for (final s in sessions) {
      s.muscleVolume.forEach((muscle, vol) {
        muscleTotals[muscle] = (muscleTotals[muscle] ?? 0) + vol;
      });
    }
    String topMuscle = '—';
    double topVol = -1;
    muscleTotals.forEach((muscle, vol) {
      if (vol > topVol) {
        topVol = vol;
        topMuscle = muscle;
      }
    });

    final summary = <(String, String)>[
      ('Workouts', '$workouts'),
      ('Total volume', _formatVolume(totalVolume)),
      ('Total sets', '$totalSets'),
      ('Top muscle', topMuscle),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_monthNames[month.month - 1]} ${month.year}',
          style: TextStyle(
            fontFamily: ZveltTokens.fontPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
            letterSpacing: -0.01 * 18,
            color: ZveltTokens.text,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _summaryCard(summary[0])),
            const SizedBox(width: 10),
            Expanded(child: _summaryCard(summary[1])),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _summaryCard(summary[2])),
            const SizedBox(width: 10),
            Expanded(child: _summaryCard(summary[3])),
          ],
        ),
      ],
    );
  }

  String _formatVolume(double kg) {
    if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)} t';
    return '${kg.round()} kg';
  }

  Widget _summaryCard((String, String) data) {
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: ZveltTokens.shadowCard,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            data.$1,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontWeight: FontWeight.w400,
              fontSize: 12,
              color: ZveltTokens.text2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.$2,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 24,
              color: ZveltTokens.text,
            ),
          ),
        ],
      ),
    );
  }

  // ── D. Workout Log ──────────────────────────────────────────────────────────
  Widget _workoutLog() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: widget.workoutLog.isEmpty
          ? _emptyLine('No workouts logged yet.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.workoutLog.length; i++)
                  _logRow(widget.workoutLog[i],
                      last: i == widget.workoutLog.length - 1),
              ],
            ),
    );
  }

  Widget _logRow(HistoryLogEntry data, {required bool last}) {
    final prLabel = '${data.prCount} ${data.prCount == 1 ? 'PR' : 'PRs'}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onOpenWorkout,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(bottom: BorderSide(color: ZveltTokens.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(AppIcons.gym,
                    color: ZveltTokens.brand, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.label,
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: ZveltTokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.subtitle,
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        color: ZveltTokens.text2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                prLabel,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: ZveltTokens.text2,
                ),
              ),
              const SizedBox(width: 2),
              Icon(AppIcons.angle_small_right,
                  size: 20, color: ZveltTokens.text3),
            ],
          ),
        ),
      ),
    );
  }

  // ── E. Personal Records ─────────────────────────────────────────────────────
  Widget _personalRecords() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: widget.personalRecords.isEmpty
          ? _emptyLine('No personal records yet.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.personalRecords.length; i++)
                  _recordRow(widget.personalRecords[i],
                      last: i == widget.personalRecords.length - 1),
              ],
            ),
    );
  }

  Widget _recordRow(HistoryPr data, {required bool last}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border:
            last ? null : Border(bottom: BorderSide(color: ZveltTokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data.exercise,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: ZveltTokens.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.value,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: ZveltTokens.text2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            data.category,
            style: const TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: ZveltTokens.brand,
            ),
          ),
        ],
      ),
    );
  }

  // ── F. Exercise Progress charts ─────────────────────────────────────────────
  Widget _exerciseProgress() {
    if (widget.progressCharts.isEmpty) {
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: ZveltTokens.shadowCard,
        ),
        child: _emptyLine('Not enough data yet.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.progressCharts.length; i++) ...[
          _progressCard(widget.progressCharts[i]),
          if (i != widget.progressCharts.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _progressCard(HistoryProgress data) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: widget.onOpenExerciseProgress,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: ZveltTokens.shadowCard,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data.name,
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: ZveltTokens.text,
                      ),
                    ),
                  ),
                  Text(
                    data.trendLabel,
                    style: const TextStyle(
                      fontFamily: ZveltTokens.fontPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: ZveltTokens.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < data.bars.length; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      Expanded(
                        child: Container(
                          height: (data.bars[i].clamp(0.0, 1.0) * 52)
                              .clamp(2.0, 52.0),
                          decoration: BoxDecoration(
                            color: i >= data.bars.length - 3
                                ? ZveltTokens.brand
                                : ZveltTokens.brand2,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Honest empty-state line inside a card.
  Widget _emptyLine(String text) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(text, style: ZType.bodyS),
      ),
    );
  }
}
