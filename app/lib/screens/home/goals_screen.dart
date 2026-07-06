import 'package:flutter/material.dart';

import '../../services/activity_calendar_store.dart';
import '../../services/workout_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({
    super.key,
    required this.initialCurrentStreak,
    required this.initialTrainedDayKeys,
    this.targetStreak = 7,
  });

  final int initialCurrentStreak;
  final Set<String> initialTrainedDayKeys;
  final int targetStreak;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _workouts = WorkoutService();
  final _activity = ActivityCalendarStore();

  late int _currentStreak;
  late Set<String> _trainedDayKeys;
  late DateTime _visibleMonth;
  DateTime? _startDate;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _currentStreak = widget.initialCurrentStreak;
    _trainedDayKeys = Set<String>.from(widget.initialTrainedDayKeys);
    _startDate = _firstTrainedDate(_trainedDayKeys);
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _workouts.getWorkouts(limit: 200),
        _activity.loadManualSessions(),
      ]);
      final workouts = results[0] as WorkoutsResponse;
      final cardioByDay = results[1] as Map<String, List<ManualCardioSession>>;
      final trained = <String>{
        // UTC server timestamps → LOCAL day, matching the Activity calendar.
        for (final w in workouts.data)
          if (w.status != 'draft') _ymd((w.endedAt ?? w.startedAt).toLocal()),
        for (final entry in cardioByDay.entries)
          if (entry.value.isNotEmpty) entry.key,
      };
      if (!mounted) return;
      setState(() {
        _trainedDayKeys = trained;
        _currentStreak = _currentStreakFrom(trained, DateTime.now());
        _startDate = _firstTrainedDate(trained);
      });
    } catch (_) {
      // Keep the real snapshot passed from Home when the refresh cannot reach
      // the workout/cardio stores.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openNewGoal() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const NewGoalScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.targetStreak <= 0
        ? 0.0
        : (_currentStreak / widget.targetStreak).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: ZveltTokens.brand,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              ZveltTokens.screenPaddingH,
              ZveltTokens.s3,
              ZveltTokens.screenPaddingH,
              ZveltTokens.s8,
            ),
            children: [
              _GoalsTopBar(
                title: 'Goals',
                onRefresh: _load,
                onAdd: _openNewGoal,
                loading: _loading,
              ),
              const SizedBox(height: ZveltTokens.s5),
              _ConsistencyGoalDetailCard(
                currentStreak: _currentStreak,
                targetStreak: widget.targetStreak,
                progress: progress,
                visibleMonth: _visibleMonth,
                trainedDayKeys: _trainedDayKeys,
                startDate: _startDate,
                onPreviousMonth: () {
                  setState(() {
                    _visibleMonth =
                        DateTime(_visibleMonth.year, _visibleMonth.month - 1);
                  });
                },
                onNextMonth: _canGoNextMonth
                    ? () {
                        setState(() {
                          _visibleMonth = DateTime(
                            _visibleMonth.year,
                            _visibleMonth.month + 1,
                          );
                        });
                      }
                    : null,
              ),
              const SizedBox(height: ZveltTokens.s6),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _openNewGoal,
                  icon: const Icon(AppIcons.plus, size: 20),
                  label: Text(
                    'Add Goal',
                    style: ZType.bodyM.copyWith(
                      color: ZveltTokens.onBrand,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF56B4EE),
                    foregroundColor: ZveltTokens.onBrand,
                    elevation: 0,
                    minimumSize: const Size(158, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canGoNextMonth {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    return _visibleMonth.isBefore(current);
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseYmd(String key) {
    final parsed = DateTime.tryParse(key);
    if (parsed == null) return null;
    return DateUtils.dateOnly(parsed);
  }

  static DateTime? _firstTrainedDate(Set<String> trainedDayKeys) {
    final dates = [
      for (final key in trainedDayKeys)
        if (_parseYmd(key) != null) _parseYmd(key)!,
    ]..sort();
    return dates.isEmpty ? null : dates.first;
  }

  static int _currentStreakFrom(Set<String> trainedDays, DateTime today) {
    var day = DateUtils.dateOnly(today);
    if (!trainedDays.contains(_ymd(day))) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (trainedDays.contains(_ymd(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }
}

class NewGoalScreen extends StatelessWidget {
  const NewGoalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ZveltTokens.screenPaddingH,
            ZveltTokens.s3,
            ZveltTokens.screenPaddingH,
            ZveltTokens.s8,
          ),
          children: const [
            _SimpleTopBar(title: 'New Goal'),
            SizedBox(height: ZveltTokens.s5),
            _GoalOptionCard(
              title: 'Strength Goal',
              subtitle: 'Crush your personal records and get stronger!',
              avatarAsset: 'assets/mascot/m-like.png',
              avatarWidth: 86,
            ),
            SizedBox(height: ZveltTokens.s4),
            _GoalOptionCard(
              title: 'Bodyweight Goal',
              subtitle: 'Transform your body and reach your target weight!',
              avatarAsset: 'assets/mascot/m-think.png',
              avatarWidth: 74,
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalsTopBar extends StatelessWidget {
  const _GoalsTopBar({
    required this.title,
    required this.onRefresh,
    required this.onAdd,
    required this.loading,
  });

  final String title;
  final VoidCallback onRefresh;
  final VoidCallback onAdd;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          _TopIconButton(
            icon: AppIcons.arrow_small_left,
            label: 'Back',
            onTap: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: ZType.h2.copyWith(
                  color: ZveltTokens.text3,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          _TopIconButton(
            icon: AppIcons.refresh,
            label: 'Refresh',
            onTap: loading ? null : onRefresh,
          ),
          _TopIconButton(
            icon: AppIcons.plus,
            label: 'Add goal',
            onTap: onAdd,
          ),
        ],
      ),
    );
  }
}

class _SimpleTopBar extends StatelessWidget {
  const _SimpleTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          _TopIconButton(
            icon: AppIcons.arrow_small_left,
            label: 'Back',
            onTap: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Center(
              child: Text(
                title,
                style: ZType.h2.copyWith(
                  color: ZveltTokens.text3,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              color: onTap == null ? ZveltTokens.text4 : ZveltTokens.text3,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsistencyGoalDetailCard extends StatelessWidget {
  const _ConsistencyGoalDetailCard({
    required this.currentStreak,
    required this.targetStreak,
    required this.progress,
    required this.visibleMonth,
    required this.trainedDayKeys,
    required this.startDate,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final int currentStreak;
  final int targetStreak;
  final double progress;
  final DateTime visibleMonth;
  final Set<String> trainedDayKeys;
  final DateTime? startDate;
  final VoidCallback onPreviousMonth;
  final VoidCallback? onNextMonth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surfaceTinted,
        borderRadius: BorderRadius.circular(20),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Consistency Goal',
                  style: ZType.h2.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Icon(AppIcons.menu_dots_vertical,
                  color: ZveltTokens.text2, size: 22),
            ],
          ),
          const SizedBox(height: ZveltTokens.s5),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '$currentStreak',
                      style: ZType.displayL.copyWith(
                        color: ZveltTokens.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: ZveltTokens.s2),
                    const Icon(AppIcons.flame,
                        color: Color(0xFFFF7A00), size: 42),
                  ],
                ),
              ),
              _LargeGoalRing(progress: progress),
            ],
          ),
          const SizedBox(height: ZveltTokens.s5),
          Row(
            children: [
              Expanded(
                child: Text(
                  _monthLabel(visibleMonth),
                  style: ZType.h3.copyWith(
                    color: ZveltTokens.text2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _MonthButton(
                icon: AppIcons.angle_small_left,
                onTap: onPreviousMonth,
              ),
              const SizedBox(width: ZveltTokens.s2),
              _MonthButton(
                icon: AppIcons.angle_small_right,
                onTap: onNextMonth,
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s3),
          _GoalMonthCalendar(
            month: visibleMonth,
            trainedDayKeys: trainedDayKeys,
          ),
          const SizedBox(height: ZveltTokens.s5),
          _GoalInfoRow(
            icon: AppIcons.target,
            label: 'Target Streak',
            value: '$targetStreak',
            trailingIcon: AppIcons.flame,
          ),
          Divider(height: ZveltTokens.s5, color: ZveltTokens.borderStrong),
          _GoalInfoRow(
            icon: AppIcons.calendar,
            label: 'Start Date',
            value: startDate == null ? '--' : _shortDate(startDate!),
          ),
        ],
      ),
    );
  }

  static String _monthLabel(DateTime d) {
    const months = [
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
    return '${months[d.month - 1]} ${d.year}';
  }

  static String _shortDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _LargeGoalRing extends StatelessWidget {
  const _LargeGoalRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 138,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(138, 96),
            painter: _LargeGoalRingPainter(progress: progress),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              '${(progress * 100).round()}%',
              style: ZType.h2.copyWith(
                color: ZveltTokens.text,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LargeGoalRingPainter extends CustomPainter {
  const _LargeGoalRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(10, 4, size.width - 20, size.height + 44);
    final bg = Paint()
      ..color = ZveltTokens.surface.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 14;
    final fg = Paint()
      ..color = const Color(0xFFFF6B00)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 14;
    canvas.drawArc(rect, 3.1415926535, 3.1415926535, false, bg);
    canvas.drawArc(
      rect,
      3.1415926535,
      3.1415926535 * progress,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _LargeGoalRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _MonthButton extends StatelessWidget {
  const _MonthButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            icon,
            color: onTap == null ? ZveltTokens.text4 : ZveltTokens.text,
            size: 28,
          ),
        ),
      ),
    );
  }
}

class _GoalMonthCalendar extends StatelessWidget {
  const _GoalMonthCalendar({
    required this.month,
    required this.trainedDayKeys,
  });

  final DateTime month;
  final Set<String> trainedDayKeys;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final leading = first.weekday % 7;
    final totalCells = ((leading + days + 6) ~/ 7) * 7;
    const labels = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      decoration: BoxDecoration(
        color: ZveltTokens.surface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in labels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: ZType.h4.copyWith(
                        color: ZveltTokens.text4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s3),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalCells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final day = index - leading + 1;
              if (day < 1 || day > days) return const SizedBox.shrink();
              final date = DateTime(month.year, month.month, day);
              final key = _ymd(date);
              final trained = trainedDayKeys.contains(key);
              final today = DateUtils.isSameDay(date, DateTime.now());
              return _GoalDayCell(
                day: day,
                trained: trained,
                today: today,
              );
            },
          ),
        ],
      ),
    );
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _GoalDayCell extends StatelessWidget {
  const _GoalDayCell({
    required this.day,
    required this.trained,
    required this.today,
  });

  final int day;
  final bool trained;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final bg = trained ? const Color(0xFFFFB12B) : ZveltTokens.surface3;
    final fg = trained ? Colors.white : Colors.white.withValues(alpha: 0.9);
    return Center(
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: today
              ? Border.all(color: const Color(0xFFFFE100), width: 4)
              : null,
        ),
        child: trained && today
            ? const Icon(AppIcons.flame, color: Colors.white, size: 22)
            : Text(
                '$day',
                style: ZType.h4.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

class _GoalInfoRow extends StatelessWidget {
  const _GoalInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailingIcon,
  });

  final IconData icon;
  final String label;
  final String value;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: ZveltTokens.text4, size: 20),
        const SizedBox(width: ZveltTokens.s3),
        Expanded(
          child: Text(
            label,
            style: ZType.h4.copyWith(
              color: ZveltTokens.text2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: ZType.h4.copyWith(
            color: ZveltTokens.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: 6),
          Icon(trailingIcon, color: const Color(0xFFFF7A00), size: 22),
        ],
      ],
    );
  }
}

class _GoalOptionCard extends StatelessWidget {
  const _GoalOptionCard({
    required this.title,
    required this.subtitle,
    required this.avatarAsset,
    required this.avatarWidth,
  });

  final String title;
  final String subtitle;
  final String avatarAsset;
  final double avatarWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(ZveltTokens.s5),
      decoration: BoxDecoration(
        color: ZveltTokens.surfaceTinted,
        borderRadius: BorderRadius.circular(18),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ZType.h2.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: ZveltTokens.s2),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.h4.copyWith(
                    color: ZveltTokens.text2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Align(
            alignment: Alignment.bottomRight,
            child: ExcludeSemantics(
              child: Image.asset(
                avatarAsset,
                width: avatarWidth,
                height: 116,
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
