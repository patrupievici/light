import 'package:flutter/material.dart';

import '../../models/social_feed_post.dart';
import '../../services/nutrition_service.dart';
import '../../services/profile_service.dart';
import '../../services/social_feed_service.dart';
import '../../services/workout_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/zvelt_main_nav_bar.dart';
import '../workouts/workout_tracker_screen.dart';

/// HOME — the "today dashboard" from Razvan's light redesign (brief §7, mockup
/// screen 3). Greeting · Start-Workout hero · today's macros + workout status ·
/// weekly consistency strip · latest friend activity. Deliberately lean: no
/// biology / recovery / XP cards (those belong to the full app, not light).
///
/// Reuses the existing data layer — ProfileService, NutritionService,
/// WorkoutService, SocialFeedService — so it stays honest (real data or empty
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

  bool _loading = true;

  String _displayName = 'Athlete';
  double _kcal = 0, _kcalGoal = 0;
  double _protein = 0, _proteinGoal = 0;
  bool _workoutToday = false;
  List<bool> _week = List<bool>.filled(7, false);
  int _weekCount = 0;
  int _weekGoal = 5;
  SocialFeedPost? _friendPost;

  @override
  void initState() {
    super.initState();
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
    final monday = DateUtils.dateOnly(now).subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));

    final results = await Future.wait([
      _safe(_profile.getMe()),
      _safe(NutritionService.instance.getDay(now)),
      _safe(NutritionService.instance.getGoals()),
      _safe(_workouts.getWorkoutCalendar(from: monday, to: sunday)),
      _safe(_feed.getFeed()),
    ]);
    if (!mounted) return;

    final me = results[0] as Map<String, dynamic>?;
    final day = results[1] as DailyNutrition?;
    final goals = results[2] as NutritionGoals?;
    final calendar = (results[3] as List<DateTime>?) ?? const [];
    final posts = (results[4] as List<SocialFeedPost>?) ?? const [];

    final profile = me?['profile'] as Map<String, dynamic>?;
    final name = profile?['displayName'] as String?;
    final myId = me?['id'] as String?;
    // daysPerWeek lives on the training profile (/me → trainingProfile), not the
    // userProfile — reading it off `profile` always returned null (→ goal of 5).
    final trainingProfile = me?['trainingProfile'] as Map<String, dynamic>?;
    final daysPerWeek = (trainingProfile?['daysPerWeek'] as num?)?.toInt();

    final week = List<bool>.filled(7, false);
    final today = DateUtils.dateOnly(now);
    var workedOutToday = false;
    for (final d in calendar) {
      final dd = DateUtils.dateOnly(d);
      if (!dd.isBefore(monday) && !dd.isAfter(sunday)) {
        week[dd.weekday - 1] = true;
      }
      if (dd == today) workedOutToday = true;
    }

    setState(() {
      _loading = false;
      _displayName = (name != null && name.trim().isNotEmpty) ? name.trim() : 'Athlete';
      _kcal = day?.totalCalories ?? 0;
      _protein = day?.totalProtein ?? 0;
      _kcalGoal = (goals?.calories ?? 0).toDouble();
      _proteinGoal = (goals?.proteinG ?? 0).toDouble();
      _week = week;
      _weekCount = week.where((e) => e).length;
      _weekGoal = (daysPerWeek != null && daysPerWeek > 0) ? daysPerWeek : 5;
      _workoutToday = workedOutToday;
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

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  String get _todayLabel {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final n = DateTime.now();
    return 'Today, ${n.day} ${months[n.month - 1]}';
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
            _startWorkoutHero(),
            const SizedBox(height: ZveltTokens.s6),
            const _Eyebrow('TODAY'),
            const SizedBox(height: ZveltTokens.s3),
            _todayCards(),
            const SizedBox(height: ZveltTokens.s6),
            const _Eyebrow('THIS WEEK'),
            const SizedBox(height: ZveltTokens.s3),
            _weekCard(),
            const SizedBox(height: ZveltTokens.s6),
            const _Eyebrow('FRIEND ACTIVITY'),
            const SizedBox(height: ZveltTokens.s3),
            _friendCard(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header() {
    final initial = _displayName.trim().isNotEmpty
        ? _displayName.trim()[0].toUpperCase()
        : 'A';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$_greeting,', style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
              const SizedBox(height: 2),
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
              Text(_todayLabel, style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
            ],
          ),
        ),
        _CircleButton(
          icon: AppIcons.bell,
          onTap: widget.onOpenNotifications,
          semanticLabel: 'Notifications',
        ),
        const SizedBox(width: ZveltTokens.s2),
        InkWell(
          onTap: widget.onOpenProfile,
          customBorder: const CircleBorder(),
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: ZveltTokens.gradBrand,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: ZType.h4.copyWith(color: ZveltTokens.onBrand),
            ),
          ),
        ),
      ],
    );
  }

  // ── Start Workout hero — the most prominent element on the screen ──────────
  Widget _startWorkoutHero() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _startWorkout,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        child: Container(
          padding: const EdgeInsets.all(ZveltTokens.s5),
          decoration: BoxDecoration(
            gradient: ZveltTokens.gradBtn,
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            boxShadow: [
              BoxShadow(
                color: ZveltTokens.brand.withValues(alpha: 0.32),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start Workout',
                      style: ZType.h2.copyWith(color: ZveltTokens.onBrand),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _workoutToday ? 'Logged today — go again?' : 'Pick up where you left off',
                      style: ZType.bodyS.copyWith(
                        color: ZveltTokens.onBrand.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ZveltTokens.onBrand.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(AppIcons.arrow_small_right, color: ZveltTokens.onBrand),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Today cards: calories · protein · workout ──────────────────────────────
  Widget _todayCards() {
    return Column(
      children: [
        _StatRow(
          icon: AppIcons.flame,
          label: 'Calories',
          value: _kcalGoal > 0
              ? '${_kcal.round()} / ${_kcalGoal.round()} kcal'
              : '${_kcal.round()} kcal',
          progress: _kcalGoal > 0 ? (_kcal / _kcalGoal).clamp(0.0, 1.0) : null,
          onTap: widget.onOpenFood,
        ),
        const SizedBox(height: ZveltTokens.cardGap),
        _StatRow(
          icon: AppIcons.restaurant,
          label: 'Protein',
          value: _proteinGoal > 0
              ? '${_protein.round()} / ${_proteinGoal.round()} g'
              : '${_protein.round()} g',
          progress: _proteinGoal > 0 ? (_protein / _proteinGoal).clamp(0.0, 1.0) : null,
          onTap: widget.onOpenFood,
        ),
        const SizedBox(height: ZveltTokens.cardGap),
        _StatRow(
          icon: AppIcons.gym,
          label: 'Workout',
          value: _workoutToday ? 'Completed today' : 'Not logged yet',
          progress: null,
          trailingDot: _workoutToday ? ZveltTokens.success : ZveltTokens.warn,
          onTap: _startWorkout,
        ),
      ],
    );
  }

  // ── Weekly consistency strip ───────────────────────────────────────────────
  Widget _weekCard() {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Consistency', style: ZType.h4),
              Text(
                '$_weekCount / $_weekGoal workouts',
                style: ZType.bodyS.copyWith(
                  color: ZveltTokens.brandDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                Column(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _week[i] ? ZveltTokens.brand : ZveltTokens.bg2,
                      ),
                      child: _week[i]
                          ? const Icon(AppIcons.check, size: 16, color: ZveltTokens.onBrand)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      style: ZType.monoXS.copyWith(
                        color: _week[i] ? ZveltTokens.text : ZveltTokens.text3,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
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
              child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.brand),
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
          Text(_ago(post.createdAt), style: ZType.monoXS.copyWith(color: ZveltTokens.text3)),
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

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.progress,
    this.trailingDot,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final double? progress;
  final Color? trailingDot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _Card(
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
            child: Icon(icon, size: 20, color: ZveltTokens.brandDeep),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZType.bodyM.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (progress != null) _PercentRing(progress: progress!),
          if (trailingDot != null)
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: trailingDot, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}

class _PercentRing extends StatelessWidget {
  const _PercentRing({required this.progress});
  final double progress;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 4,
              backgroundColor: ZveltTokens.surface3,
              valueColor: const AlwaysStoppedAnimation(ZveltTokens.brand),
            ),
          ),
          Text(
            '${(progress * 100).round()}',
            style: ZType.monoXS.copyWith(
              color: ZveltTokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, this.onTap, required this.semanticLabel});
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
