import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/activity_kind.dart';
import '../../models/social_feed_post.dart';
import '../../services/activity_calendar_store.dart';
import '../../services/feed_refresh_notifier.dart';
import '../../services/nutrition_service.dart';
import '../../services/profile_service.dart';
import '../../services/social_feed_service.dart';
import '../../services/muscle_recovery_service.dart';
import '../../services/stats_charts_service.dart';
import '../../services/workout_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/zvelt_main_nav_bar.dart';
import '../../widgets/muscle_map_widget.dart';
import '../../widgets/z/z_card.dart';
import '../../widgets/z/z_collapsible_chart_card.dart';
import '../../widgets/charts/recent_prs_card.dart';
import '../calendar/activity_calendar_screen.dart';
import '../workouts/workout_tracker_screen.dart';
import 'goals_screen.dart';
import 'streak_calendar_screen.dart';

/// HOME — the "today dashboard" from Razvan's light redesign (brief §7, mockup
/// screen 3). Greeting · Start-Workout hero · cardio · progress · latest friend activity.
/// Deliberately lean: no
/// biology / recovery / XP cards (those belong to the full app, not light).
///
/// Reuses the existing data layer — ProfileService, WorkoutService,
/// SocialFeedService — so it stays honest (real data or empty
/// state, never fabricated numbers).
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    this.onOpenProfile,
    this.onOpenNotifications,
    this.onOpenSettings,
    this.onOpenFood,
    this.onOpenFeed,
  });

  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenNotifications;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenFood;
  final VoidCallback? onOpenFeed;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _profile = ProfileService();
  final _workouts = WorkoutService();
  final _feed = SocialFeedService();
  final _recovery = MuscleRecoveryService();
  final _stats = StatsChartsService();
  final _nutrition = NutritionService.instance;

  bool _loading = true;
  Map<String, MuscleLevel> _muscleLevels = const {};

  String _displayName = 'Athlete';
  bool _workoutToday = false;
  int _currentStreak = 0;
  Set<String> _trainedDayKeys = const {};
  _Last14WorkoutStats _last14 = _Last14WorkoutStats.empty;
  double? _bodyweightKg;
  List<double> _bodyweightTrend = const [];
  // Weekly cardio (runs/rides/walks) — from ActivityCalendarStore.
  int _cardioCount = 0;
  double _cardioKm = 0;
  int _cardioMin = 0;
  String? _cardioLatestLine;
  SocialFeedPost? _friendPost;

  @override
  void initState() {
    super.initState();
    // Completion flows bump [RefreshScope.home] (WorkoutService.completeWorkout,
    // ActivityCalendarStore.addManualSession) — reload so "logged today" /
    // consistency / weekly cardio reflect sessions finished from ANY flow
    // (center ⚡ quick-launch, Train tab, GPS run), not just Home's hero button.
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

    final now = DateTime.now();
    final monday =
        DateUtils.dateOnly(now).subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));

    final results = await Future.wait([
      _safe(_profile.getMe()),
      // Same source of truth History uses (GET /v1/workouts). The old
      // getWorkoutCalendar hit a nonexistent endpoint and ALWAYS returned []
      // — Home showed "Not logged yet" / 0-consistency while History was right.
      _safe(_workouts.getWorkouts(limit: 50)),
      _safe(_feed.getFeed()),
      _safe(_recovery.getMuscleLevels(windowDays: 90)),
      // Weekly cardio summary (offline-first — written on every cardio save).
      _safe(ActivityCalendarStore().loadManualSessions()),
      _safe(_stats.getRecentPrs(days: 30)),
      _safe(_nutrition.loadNutritionHistory(days: 14)),
    ]);
    if (!mounted) return;

    final me = results[0] as Map<String, dynamic>?;
    final workoutsRes = results[1] as WorkoutsResponse?;
    final posts = (results[2] as List<SocialFeedPost>?) ?? const [];
    final muscleLevels = (results[3] as Map<String, MuscleLevel>?) ?? const {};
    final cardioByDay =
        (results[4] as Map<String, List<ManualCardioSession>>?) ?? const {};
    final recentPrs = (results[5] as List<RecentPr>?) ?? const <RecentPr>[];
    final nutritionHistory = (results[6] as List<NutritionDaySnapshot>?) ??
        const <NutritionDaySnapshot>[];

    // Completed gym sessions this week ('completed' or 'posted'; drafts out).
    // Server timestamps are UTC — attribute to the LOCAL calendar day, same
    // as the Activity calendar, or late-evening sessions land on the wrong
    // day and "logged today" fails (Romania is UTC+2/+3).
    final calendar = <DateTime>[
      for (final w in workoutsRes?.data ?? const <WorkoutDto>[])
        if (w.status != 'draft')
          DateUtils.dateOnly((w.endedAt ?? w.startedAt).toLocal()),
    ];

    final profile = me?['profile'] as Map<String, dynamic>?;
    final name = profile?['displayName'] as String?;
    final myId = me?['id'] as String?;
    final today = DateUtils.dateOnly(now);
    var workedOutToday = false;
    for (final d in calendar) {
      final dd = DateUtils.dateOnly(d);
      if (dd == today) workedOutToday = true;
    }

    // Weekly cardio aggregates (Mon–Sun window, latest session for the line).
    var cardioCount = 0;
    var cardioKm = 0.0;
    var cardioMin = 0;
    ManualCardioSession? latestCardio;
    DateTime? latestCardioDay;
    cardioByDay.forEach((key, sessions) {
      final d = DateTime.tryParse(key);
      if (d == null) return;
      final dd = DateUtils.dateOnly(d);
      if (dd.isBefore(monday) || dd.isAfter(sunday)) return;
      for (final s in sessions) {
        cardioCount++;
        cardioKm += s.distanceKm ?? 0;
        cardioMin += s.durationMin ?? 0;
        if (latestCardioDay == null || !dd.isBefore(latestCardioDay!)) {
          latestCardioDay = dd;
          latestCardio = s;
        }
      }
    });
    String? cardioLatestLine;
    if (latestCardio != null) {
      final kindLabel = switch (latestCardio!.kind) {
        ActivityKind.cycle => 'Ride',
        ActivityKind.walk => 'Walk',
        ActivityKind.swim => 'Swim',
        _ => 'Run',
      };
      cardioLatestLine = '$kindLabel · ${latestCardio!.subtitle}';
    }

    final completedWorkouts = (workoutsRes?.data ?? const <WorkoutDto>[])
        .where((w) => w.status != 'draft')
        .toList()
      ..sort((a, b) => _workoutDate(b).compareTo(_workoutDate(a)));
    final trainedKeys = <String>{
      for (final d in calendar) _homeYmd(d),
      for (final entry in cardioByDay.entries)
        if (entry.value.isNotEmpty) entry.key,
    };
    final streak = _currentStreakFrom(trainedKeys, today);
    final weightTrend = [
      for (final d in nutritionHistory)
        if (d.weightKg != null && d.weightKg! > 0) d.weightKg!,
    ];
    final profileBodyweight = _asDouble(profile?['bodyweightKg']);
    final bodyweightKg =
        weightTrend.isNotEmpty ? weightTrend.last : profileBodyweight;
    final last14 = _Last14WorkoutStats.fromWorkouts(
      completedWorkouts.take(14),
    ).copyWith(records: recentPrs.length);

    setState(() {
      _loading = false;
      _displayName =
          (name != null && name.trim().isNotEmpty) ? name.trim() : 'Athlete';
      _workoutToday = workedOutToday;
      _currentStreak = streak;
      _trainedDayKeys = trainedKeys;
      _last14 = last14;
      _bodyweightKg = bodyweightKg;
      _bodyweightTrend = weightTrend;
      _cardioCount = cardioCount;
      _cardioKm = cardioKm;
      _cardioMin = cardioMin;
      _cardioLatestLine = cardioLatestLine;
      _muscleLevels = muscleLevels;
      // "Friend activity" must be a FRIEND's post — the friends feed includes
      // the user's own posts, so drop those before taking the latest.
      final friendPosts =
          myId == null ? posts : posts.where((p) => p.userId != myId).toList();
      _friendPost = friendPosts.isNotEmpty ? friendPosts.first : null;
    });
  }

  Future<void> _startWorkout() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final workout = await _workouts.createWorkout();
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        builder: (_) => WorkoutTrackerScreen(
          workoutId: workout.id,
          onComplete: _load,
        ),
      ));
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: ZveltTokens.error,
      ));
    }
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
      _bodyweightTrend = _replaceLatestWeight(_bodyweightTrend, nextKg);
    });

    try {
      await _nutrition.updateWeight(nextKg, DateTime.now());
      try {
        await _profile.updateProfile(bodyweightKg: nextKg);
      } catch (_) {
        // The nutrition log is offline-first and remains the local source of
        // truth for this card. Profile sync can retry on the next successful
        // profile edit / app sync.
      }
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Bodyweight updated'),
          backgroundColor: ZveltTokens.success,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: ZveltTokens.error,
        ),
      );
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String get _todayLabel {
    const months = [
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
      'Dec',
    ];
    final n = DateTime.now();
    return 'Today, ${n.day} ${months[n.month - 1]}';
  }

  DateTime _workoutDate(WorkoutDto w) =>
      DateUtils.dateOnly((w.endedAt ?? w.startedAt).toLocal());

  static String _homeYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int _currentStreakFrom(Set<String> trainedDays, DateTime today) {
    var day = DateUtils.dateOnly(today);
    if (!trainedDays.contains(_homeYmd(day))) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (trainedDays.contains(_homeYmd(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static List<double> _replaceLatestWeight(List<double> values, double kg) {
    final next = List<double>.from(values);
    if (next.isEmpty) return [kg];
    next[next.length - 1] = kg;
    return next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: RefreshIndicator(
        color: ZveltTokens.brand,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            ZveltTokens.screenPaddingH,
            MediaQuery.paddingOf(context).top + ZveltTokens.s4,
            ZveltTokens.screenPaddingH,
            ZveltMainNavBar.reservedBottomHeight(context) + ZveltTokens.s4,
          ),
          children: [
            _header(),
            const SizedBox(height: ZveltTokens.s5),
            _coachCard(),
            const SizedBox(height: ZveltTokens.s6),
            const _Eyebrow('THIS WEEK'),
            const SizedBox(height: ZveltTokens.s3),
            _streakCalendarCard(),
            const SizedBox(height: ZveltTokens.s3),
            _consistencyGoalSection(),
            const SizedBox(height: ZveltTokens.s5),
            _last14WorkoutsSection(),
            const SizedBox(height: ZveltTokens.s3),
            _cardioWeekCard(),
            const SizedBox(height: ZveltTokens.s6),
            const _Eyebrow('MUSCLES'),
            const SizedBox(height: ZveltTokens.s3),
            _muscleSection(),
            const SizedBox(height: ZveltTokens.s6),
            const _Eyebrow('PROGRESS'),
            const SizedBox(height: ZveltTokens.s3),
            _progressCharts(),
            const SizedBox(height: ZveltTokens.s6),
            const _Eyebrow('FRIEND ACTIVITY'),
            const SizedBox(height: ZveltTokens.s3),
            _friendCard(),
          ],
        ),
      ),
    );
  }

  // ── Header — avatar (→ profile) + settings, then greeting block ────────────
  Widget _header() {
    final initial = _displayName.trim().isNotEmpty
        ? _displayName.trim()[0].toUpperCase()
        : 'A';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: widget.onOpenProfile,
              customBorder: const CircleBorder(),
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFC9CDF2), Color(0xFF9AA0E8)],
                  ),
                  boxShadow: ZveltTokens.shadowCard,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: ZType.h4.copyWith(color: Colors.white),
                ),
              ),
            ),
            const Spacer(),
            _CircleButton(
              icon: AppIcons.settings,
              onTap: widget.onOpenSettings,
              semanticLabel: 'Settings',
            ),
          ],
        ),
        const SizedBox(height: ZveltTokens.s5),
        Text('$_greeting,',
            style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
        Row(
          children: [
            Flexible(
              child: Text(
                _displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZType.h1,
              ),
            ),
            const SizedBox(width: 6),
            const Text('👋', style: TextStyle(fontSize: 22)),
          ],
        ),
        const SizedBox(height: 2),
        Text(_todayLabel,
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
      ],
    );
  }

  // ── Coach card — periwinkle gradient panel + 3D rabbit mascot ──────────────
  Widget _coachCard() {
    final msg = _workoutToday
        ? 'Nice work today. Recovery is where the muscle is built.'
        : "Ready to move? You're 1 workout away from keeping your streak.";
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _startWorkout,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 116,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: ZveltTokens.shadowCard,
          ),
          child: Row(
            children: [
              // mascot panel — fixed-size box, gradient fills, rabbit at bottom
              SizedBox(
                width: 104,
                height: 116,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [ZveltTokens.brandTint, ZveltTokens.surface],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Image.asset(
                        'assets/mascot/m-think.png',
                        height: 108,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 16, 18, 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ZVELT COACH',
                        style: ZType.bodyS.copyWith(
                          color: ZveltTokens.brand,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.06 * 11,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Flexible(
                        child: Text(
                          msg,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: ZType.bodyM.copyWith(
                            color: ZveltTokens.text,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Weekly cardio strip (count · km · min + latest session). Reads the same
  /// per-user store every cardio save writes, so it survives restarts and
  /// works offline. Tap → the Activity calendar with the full session list.
  Widget _streakCalendarCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const StreakCalendarScreen(),
          ),
        ),
        child: Container(
          height: 176,
          width: double.infinity,
          decoration: BoxDecoration(
            color: ZveltTokens.surfaceTinted,
            borderRadius: BorderRadius.circular(26),
            boxShadow: ZveltTokens.shadowCard,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFD43B), Color(0xFFFF6B00)],
                  ),
                ),
                child:
                    const Icon(AppIcons.flame, color: Colors.white, size: 34),
              ),
              const SizedBox(height: ZveltTokens.s4),
              Text(
                'Streak Calendar',
                style: ZType.h1.copyWith(
                  color: ZveltTokens.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Track your consistency',
                style: ZType.h3.copyWith(
                  color: ZveltTokens.text2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _consistencyGoalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Consistency Goal',
          style: ZType.h4.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: ZveltTokens.s3),
        _ConsistencyGoalCard(
          currentStreak: _currentStreak,
          targetStreak: 7,
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => GoalsScreen(
                initialCurrentStreak: _currentStreak,
                initialTrainedDayKeys: _trainedDayKeys,
                targetStreak: 7,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _last14WorkoutsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Last 14 Workouts',
          style: ZType.h4.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: ZveltTokens.s3),
        _Last14WorkoutsCard(
          stats: _last14,
          bodyweightKg: _bodyweightKg,
          bodyweightTrend: _bodyweightTrend,
          onEditBodyweight: _editBodyweight,
        ),
      ],
    );
  }

  Widget _cardioWeekCard() {
    final hasCardio = _cardioCount > 0;
    final kmStr =
        _cardioKm >= 0.05 ? ' · ${_cardioKm.toStringAsFixed(1)} km' : '';
    final minStr = _cardioMin > 0 ? ' · $_cardioMin min' : '';
    return GestureDetector(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const ActivityCalendarScreen()),
      ),
      child: _Card(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ZveltTokens.brandTint,
                borderRadius: BorderRadius.circular(ZveltTokens.rMd),
              ),
              child: const Icon(AppIcons.running,
                  size: 20, color: ZveltTokens.brand),
            ),
            const SizedBox(width: ZveltTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cardio', style: ZType.h4),
                  const SizedBox(height: 2),
                  Text(
                    hasCardio
                        ? (_cardioLatestLine ?? 'Latest session saved')
                        : 'No runs or rides yet this week',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: ZveltTokens.s2),
            Text(
              hasCardio ? '$_cardioCount$kmStr$minStr' : '0',
              style: ZType.bodyS.copyWith(
                color: ZveltTokens.brandDeep,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Muscle map + per-muscle levels ─────────────────────────────────────────
  Widget _muscleSection() {
    final levels = _muscleLevels.values.where((m) => m.level > 0).toList()
      ..sort((a, b) => b.level.compareTo(a.level));
    return Column(
      children: [
        const MuscleMapCard(),
        if (levels.isNotEmpty) ...[
          const SizedBox(height: ZveltTokens.cardGap),
          SizedBox(
            height: 66,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: levels.length > 8 ? 8 : levels.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: ZveltTokens.s2),
              itemBuilder: (_, i) => _MuscleLevelChip(level: levels[i]),
            ),
          ),
        ],
      ],
    );
  }

  // ── Collapsible progress charts (open on tap) ──────────────────────────────
  Widget _progressCharts() {
    return const Column(
      children: [
        ZCollapsibleChartCard(
          title: 'Recent records',
          icon: AppIcons.trophy,
          child: RecentPrsCard(),
        ),
      ],
    );
  }

  // ── Latest friend activity ─────────────────────────────────────────────────
  Widget _friendCard() {
    final post = _friendPost;
    if (_loading) {
      return const _Card(
        child: SizedBox(
          height: 44,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: ZveltTokens.brand),
            ),
          ),
        ),
      );
    }
    if (post == null) {
      return _Card(
        child: Row(
          children: [
            Icon(AppIcons.users, size: 20, color: ZveltTokens.text3),
            const SizedBox(width: ZveltTokens.s3),
            Expanded(
              child: Text(
                'No friend activity yet — add friends to see their sessions here.',
                style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
              ),
            ),
          ],
        ),
      );
    }
    final author = (post.authorName?.trim().isNotEmpty ?? false)
        ? post.authorName!.trim()
        : 'A friend';
    final summary = _friendSummary(post);
    return _Card(
      onTap: widget.onOpenFeed,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: ZveltTokens.gradBrand,
            ),
            alignment: Alignment.center,
            child: Text(
              author[0].toUpperCase(),
              style: ZType.bodyM.copyWith(
                color: ZveltTokens.onBrand,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZType.bodyM.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
              ],
            ),
          ),
          const SizedBox(width: ZveltTokens.s2),
          Text(_ago(post.createdAt),
              style: ZType.monoXS.copyWith(color: ZveltTokens.text3)),
        ],
      ),
    );
  }

  String _friendSummary(SocialFeedPost post) {
    final cap = post.caption?.trim();
    if (cap != null && cap.isNotEmpty) return cap;
    if (post.exercises.isNotEmpty) {
      final n = post.exercises.length;
      return 'Completed a workout · $n exercise${n == 1 ? '' : 's'}';
    }
    return 'Shared an update';
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared light-mode building blocks
// ─────────────────────────────────────────────────────────────────────────────

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: ZType.eyebrow);
}

class _MuscleLevelChip extends StatelessWidget {
  const _MuscleLevelChip({required this.level});
  final MuscleLevel level;

  String get _label {
    final s = level.slug.replaceAll('-', ' ').trim();
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return ZCard(
      padding: const EdgeInsets.symmetric(
          horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
                color: ZveltTokens.brandTint,
                borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
            child: Text('Lvl ${level.level}',
                style: ZType.monoXS.copyWith(color: ZveltTokens.brandDeep)),
          ),
          const SizedBox(height: 3),
          Text(_label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZType.bodyS.copyWith(
                  color: ZveltTokens.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
          Text(level.tier,
              style: ZType.monoXS.copyWith(color: ZveltTokens.text3)),
        ],
      ),
    );
  }
}

class _ConsistencyGoalCard extends StatelessWidget {
  const _ConsistencyGoalCard({
    required this.currentStreak,
    required this.targetStreak,
    required this.onTap,
  });

  final int currentStreak;
  final int targetStreak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = targetStreak <= 0
        ? 0.0
        : (currentStreak / targetStreak).clamp(0.0, 1.0);
    final filledSlots = currentStreak.clamp(0, targetStreak);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(ZveltTokens.s4),
          decoration: BoxDecoration(
            color: ZveltTokens.surfaceTinted,
            borderRadius: BorderRadius.circular(18),
            boxShadow: ZveltTokens.shadowCard,
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Streak',
                          style: ZType.bodyS.copyWith(
                            color: ZveltTokens.text2,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '$currentStreak',
                              style: ZType.h3.copyWith(
                                color: ZveltTokens.text,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(AppIcons.flame,
                                color: Color(0xFFFF7A00), size: 18),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _GoalRing(progress: progress),
                ],
              ),
              const SizedBox(height: ZveltTokens.s4),
              Row(
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    Expanded(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: i < filledSlots
                                ? const Color(0xFFFF6B00)
                                : ZveltTokens.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: i == 6
                              ? Icon(
                                  AppIcons.flag,
                                  size: 18,
                                  color: filledSlots >= targetStreak
                                      ? Colors.white
                                      : ZveltTokens.text4,
                                )
                              : null,
                        ),
                      ),
                    ),
                    if (i < 6) const SizedBox(width: 7),
                  ],
                ],
              ),
              const SizedBox(height: ZveltTokens.s4),
              Row(
                children: [
                  Icon(AppIcons.target, size: 18, color: ZveltTokens.text4),
                  const SizedBox(width: ZveltTokens.s2),
                  Expanded(
                    child: Text(
                      'Target Streak',
                      style: ZType.bodyM.copyWith(color: ZveltTokens.text2),
                    ),
                  ),
                  Text(
                    '$targetStreak',
                    style: ZType.bodyM.copyWith(
                      color: ZveltTokens.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(AppIcons.flame,
                      color: Color(0xFFFF7A00), size: 17),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalRing extends StatelessWidget {
  const _GoalRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 78,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(104, 78),
            painter: _GoalRingPainter(progress: progress),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '${(progress * 100).round()}%',
              style: ZType.h4.copyWith(
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

class _GoalRingPainter extends CustomPainter {
  const _GoalRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(10, 4, size.width - 20, size.height + 34);
    final bg = Paint()
      ..color = ZveltTokens.surface.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;
    final fg = Paint()
      ..color = const Color(0xFFFF6B00)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;
    canvas.drawArc(rect, math.pi, math.pi, false, bg);
    canvas.drawArc(rect, math.pi, math.pi * progress, false, fg);
  }

  @override
  bool shouldRepaint(covariant _GoalRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _Last14WorkoutsCard extends StatelessWidget {
  const _Last14WorkoutsCard({
    required this.stats,
    required this.bodyweightKg,
    required this.bodyweightTrend,
    required this.onEditBodyweight,
  });

  final _Last14WorkoutStats stats;
  final double? bodyweightKg;
  final List<double> bodyweightTrend;
  final VoidCallback onEditBodyweight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TintPanel(
          child: Row(
            children: [
              Expanded(
                child: _MetricText(
                  label: 'Volume',
                  value: '${_fmtKg(stats.volumeKg)} kg',
                  sublabel: stats.volumeTrendLabel,
                  subIcon: stats.volumeTrendIcon,
                ),
              ),
              SizedBox(
                width: 150,
                height: 58,
                child: _WorkoutBars(values: stats.volumeBars),
              ),
            ],
          ),
        ),
        const SizedBox(height: ZveltTokens.s2),
        Row(
          children: [
            Expanded(
              child: _TintPanel(
                child: _MetricText(
                  label: 'Duration',
                  value: _formatDuration(stats.duration),
                ),
              ),
            ),
            const SizedBox(width: ZveltTokens.s2),
            Expanded(
              child: _TintPanel(
                child: _MetricText(
                  label: 'Records',
                  value: '${stats.records}',
                ),
              ),
            ),
            const SizedBox(width: ZveltTokens.s2),
            Expanded(
              child: _TintPanel(
                child: _MetricText(
                  label: 'Burned',
                  value: _formatCalories(stats.burnedCalories),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZveltTokens.s2),
        Stack(
          children: [
            _TintPanel(
              child: Row(
                children: [
                  Expanded(
                    child: _MetricText(
                      label: 'Bodyweight',
                      value: bodyweightKg == null
                          ? '-- kg'
                          : '${bodyweightKg!.toStringAsFixed(1)} kg',
                      sublabel: _bodyweightStatus(bodyweightTrend),
                      subIcon: AppIcons.arrow_small_right,
                    ),
                  ),
                  const SizedBox(width: ZveltTokens.s6),
                  SizedBox(
                    width: 154,
                    height: 54,
                    child: _BodyweightSparkline(values: bodyweightTrend),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Semantics(
                button: true,
                label: 'Edit bodyweight',
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onEditBodyweight,
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        AppIcons.plus,
                        color: ZveltTokens.text2,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _fmtKg(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.05) return rounded.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  static String _formatCalories(int? calories) =>
      calories == null ? '-- cal' : '$calories cal';

  static String _bodyweightStatus(List<double> values) {
    if (values.length < 2) return 'Stable Weight';
    final delta = values.last - values.first;
    if (delta.abs() < 0.3) return 'Stable Weight';
    return delta > 0 ? 'Trending Up' : 'Trending Down';
  }
}

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
          color: ZveltTokens.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          boxShadow: ZveltTokens.shadowFloat,
        ),
        padding: const EdgeInsets.fromLTRB(
          ZveltTokens.s5,
          ZveltTokens.s5,
          ZveltTokens.s5,
          ZveltTokens.s6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: ZveltTokens.brandTint,
                    borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                  ),
                  child: const Icon(
                    AppIcons.balance_scale_left,
                    color: ZveltTokens.brand,
                    size: 20,
                  ),
                ),
                const SizedBox(width: ZveltTokens.s3),
                Expanded(
                  child: Text(
                    'Update bodyweight',
                    style: ZType.h4.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZveltTokens.s5),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'Bodyweight',
                suffixText: 'kg',
                errorText: _error,
                filled: true,
                fillColor: ZveltTokens.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: ZveltTokens.s5),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZveltTokens.brand,
                  foregroundColor: ZveltTokens.onBrand,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  ),
                ),
                child: Text(
                  'Save',
                  style: ZType.bodyM.copyWith(
                    color: ZveltTokens.onBrand,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TintPanel extends StatelessWidget {
  const _TintPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surfaceTinted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _MetricText extends StatelessWidget {
  const _MetricText({
    required this.label,
    required this.value,
    this.sublabel,
    this.subIcon,
  });

  final String label;
  final String value;
  final String? sublabel;
  final IconData? subIcon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ZType.bodyS.copyWith(
            color: ZveltTokens.text2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: ZveltTokens.s3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ZType.bodyM.copyWith(
            color: ZveltTokens.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (sublabel != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: Text(
                  sublabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                ),
              ),
              if (subIcon != null) ...[
                const SizedBox(width: 4),
                Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Color(0xFF68C8FF),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(subIcon, color: Colors.white, size: 12),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _WorkoutBars extends StatelessWidget {
  const _WorkoutBars({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WorkoutBarsPainter(values: values),
    );
  }
}

class _WorkoutBarsPainter extends CustomPainter {
  const _WorkoutBarsPainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final bars = values.isEmpty ? List<double>.filled(14, 0) : values;
    final maxV = bars.fold<double>(0, (m, v) => v > m ? v : m);
    final count = math.max(14, bars.length);
    const gap = 5.0;
    final barW = math.max(4.0, (size.width - gap * (count - 1)) / count);
    final inactive = Paint()
      ..color = ZveltTokens.surface.withValues(alpha: 0.72);
    final active = Paint()..color = const Color(0xFF67C8FF);
    for (var i = 0; i < count; i++) {
      final v = i < bars.length ? bars[i] : 0.0;
      final pct = maxV <= 0 ? 0.0 : (v / maxV).clamp(0.0, 1.0);
      final h = 12 + pct * (size.height - 16);
      final x = i * (barW + gap);
      final y = size.height - h;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, h),
        Radius.circular(barW),
      );
      canvas.drawRRect(rect, v > 0 ? active : inactive);
    }
  }

  @override
  bool shouldRepaint(covariant _WorkoutBarsPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _BodyweightSparkline extends StatelessWidget {
  const _BodyweightSparkline({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BodyweightSparklinePainter(values: values),
    );
  }
}

class _BodyweightSparklinePainter extends CustomPainter {
  const _BodyweightSparklinePainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF67C8FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final baseline = Paint()
      ..color = const Color(0xFF67C8FF).withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final midY = size.height * 0.62;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), baseline);
    if (values.length < 2) {
      canvas.drawLine(Offset(0, midY), Offset(size.width, midY), line);
      return;
    }
    final minV = values.fold<double>(values.first, (m, v) => v < m ? v : m);
    final maxV = values.fold<double>(values.first, (m, v) => v > m ? v : m);
    final spread = (maxV - minV).abs() < 0.1 ? 1.0 : maxV - minV;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : size.width * i / (values.length - 1);
      final pct = ((values[i] - minV) / spread).clamp(0.0, 1.0);
      final y = size.height - 8 - pct * (size.height - 16);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _BodyweightSparklinePainter oldDelegate) =>
      oldDelegate.values != values;
}

class _Last14WorkoutStats {
  const _Last14WorkoutStats({
    required this.volumeKg,
    required this.duration,
    required this.records,
    required this.burnedCalories,
    required this.volumeBars,
    required this.volumeTrendLabel,
    required this.volumeTrendIcon,
  });

  final double volumeKg;
  final Duration duration;
  final int records;
  final int? burnedCalories;
  final List<double> volumeBars;
  final String volumeTrendLabel;
  final IconData volumeTrendIcon;

  static const empty = _Last14WorkoutStats(
    volumeKg: 0,
    duration: Duration.zero,
    records: 0,
    burnedCalories: null,
    volumeBars: [],
    volumeTrendLabel: 'No training yet',
    volumeTrendIcon: AppIcons.arrow_small_right,
  );

  static _Last14WorkoutStats fromWorkouts(Iterable<WorkoutDto> workouts) {
    final list = workouts.toList();
    final bars = list.reversed.map(_volumeOf).toList();
    final volume = bars.fold<double>(0, (sum, v) => sum + v);
    final duration = list.fold<Duration>(
      Duration.zero,
      (sum, w) => sum + _durationOf(w),
    );
    final trend = _trendFor(bars);
    return _Last14WorkoutStats(
      volumeKg: volume,
      duration: duration,
      records: 0,
      burnedCalories: null,
      volumeBars: bars,
      volumeTrendLabel: trend.$1,
      volumeTrendIcon: trend.$2,
    );
  }

  _Last14WorkoutStats copyWith({int? records}) => _Last14WorkoutStats(
        volumeKg: volumeKg,
        duration: duration,
        records: records ?? this.records,
        burnedCalories: burnedCalories,
        volumeBars: volumeBars,
        volumeTrendLabel: volumeTrendLabel,
        volumeTrendIcon: volumeTrendIcon,
      );

  static double _volumeOf(WorkoutDto workout) {
    var sum = 0.0;
    for (final exercise in workout.exercises) {
      for (final set in exercise.sets) {
        if (!set.isCompleted || set.tag != 'WORK') continue;
        sum += set.weightKg * set.reps;
      }
    }
    return sum;
  }

  static Duration _durationOf(WorkoutDto workout) {
    final end = workout.endedAt;
    if (end == null) return Duration.zero;
    final d = end.difference(workout.startedAt);
    if (d.isNegative || d > const Duration(hours: 24)) return Duration.zero;
    return d;
  }

  static (String, IconData) _trendFor(List<double> bars) {
    final nonZero = bars.where((v) => v > 0).toList();
    if (nonZero.length < 4) {
      return ('Training Stable', AppIcons.arrow_small_right);
    }
    final mid = (bars.length / 2).floor();
    final prior = bars.take(mid).fold<double>(0, (sum, v) => sum + v);
    final latest = bars.skip(mid).fold<double>(0, (sum, v) => sum + v);
    if (prior <= 0) return ('Training Up', AppIcons.arrow_small_up);
    final pct = (latest - prior) / prior;
    if (pct < -0.12) return ('Training Regression', AppIcons.arrow_small_down);
    if (pct > 0.12) return ('Training Up', AppIcons.arrow_small_up);
    return ('Training Stable', AppIcons.arrow_small_right);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        child: card,
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton(
      {required this.icon, this.onTap, required this.semanticLabel});
  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: ZveltTokens.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: ZveltTokens.text2),
          ),
        ),
      ),
    );
  }
}
