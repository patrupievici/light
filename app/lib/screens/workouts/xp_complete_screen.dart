import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import '../../models/game_xp_models.dart';
import '../profile_screen.dart';
import '../../services/_crash_reporter.dart';
import '../../services/profile_service.dart';
import '../../services/workout_service.dart';
import '../../services/activity_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/zvelt_secondary_button.dart';
import '../../services/social_feed_service.dart';
import '../../services/stats_charts_service.dart';
import '../../widgets/post_prompt_sheet.dart';

/// Mesaj când [GET /v1/ranks/me] e gol (nu există `userExerciseRank` încă).
enum _RankEmptyHint {
  /// Profil fără greutate validă — rangurile strength folosesc bodyweight.
  setBodyweight,
  /// Greutate setată, dar încă fără randuri rank (ex. doar bodyweight / încă nu s-au scris seturi rankabile).
  weightedSetsNeeded,
  /// Fallback (ex. nu am putut citi profilul).
  generic,
}

double? _profileBodyweightKg(Map<String, dynamic>? profile) {
  if (profile == null) return null;
  final v = profile['bodyweightKg'] ?? profile['bodweightKg'] ?? profile['bodyweight_kg'];
  if (v == null) return null;
  if (v is num) {
    final d = v.toDouble();
    return d > 0 ? d : null;
  }
  final d = double.tryParse(v.toString());
  return (d != null && d > 0) ? d : null;
}

/// Ecran final după complete: animație +XP; butoanele rămân mereu vizibile jos (scroll pe ecrane mici).
class XpCompleteScreen extends StatefulWidget {
  const XpCompleteScreen({
    super.key,
    required this.onDone,
    this.workoutId,
    this.xpGain = 0,
    this.ageMultiplier = 1.0,
    this.gameXp,
    this.title = 'Workout complete!',
    this.subtitle,
    this.showRanks = true,
    this.showShare = true,
    this.xpBreakdown = const [],
    this.shareCaption,
  });

  final String? workoutId;
  final VoidCallback onDone;
  final int xpGain;
  /// Age bonus applied by server (e.g. 1.22). Anything >1.0 surfaces as
  /// a chip under the XP number so the user sees the fairness payoff.
  final double ageMultiplier;
  final GameXpSnapshot? gameXp;
  final String title;
  final String? subtitle;
  final bool showRanks;
  final bool showShare;
  final List<XpBreakdownLine> xpBreakdown;
  final String? shareCaption;

  @override
  State<XpCompleteScreen> createState() => _XpCompleteScreenState();
}

class _XpCompleteScreenState extends State<XpCompleteScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  List<ExerciseRankDto> _ranks = [];
  bool _ranksLoaded = false;
  _RankEmptyHint _rankEmptyHint = _RankEmptyHint.generic;

  /// A personal record set in the last day — almost certainly from the workout
  /// just completed. Drives the "NEW PR" badge + a celebratory share caption.
  RecentPr? _todayPr;

  /// AI coach commentary on the workout just completed. Null while loading,
  /// stays null on AI failure (the card just doesn't render).
  String? _insight;
  bool _insightLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scale = Tween<double>(begin: 0.5, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0, 0.5, curve: Curves.easeOut)),
    );
    _controller.forward();
    if (widget.showRanks) {
      Future.delayed(const Duration(milliseconds: 600), _loadRanks);
    } else {
      _ranksLoaded = true;
    }
    if (widget.workoutId != null && widget.workoutId!.isNotEmpty) {
      _insightLoading = true;
      // Small delay so the celebratory XP animation plays first; the coach
      // commentary then fades in once attention has settled.
      Future.delayed(const Duration(milliseconds: 900), _loadInsight);
      _loadTodayPr();
    }
  }

  Future<void> _loadTodayPr() async {
    try {
      final prs = await StatsChartsService().getRecentPrs(days: 1);
      if (!mounted || prs.isEmpty) return;
      setState(() => _todayPr = prs.first);
    } catch (_) {
      // Best-effort celebration — no PR badge if this fails.
    }
  }

  /// Caption used when sharing: caller-supplied wins, else a PR shout-out, else
  /// the share screens fall back to their own default.
  String? get _shareCaption {
    if (widget.shareCaption != null) return widget.shareCaption;
    final pr = _todayPr;
    if (pr != null) return 'New PR — ${pr.exerciseName}! ${pr.headline} 💪';
    return null;
  }

  Future<void> _loadInsight() async {
    final wid = widget.workoutId;
    if (wid == null || wid.isEmpty) return;
    final insight = await WorkoutService().fetchPostWorkoutInsight(wid);
    if (!mounted) return;
    setState(() {
      _insight = insight;
      _insightLoading = false;
    });
  }

  Future<void> _loadRanks() async {
    try {
      final ranks = await WorkoutService().getMyRanks();
      var hint = _RankEmptyHint.generic;
      if (ranks.isEmpty) {
        final me = await ProfileService().getMe();
        final profile = me?['profile'] as Map<String, dynamic>?;
        final bw = _profileBodyweightKg(profile);
        hint = bw != null ? _RankEmptyHint.weightedSetsNeeded : _RankEmptyHint.setBodyweight;
      }
      if (!mounted) return;
      setState(() {
        _ranks = ranks;
        _rankEmptyHint = hint;
        _ranksLoaded = true;
      });
    } catch (e, st) {
      reportError(e, st, reason: 'xp-complete:load-ranks');
      if (!mounted) return;
      setState(() {
        _ranksLoaded = true;
        _rankEmptyHint = _RankEmptyHint.generic;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openShare() async {
    await PostPromptSheet.open(
      context,
      workoutId: widget.workoutId,
      initialCaption: _shareCaption,
    );
  }

  Future<void> _quickShareToFeed() async {
    if (widget.workoutId == null) {
      await _openShare();
      return;
    }
    try {
      await SocialFeedService().createWorkoutPost(
        workoutId: widget.workoutId!,
        caption: _shareCaption ?? 'Workout logged 💪',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workout shared to your feed — streak updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _showRankExplain(ExerciseRankDto rank) async {
    try {
      final data = await WorkoutService().getRankExplain(rank.exerciseId);
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: ZveltTokens.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
        ),
        builder: (ctx) {
          // Backend returns `explanation` (per-user, log-derived); the old code
          // read `summary`/`message` which the endpoint never sends, so users
          // always saw the hardcoded fallback. Read the real field first.
          final explanation = (data['explanation'] ??
                  data['summary'] ??
                  data['message'] ??
                  'Rank based on strength ratio vs peers.')
              .toString();
          final nextTier = data['nextTier'];
          final tierName = nextTier is Map ? nextTier['name'] as String? : null;
          final target = nextTier is Map
              ? num.tryParse('${nextTier['estimatedWeightAt5Reps']}')
              : null;
          final lpRemaining = nextTier is Map
              ? num.tryParse('${nextTier['lpRemaining']}')
              : null;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rank.exerciseName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 8),
                Text(
                  explanation,
                  style: TextStyle(color: ZveltTokens.text2, height: 1.45),
                ),
                if (target != null && tierName != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(AppIcons.flag, size: 16, color: ZveltTokens.brand),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Hit ~${target % 1 == 0 ? target.toInt() : target.toStringAsFixed(1)}kg × 5 to reach $tierName'
                          '${lpRemaining != null ? ' · ${lpRemaining.toInt()} LP left' : ''}',
                          style: TextStyle(
                              color: ZveltTokens.text, fontWeight: FontWeight.w600, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(AppIcons.cross_small, color: ZveltTokens.text),
          tooltip: 'Close',
          onPressed: () {
            Navigator.of(context).pop();
            widget.onDone();
          },
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const bottomActionsHeight = 200.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - bottomActionsHeight,
                      ),
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _opacity.value,
                            child: Transform.scale(
                              scale: _scale.value,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: ZveltTokens.success.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: ZveltTokens.success, width: 2),
                                    ),
                                    child: const Icon(AppIcons.check, size: 64, color: ZveltTokens.success),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    widget.xpGain > 0 ? '+${widget.xpGain} XP' : '+0 XP',
                                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                          color: ZveltTokens.info,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1,
                                        ),
                                  ),
                                  // Surface the age bonus when present so older
                                  // lifters can see the fairness multiplier
                                  // visible in the result, not buried in code.
                                  if (widget.ageMultiplier > 1.0 && widget.xpGain > 0) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: ZveltTokens.brand.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                                        border: Border.all(
                                          color: ZveltTokens.brand.withValues(alpha: 0.5),
                                        ),
                                      ),
                                      child: Text(
                                        '×${widget.ageMultiplier.toStringAsFixed(2)} age bonus',
                                        style: const TextStyle(
                                          color: ZveltTokens.brand,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (_todayPr != null) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: ZveltTokens.success.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                                        border: Border.all(color: ZveltTokens.success.withValues(alpha: 0.5)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(AppIcons.trophy, size: 14, color: ZveltTokens.success),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              'NEW PR · ${_todayPr!.exerciseName}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: ZveltTokens.success,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.title,
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          color: ZveltTokens.text2,
                                        ),
                                  ),
                                  if (widget.subtitle != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      widget.subtitle!,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: ZveltTokens.text2,
                                          ),
                                    ),
                                  ],
                                  if (widget.workoutId != null && widget.workoutId!.isNotEmpty) ...[
                                    const SizedBox(height: 20),
                                    _CoachInsightCard(
                                      insight: _insight,
                                      loading: _insightLoading,
                                    ),
                                  ],
                                  if (widget.gameXp != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      '${widget.gameXp!.levelName} · Lv ${widget.gameXp!.level} · ${widget.gameXp!.totalXp} XP total',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: ZveltTokens.text2,
                                          ),
                                    ),
                                  ],
                                  if (widget.xpBreakdown.isNotEmpty) ...[
                                    const SizedBox(height: 20),
                                    _XpBreakdownList(lines: widget.xpBreakdown),
                                  ],
                                  const SizedBox(height: 24),
                                  if (widget.showRanks)
                                    _RankSummarySection(
                                      ranks: _ranks,
                                      loaded: _ranksLoaded,
                                      emptyHint: _rankEmptyHint,
                                      onExplain: _showRankExplain,
                                    ),
                                  if (widget.showRanks && _ranks.isNotEmpty) const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.showShare) ...[
                        FilledButton.icon(
                          onPressed: _openShare,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 54),
                            backgroundColor: ZveltTokens.brand,
                            foregroundColor: ZveltTokens.onBrand,
                          ),
                          icon: const Icon(AppIcons.picture, size: 22),
                          label: const Text(
                            'Post with photo',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _quickShareToFeed,
                          icon: const Icon(AppIcons.paper_plane, size: 20),
                          label: const Text('Share to feed (no photo)'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            foregroundColor: ZveltTokens.text,
                            side: BorderSide(color: ZveltTokens.border),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Gallery or camera — optional. Tap Done to finish without sharing.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: ZveltTokens.text2.withValues(alpha: 0.9),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      ZveltSecondaryButton(
                        label: 'Done',
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onDone();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _RankSummarySection extends StatelessWidget {
  const _RankSummarySection({
    required this.ranks,
    required this.loaded,
    required this.emptyHint,
    this.onExplain,
  });
  final List<ExerciseRankDto> ranks;
  final bool loaded;
  final _RankEmptyHint emptyHint;
  final void Function(ExerciseRankDto rank)? onExplain;

  static const _tierColors = {
    'Iron': Color(0xFF9E9E9E),
    'Bronze': Color(0xFFCD7F32),
    'Silver': Color(0xFFAAAAAA),
    'Gold': Color(0xFFFFD700),
    'Platinum': Color(0xFF00BCD4),
    'Diamond': Color(0xFF2979FF),
    'Olympian': Color(0xFFE040FB),
  };

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.brand)),
            const SizedBox(width: 8),
            Text('Loading ranks…', style: TextStyle(color: ZveltTokens.text2, fontSize: 12)),
          ],
        ),
      );
    }
    if (ranks.isEmpty) {
      final message = switch (emptyHint) {
        _RankEmptyHint.setBodyweight =>
          'Set your bodyweight in profile to unlock strength rankings (e1RM vs bodyweight).',
        _RankEmptyHint.weightedSetsNeeded =>
          'No rankings yet — log completed working sets on rankable exercises: weighted lifts or calisthenics (reps with 0 kg; optional added weight on belt).',
        _RankEmptyHint.generic =>
          'No rankings loaded yet. Set bodyweight in your profile, then complete workouts with rankable exercises.',
      };
      // For setBodyweight specifically, offer a direct action so the user
      // can fix the gap right now instead of finding the profile manually.
      final showProfileCta = emptyHint == _RankEmptyHint.setBodyweight;
      return Container(
        margin: const EdgeInsets.symmetric(vertical: ZveltTokens.s1),
        padding: const EdgeInsets.all(ZveltTokens.s3),
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          boxShadow: ZveltTokens.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(AppIcons.info, color: ZveltTokens.warn, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
                  ),
                ),
              ],
            ),
            if (showProfileCta) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: ZveltTokens.brand,
                    minimumSize: const Size(44, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () {
                    // Push Physical Data on top of the celebration screen.
                    // When the user pops back, they can dismiss the
                    // celebration via the existing Close button. We don't
                    // call onDone here because that would tear down the
                    // route stack before ProfileScreen renders.
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
                    );
                  },
                  child: const Text('Set bodyweight',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Show top 3 ranks
    final top = ranks.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your Rankings',
          textAlign: TextAlign.center,
          style: TextStyle(color: ZveltTokens.text2, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        ...top.map((r) {
          final color = _tierColors[r.tier] ?? ZveltTokens.text2;
          final progress = (r.lpInTier / 100.0).clamp(0.0, 1.0);
          return InkWell(
            onTap: onExplain != null ? () => onExplain!(r) : null,
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            child: Container(
            margin: const EdgeInsets.only(bottom: ZveltTokens.s2),
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              boxShadow: ZveltTokens.shadowCard,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.exerciseName,
                        style: TextStyle(color: ZveltTokens.text, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (onExplain != null)
                      TextButton(
                        onPressed: () => onExplain!(r),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Why?', style: TextStyle(fontSize: 11)),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        r.tier,
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${r.lpInTier}/100',
                      style: TextStyle(color: ZveltTokens.text2, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: ZveltTokens.border,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          ),
          );
        }),
      ],
    );
  }
}

class _XpBreakdownList extends StatelessWidget {
  const _XpBreakdownList({required this.lines});

  final List<XpBreakdownLine> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'XP breakdown',
            style: TextStyle(color: ZveltTokens.text2, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),
          ...lines.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.label, style: TextStyle(color: ZveltTokens.text, fontWeight: FontWeight.w600, fontSize: 13)),
                          if (l.detail != null)
                            Text(l.detail!, style: TextStyle(color: ZveltTokens.text2, fontSize: 11)),
                        ],
                      ),
                    ),
                    Text(
                      '${l.pct}% ×${l.mult}',
                      style: const TextStyle(color: ZveltTokens.brand, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Text('+${l.xp}', style: TextStyle(color: ZveltTokens.text, fontWeight: FontWeight.w700, fontSize: 12)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COACH INSIGHT CARD (post-workout commentary)
// ─────────────────────────────────────────────────────────────────────────────
//
// Replaces the generic "Workout saved!" feeling with something specific to
// what the user actually did. Loading state shows a subtle shimmer line —
// the rest of the screen (XP, ranks) keeps the user busy while the ~1.5s
// AI call lands. If the AI fails entirely, the card renders nothing so the
// completion flow never looks broken.

class _CoachInsightCard extends StatelessWidget {
  const _CoachInsightCard({required this.insight, required this.loading});

  final String? insight;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!loading && (insight == null || insight!.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(ZveltTokens.s2),
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: const Icon(
                  AppIcons.brain_circuit,
                  color: ZveltTokens.brand,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "YOUR COACH'S READ",
                  style: TextStyle(
                    color: ZveltTokens.text2,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            _ShimmerLines()
          else
            Text(
              insight!,
              style: TextStyle(
                color: ZveltTokens.text,
                fontSize: 13,
                height: 1.5,
              ),
            ),
        ],
      ),
    );
  }
}

class _ShimmerLines extends StatefulWidget {
  @override
  State<_ShimmerLines> createState() => _ShimmerLinesState();
}

class _ShimmerLinesState extends State<_ShimmerLines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final opacity = 0.18 + (_ctrl.value * 0.18);
        Widget line(double widthFrac) => Container(
              height: 12,
              width: MediaQuery.sizeOf(context).width * widthFrac,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: ZveltTokens.text.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(4),
              ),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [line(0.85), line(0.72), line(0.55)],
        );
      },
    );
  }
}
