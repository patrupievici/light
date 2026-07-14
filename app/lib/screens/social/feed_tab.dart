import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/social_challenge.dart';
import '../../models/social_feed_post.dart';
import '../../services/auth_service.dart';
import '../../services/feed_refresh_notifier.dart';
import '../../services/social_challenge_service.dart';
import '../../services/social_feed_service.dart';
import '../../services/stats_charts_service.dart';
import '../../services/stories_service.dart';
import '../../services/workout_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/post_prompt_sheet.dart';
import '../../widgets/stories_tray.dart';
import '../../widgets/zvelt_main_nav_bar.dart';
import 'challenge_detail_screen.dart';
import 'create_challenge_flow.dart';
import 'friends_screen.dart';
import 'notifications_screen.dart';
import 'post_detail_screen.dart';
import 'story_composer_screen.dart';
import 'story_viewer_screen.dart';

/// FEED — 1:1 with the ZVELT handoff prototype (screen A4).
///
/// Header ("Feed" + bell) · stories rail · 4 pills **All / Following / PRs /
/// Fame**. All: ACTIVE-CHALLENGE hero (violet→orange), Leaderboard + See all,
/// posts (detail chip, like/comment/share + Challenge chip), Post-workout /
/// Find-friends / Challenge tiles. Following: YOUR CIRCLE TODAY, pending
/// invite Accept/Decline, light posts. PRs: category chips, PR cards
/// (Celebrate / Challenge this PR), Friends PR Leaderboard. Fame: Hall of
/// Fame rows, Record holders, Your trophies. Nothing else.
///
/// All data is REAL: SocialFeedService, SocialChallengeService (active,
/// standings, invites), StoriesService, StatsChartsService PRs, season
/// leaderboard.
class FeedTab extends StatefulWidget {
  const FeedTab({super.key});

  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  final _feed = SocialFeedService();
  final _challenges = SocialChallengeService();
  final _stories = StoriesService();
  final _stats = StatsChartsService();
  final _workouts = WorkoutService();
  final _auth = AuthService();

  int _tab = 0; // 0 All · 1 Following · 2 PRs · 3 Fame · 4 Challenges
  bool _loading = true;
  String? _meId;

  List<SocialFeedPost> _posts = const [];
  List<StoryAuthorGroup> _storyGroups = const [];
  List<SocialChallenge> _active = const [];
  List<SocialChallenge> _completed = const [];
  List<ChallengeInvite> _invites = const [];
  List<RecentPr> _prs = const [];
  List<SeasonLeaderboardEntry> _fame = const [];
  String _prCat = 'All';

  /// Best-effort "You won · 1st of 6" lines per completed challenge.
  Map<String, String> _completedResult = const {};

  // Hero challenge standings (best-effort). (name, pts, userId)
  List<(String, num, String?)> _standings = const [];
  int? _myRank;
  num? _myPts;
  num? _myWorkouts;

  @override
  void initState() {
    super.initState();
    FeedRefreshNotifier.instance
        .notifier(RefreshScope.feed)
        .addListener(_onBump);
    _load();
  }

  @override
  void dispose() {
    FeedRefreshNotifier.instance
        .notifier(RefreshScope.feed)
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

  SocialChallenge? get _hero {
    final now = DateTime.now();
    for (final c in _active) {
      if ((c.joined || c.isMine) && c.endsAt.isAfter(now)) return c;
    }
    return _active.isNotEmpty ? _active.first : null;
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await Future.wait([
      _safe(_auth.getCurrentUserId()),
      _safe(_feed.getFeed()),
      _safe(_stories.getFeed()),
      _safe(_challenges.loadActive()),
      _safe(_challenges.listInvites()),
      _safe(_stats.getRecentPrs(days: 30)),
      _safe(_workouts.getSeasonLeaderboard(limit: 8)),
      _safe(_challenges.loadCompleted()),
    ]);
    if (!mounted) return;
    final meId = results[0] as String?;
    final stories = (results[2] as List<Story>?) ?? const <Story>[];
    final fameRes = results[6];

    setState(() {
      _meId = meId;
      _posts = (results[1] as List<SocialFeedPost>?) ?? const [];
      _storyGroups = groupStoriesByAuthor(stories, meId: meId);
      _active = (results[3] as List<SocialChallenge>?) ?? const [];
      _invites = (results[4] as List<ChallengeInvite>?) ?? const [];
      _prs = (results[5] as List<RecentPr>?) ?? const [];
      _fame = fameRes == null
          ? const []
          : ((fameRes as dynamic).entries as List<SeasonLeaderboardEntry>);
      _completed = (results[7] as List<SocialChallenge>?) ?? const [];
      _loading = false;
    });
    _loadStandings();
    _loadCompletedResults();
  }

  /// Placement lines for the newest completed challenges (real standings).
  Future<void> _loadCompletedResults() async {
    final out = <String, String>{};
    for (final c in _completed.take(3)) {
      final raw = await _safe(_challenges.getStandings(c.id));
      if (raw == null) continue;
      final rows =
          (raw['data'] as List<dynamic>? ?? const []).whereType<Map>().toList();
      for (var i = 0; i < rows.length; i++) {
        final m = Map<String, dynamic>.from(rows[i]);
        final uid = (m['userId'] ?? m['id'])?.toString();
        if (uid != null && uid == _meId) {
          final rank = (m['rank'] as num?)?.toInt() ?? i + 1;
          out[c.id] = rank == 1
              ? 'You won · 1st of ${rows.length}'
              : 'You placed · #$rank of ${rows.length}';
          break;
        }
      }
    }
    if (!mounted || out.isEmpty) return;
    setState(() => _completedResult = out);
  }

  Future<void> _loadStandings() async {
    final hero = _hero;
    if (hero == null) return;
    final raw = await _safe(_challenges.getStandings(hero.id));
    if (raw == null || !mounted) return;
    final rows = (raw['data'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .toList();
    final parsed = <(String, num, String?)>[];
    int? myRank;
    num? myPts;
    num? myWorkouts;
    for (var i = 0; i < rows.length; i++) {
      final m = Map<String, dynamic>.from(rows[i]);
      final name = (m['displayName'] ?? m['name'] ?? m['username'] ?? 'Athlete')
          .toString();
      final pts = (m['total'] ?? m['points'] ?? m['score'] ?? 0) as num;
      final uid = (m['userId'] ?? m['id'])?.toString();
      parsed.add((name, pts, uid));
      if (uid != null && uid == _meId) {
        myRank = (m['rank'] as num?)?.toInt() ?? i + 1;
        myPts = pts;
        // 4th hero stat — only when the payload really carries it.
        final w = m['workouts'] ?? m['sessions'] ?? m['workoutCount'];
        if (w is num) myWorkouts = w;
      }
    }
    setState(() {
      _standings = parsed;
      _myRank = myRank;
      _myPts = myPts;
      _myWorkouts = myWorkouts;
    });
  }

  // ─── actions ──────────────────────────────────────────────────────────────
  void _openNotifications() => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));

  void _openChallengeDetail() {
    final hero = _hero;
    if (hero == null) return;
    Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(
            builder: (_) => ChallengeDetailScreen(
                challengeId: hero.id, title: hero.title)))
        .then((_) => _load());
  }

  void _openCreate({String? scoringType, String? exerciseId}) {
    Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(
            builder: (_) => CreateChallengeFlow(
                initialScoringType: scoringType,
                initialExerciseId: exerciseId)))
        .then((_) => _load());
  }

  void _findFriends() => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const FriendsScreen()));

  Future<void> _postWorkout() async {
    final posted = await PostPromptSheet.open(context);
    if (posted == true) _load();
  }

  Future<void> _toggleLike(SocialFeedPost p) async {
    // Optimistic flip; revert on failure.
    final idx = _posts.indexWhere((x) => x.id == p.id);
    if (idx < 0) return;
    setState(() => _posts = List.of(_posts)
      ..[idx] = p.copyWith(
          likedByMe: !p.likedByMe,
          likeCount: p.likeCount + (p.likedByMe ? -1 : 1)));
    final ok = await _safe(_feed.toggleLike(p.id));
    if (ok == null && mounted) _load();
  }

  void _openPost(SocialFeedPost p) => Navigator.of(context)
      .push<void>(MaterialPageRoute<void>(
          builder: (_) => PostDetailScreen(postId: p.id)))
      .then((_) => _load());

  Future<void> _acceptInvite(ChallengeInvite inv) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _challenges.joinChallenge(inv.id);
      messenger.showSnackBar(const SnackBar(content: Text('Challenge accepted')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: ZveltTokens.error));
    }
    _load();
  }

  Future<void> _declineInvite(ChallengeInvite inv) async {
    await _safe(_challenges.declineChallenge(inv.id));
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
            _header(),
            _storiesRail(),
            _pills(),
            ...switch (_tab) {
              0 => _allBlocks(),
              1 => _followingBlocks(),
              2 => _prBlocks(),
              3 => _fameBlocks(),
              _ => _challengesBlocks(),
            },
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Row(
        children: [
          Text('Feed', style: ZType.h2),
          const Spacer(),
          InkWell(
            onTap: _openNotifications,
            borderRadius: BorderRadius.circular(ZveltTokens.rChip),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ZveltTokens.chip,
                borderRadius: BorderRadius.circular(ZveltTokens.rChip),
                border: Border.all(color: ZveltTokens.border),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(AppIcons.bell, size: 19, color: ZveltTokens.text),
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ZveltTokens.brand,
                        border: Border.all(color: ZveltTokens.bg, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _storiesRail() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 2),
      child: StoriesTray(
        groups: _storyGroups,
        onAddStory: () async {
          final created = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                  builder: (_) => StoryComposerScreen(service: _stories)));
          if (created == true && mounted) _load();
        },
        onOpenGroup: (i) {
          Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => StoryViewerScreen(
              groups: _storyGroups,
              initialGroup: i,
              service: _stories,
              meId: _meId,
              onChanged: _load,
            ),
          ));
        },
      ),
    );
  }

  Widget _pills() {
    // Prototype feedTabs: All · Following · PRs · Fame · Challenges (11px).
    const labels = ['All', 'Following', 'PRs', 'Fame', 'Challenges'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: ZveltTokens.chip,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _tab = i),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: ZMotion.quick,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _tab == i ? ZveltTokens.brand : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _tab == i ? ZveltTokens.glowSm : null,
                    ),
                    child: Text(labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.bodyS.copyWith(
                            fontSize: 11,
                            fontWeight: _tab == i
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: _tab == i
                                ? ZveltTokens.onBrand
                                : ZveltTokens.text2)),
                  ),
                ),
              ),
              if (i < labels.length - 1) const SizedBox(width: 3),
            ],
          ],
        ),
      ),
    );
  }

  // ─── ALL ──────────────────────────────────────────────────────────────────
  List<Widget> _allBlocks() => [
        if (_hero != null) _challengeHero(),
        if (_standings.isNotEmpty) ...[
          _sectionRow('Leaderboard', 'See all', _openChallengeDetail),
          _leaderboardRows(),
        ],
        _postsList(light: false),
        _bottomTiles(),
      ];

  Widget _challengeHero() {
    final c = _hero!;
    final daysLeft = c.endsAt.difference(DateTime.now()).inDays;
    final pct = _myPts == null || _standings.isEmpty
        ? null
        : (_myPts! / (_standings.first.$2 == 0 ? 1 : _standings.first.$2))
            .clamp(0.0, 1.0);
    // Points needed to overtake the person directly above me.
    String? chaseLine;
    if (_myRank != null && _myRank! > 1 && _standings.length >= _myRank!) {
      final above = _standings[_myRank! - 2];
      final need = (above.$2 - (_myPts ?? 0)).clamp(0, double.infinity);
      chaseLine =
          'You need ${_fmtNum(need.round())} pts to overtake ${above.$1}';
    }

    Widget stat(String v, String l) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v,
                style: ZType.bodyL.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: ZveltTokens.onBrand)),
            Text(l,
                style: ZType.monoXS.copyWith(
                    fontSize: 10.5, color: const Color(0xCCFFFFFF))),
          ],
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: InkWell(
        onTap: _openChallengeDetail,
        borderRadius: BorderRadius.circular(ZveltTokens.rCard),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [0, 0.55, 1],
              colors: [Color(0xFF7C5CE0), Color(0xFF5B3FD1), Color(0xFFF0720A)],
            ),
            borderRadius: BorderRadius.circular(ZveltTokens.rCard),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x995C3FD1),
                  blurRadius: 34,
                  offset: Offset(0, 16),
                  spreadRadius: -10),
            ],
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
                      shape: BoxShape.circle, color: Color(0x24FFFFFF)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('ACTIVE CHALLENGE',
                            style: ZType.eyebrow
                                .copyWith(color: const Color(0xE6FFFFFF))),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0x38000000),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                              daysLeft <= 0 ? 'ends today' : '$daysLeft days left',
                              style: ZType.monoXS.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: ZveltTokens.onBrand)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(c.title,
                        style: ZType.h3.copyWith(
                            fontSize: 22, color: ZveltTokens.onBrand)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        stat('${c.participantsCount}', 'players'),
                        const SizedBox(width: 14),
                        if (_myRank != null) ...[
                          stat('#$_myRank', 'rank'),
                          const SizedBox(width: 14),
                        ],
                        if (_myWorkouts != null) ...[
                          stat(_fmtNum(_myWorkouts!.round()), 'workouts'),
                          const SizedBox(width: 14),
                        ],
                        if (_myPts != null)
                          stat(_fmtNum(_myPts!.round()), 'pts'),
                      ],
                    ),
                    if (pct != null) ...[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 7,
                          child: Stack(
                            children: [
                              Container(color: const Color(0x38000000)),
                              FractionallySizedBox(
                                widthFactor: pct.toDouble(),
                                child: Container(color: ZveltTokens.onBrand),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (chaseLine != null) ...[
                      const SizedBox(height: 9),
                      Text(chaseLine,
                          style: ZType.bodyS.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xF2FFFFFF))),
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

  Widget _sectionRow(String title, String action, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      child: Row(
        children: [
          Text(title,
              style: ZType.bodyL.copyWith(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          InkWell(
            onTap: onTap,
            child: Text(action,
                style: ZType.bodyS.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: ZveltTokens.brand)),
          ),
        ],
      ),
    );
  }

  Widget _leaderboardRows() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          for (var i = 0; i < _standings.length && i < 3; i++) ...[
            Builder(builder: (_) {
              // Prototype JS 2020-2021: "You" row gets the orange tint +
              // border; other rows use the plain chip bg, radius 14.
              final isMe = _meId != null && _standings[i].$3 == _meId;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0x24F5820A) : ZveltTokens.chip,
                  borderRadius: BorderRadius.circular(ZveltTokens.rChip),
                  border: Border.all(
                      color: isMe
                          ? const Color(0x66F5820A)
                          : ZveltTokens.border),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text('${i + 1}',
                          style: ZType.bodyM.copyWith(
                              fontWeight: FontWeight.w800,
                              color: ZveltTokens.brand)),
                    ),
                    Expanded(
                      child: Text(_standings[i].$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZType.bodyM
                              .copyWith(fontWeight: FontWeight.w700)),
                    ),
                    Text('${_fmtNum(_standings[i].$2.round())} pts',
                        style: ZType.bodyS.copyWith(
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              );
            }),
            if (i < 2 && i < _standings.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _postsList({required bool light}) {
    if (_posts.isEmpty && !_loading) {
      return Container(
        margin: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ZveltTokens.rBox),
          border: Border.all(color: ZveltTokens.borderStrong),
        ),
        child: Text('No activity yet — share a workout.', style: ZType.bodyS),
      );
    }
    final posts = light
        ? _posts.where((p) => _meId == null || p.userId != _meId).toList()
        : _posts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        children: [
          for (final p in posts.take(12)) ...[
            _postCard(p, light: light),
            const SizedBox(height: 11),
          ],
        ],
      ),
    );
  }

  String _postAction(SocialFeedPost p) {
    if (p.exercises.isNotEmpty) {
      final n = p.exercises.length;
      return 'completed a workout · $n exercise${n == 1 ? '' : 's'}';
    }
    return 'shared an update';
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  Widget _postCard(SocialFeedPost p, {required bool light}) {
    final name = (p.authorName?.trim().isNotEmpty ?? false)
        ? p.authorName!.trim()
        : 'Athlete';
    final detail = p.caption?.trim().isNotEmpty == true
        ? p.caption!.trim()
        : (p.exercises.isNotEmpty
            ? p.exercises.map((e) => e.name).take(3).join(' · ')
            : null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        gradient: ZveltTokens.surface2Grad,
        borderRadius: BorderRadius.circular(ZveltTokens.rCardSm),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: _avatarColor(name)),
                child: Text(_initials(name),
                    style: ZType.bodyM.copyWith(
                        fontWeight: FontWeight.w800,
                        color: ZveltTokens.onBrand)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.bodyM.copyWith(
                            fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(_postAction(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.bodyS.copyWith(fontSize: 12.5)),
                  ],
                ),
              ),
              Text(_ago(p.createdAt),
                  style: ZType.monoXS.copyWith(fontSize: 11.5)),
            ],
          ),
          if (!light && detail != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: ZveltTokens.chip,
                borderRadius: BorderRadius.circular(ZveltTokens.rChip),
                border: Border.all(color: ZveltTokens.border),
              ),
              child: Text(detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodyM.copyWith(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              InkWell(
                onTap: () => _toggleLike(p),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Icon(p.likedByMe ? AppIcons.heart : AppIcons.heart,
                        size: 18,
                        color: p.likedByMe
                            ? ZveltTokens.brand
                            : ZveltTokens.text2),
                    const SizedBox(width: 6),
                    Text('${p.likeCount}',
                        style: ZType.bodyS.copyWith(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              if (!light) ...[
                const SizedBox(width: 16),
                InkWell(
                  onTap: () => _openPost(p),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Icon(AppIcons.comment_alt, size: 18, color: ZveltTokens.text2),
                      const SizedBox(width: 6),
                      Text('${p.commentCount}',
                          style: ZType.bodyS.copyWith(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                InkWell(
                  onTap: () {
                    final txt = detail ?? _postAction(p);
                    SharePlus.instance
                        .share(ShareParams(text: '$name on ZVELT: $txt'));
                  },
                  borderRadius: BorderRadius.circular(8),
                  child:
                      Icon(AppIcons.share, size: 18, color: ZveltTokens.text2),
                ),
              ],
              const Spacer(),
              InkWell(
                onTap: () => _openCreate(),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0x24F5820A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x66F5820A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(AppIcons.bolt,
                          size: 13, color: ZveltTokens.brand),
                      const SizedBox(width: 5),
                      Text('Challenge',
                          style: ZType.bodyS.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: ZveltTokens.brand)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomTiles() {
    Widget tile(String label, VoidCallback onTap, {bool accent = false}) =>
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ZveltTokens.rChip),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent ? ZveltTokens.brand : ZveltTokens.chip,
                borderRadius: BorderRadius.circular(ZveltTokens.rChip),
                border: accent ? null : Border.all(color: ZveltTokens.border),
                boxShadow: accent ? ZveltTokens.glowSm : null,
              ),
              child: Text(label,
                  style: ZType.bodyS.copyWith(
                      fontSize: 12,
                      fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
                      color: accent ? ZveltTokens.onBrand : ZveltTokens.text)),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        children: [
          tile('Post workout', _postWorkout),
          const SizedBox(width: 8),
          tile('Find friends', _findFriends),
          const SizedBox(width: 8),
          tile('Challenge', () => _openCreate(), accent: true),
        ],
      ),
    );
  }

  // ─── FOLLOWING ────────────────────────────────────────────────────────────
  List<Widget> _followingBlocks() => [
        _circleCard(),
        for (final inv in _invites.take(2)) _inviteCard(inv),
        _postsList(light: true),
      ];

  Widget _circleCard() {
    final today = DateUtils.dateOnly(DateTime.now());
    final friendsToday = <String>{};
    var prPosts = 0;
    for (final p in _posts) {
      if (_meId != null && p.userId == _meId) continue;
      if (DateUtils.dateOnly(p.createdAt.toLocal()) == today) {
        friendsToday.add(p.userId);
        final cap = p.caption?.toLowerCase() ?? '';
        if (cap.contains('pr') || cap.contains('record')) prPosts++;
      }
    }
    final activeCount =
        _active.where((c) => c.endsAt.isAfter(DateTime.now())).length;

    Widget stat(String v, String l) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v, style: ZType.h3.copyWith(fontSize: 20)),
            Text(l, style: ZType.monoXS.copyWith(fontSize: 11)),
          ],
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surfaceGrad,
          borderRadius: BorderRadius.circular(ZveltTokens.rCardSm),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('YOUR CIRCLE TODAY',
                style: ZType.eyebrow.copyWith(color: ZveltTokens.brand)),
            const SizedBox(height: 10),
            Row(
              children: [
                stat('${friendsToday.length}', 'trained'),
                const SizedBox(width: 16),
                stat('$prPosts', 'new PRs'),
                const SizedBox(width: 16),
                stat('$activeCount', 'challenge${activeCount == 1 ? '' : 's'}'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _openCreate(),
                    borderRadius: BorderRadius.circular(13),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ZveltTokens.brand,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: ZveltTokens.glowSm,
                      ),
                      child: Text('Challenge a friend',
                          style: ZType.bodyS.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: ZveltTokens.onBrand)),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: InkWell(
                    onTap: _findFriends,
                    borderRadius: BorderRadius.circular(13),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ZveltTokens.chip,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: ZveltTokens.border),
                      ),
                      child: Text('Find friends',
                          style: ZType.bodyS.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: ZveltTokens.text)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _inviteCard(ChallengeInvite inv) {
    final from = inv.fromName?.trim().isNotEmpty == true
        ? inv.fromName!.trim()
        : 'A friend';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surface2Grad,
          borderRadius: BorderRadius.circular(ZveltTokens.rBox),
          border: Border.all(color: const Color(0x59F5820A)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: _avatarColor(from)),
                  child: Text(_initials(from),
                      style: ZType.bodyS.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ZveltTokens.onBrand)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$from challenged you',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZType.bodyM
                              .copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(inv.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZType.bodyS.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _acceptInvite(inv),
                    borderRadius: BorderRadius.circular(13),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ZveltTokens.brand,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Text('Accept',
                          style: ZType.bodyS.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ZveltTokens.onBrand)),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: InkWell(
                    onTap: () => _declineInvite(inv),
                    borderRadius: BorderRadius.circular(13),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ZveltTokens.chip,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: ZveltTokens.border),
                      ),
                      child: Text('Decline',
                          style: ZType.bodyS.copyWith(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── PRS ──────────────────────────────────────────────────────────────────
  List<Widget> _prBlocks() {
    // Prototype JS 2022: fixed category chips. All current PR data is
    // strength PRs, so All/Strength show the real list; the other
    // categories show the honest empty card until data exists.
    const cats = ['All', 'Strength', 'Volume', 'Reps', 'Streaks', 'Body'];
    final shown = _prCat == 'All' || _prCat == 'Strength'
        ? _prs
        : const <RecentPr>[];

    return [
      SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          children: [
            for (final c in cats)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => setState(() => _prCat = c),
                  borderRadius: BorderRadius.circular(ZveltTokens.rChip),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _prCat == c ? ZveltTokens.brand : ZveltTokens.chip,
                      borderRadius: BorderRadius.circular(ZveltTokens.rChip),
                      border: _prCat == c
                          ? null
                          : Border.all(color: ZveltTokens.border),
                    ),
                    child: Text(c,
                        style: ZType.bodyS.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _prCat == c
                                ? ZveltTokens.onBrand
                                : ZveltTokens.text2)),
                  ),
                ),
              ),
          ],
        ),
      ),
      if (shown.isEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ZveltTokens.rBox),
            border: Border.all(color: ZveltTokens.borderStrong),
          ),
          child: Text('No PRs yet — beat a best set to see it here.',
              style: ZType.bodyS),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            children: [
              for (final pr in shown.take(6)) ...[
                _prCard(pr),
                const SizedBox(height: 11),
              ],
            ],
          ),
        ),
      if (_prs.isNotEmpty) _prLeaderboardCard(),
    ];
  }

  Widget _prCard(RecentPr pr) {
    final e1rm = pr.weightKg * (1 + pr.reps / 30);
    final imp = pr.previousBestKg <= 0
        ? 'NEW'
        : '+${(pr.weightKg - pr.previousBestKg).toStringAsFixed(1)} kg';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: ZveltTokens.surface2Grad,
        borderRadius: BorderRadius.circular(ZveltTokens.rCardSm),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(pr.exerciseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZType.bodyL.copyWith(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x29F5820A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x66F5820A)),
                ),
                child: Text(imp,
                    style: ZType.monoXS.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: ZveltTokens.brand)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${pr.weightKg.toStringAsFixed(1)} kg × ${pr.reps}',
              style: ZType.h3.copyWith(fontSize: 22)),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                  pr.previousBestKg > 0
                      ? 'Previous ${pr.previousBestKg.toStringAsFixed(1)} kg'
                      : 'First recorded set',
                  style: ZType.bodyS.copyWith(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 14),
              Text('e1RM ${e1rm.toStringAsFixed(1)} kg',
                  style: ZType.bodyS.copyWith(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => SharePlus.instance.share(ShareParams(
                      text:
                          'New PR on ZVELT — ${pr.exerciseName}: ${pr.weightKg.toStringAsFixed(1)} kg × ${pr.reps} 🏆')),
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ZveltTokens.chip,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: ZveltTokens.border),
                    ),
                    child: Text('Celebrate',
                        style: ZType.bodyS.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: ZveltTokens.text)),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: InkWell(
                  onTap: () => _openCreate(
                      scoringType: 'pr', exerciseId: pr.exerciseId),
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ZveltTokens.brand,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: ZveltTokens.glowSm,
                    ),
                    child: Text('Challenge this PR',
                        style: ZType.bodyS.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: ZveltTokens.onBrand)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _prLeaderboardCard() {
    // Top e1RM per exercise from the user's own recent PRs (real data).
    final best = <String, RecentPr>{};
    for (final pr in _prs) {
      final cur = best[pr.exerciseName];
      if (cur == null || pr.weightKg > cur.weightKg) best[pr.exerciseName] = pr;
    }
    final top = best.values.toList()
      ..sort((a, b) => b.weightKg.compareTo(a.weightKg));
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surfaceGrad,
          borderRadius: BorderRadius.circular(ZveltTokens.rCardSm),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Friends PR Leaderboard · ${mo[DateTime.now().month - 1]}',
                style:
                    ZType.bodyM.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (final pr in top.take(3)) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text('Top ${pr.exerciseName.split(' ').first}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZType.bodyS.copyWith(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      child: Text(
                          'You · ${pr.weightKg.toStringAsFixed(0)} kg',
                          style: ZType.bodyS.copyWith(
                              fontWeight: FontWeight.w700,
                              color: ZveltTokens.text)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── FAME ─────────────────────────────────────────────────────────────────
  List<Widget> _fameBlocks() {
    final myEntry = _fame.where((e) => e.userId == _meId).toList();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
        child: Text('Hall of Fame',
            style:
                ZType.bodyL.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      if (_fame.isEmpty && !_loading)
        Container(
          margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ZveltTokens.rBox),
            border: Border.all(color: ZveltTokens.borderStrong),
          ),
          child: Text('No entries yet — log ranked sets to enter the season.',
              style: ZType.bodyS),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            children: [
              for (final e in _fame) ...[
                _fameRow(e, isMe: e.userId == _meId),
                const SizedBox(height: 9),
              ],
            ],
          ),
        ),
      if (_prs.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
          child: Text('Record holders',
              style: ZType.bodyL
                  .copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        _recordHolders(),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
        child: Text('Your trophies',
            style: ZType.bodyL
                .copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _trophy('${_prs.length}', 'PRs · 30d'),
            if (myEntry.isNotEmpty) ...[
              _trophy('#${myEntry.first.rank}', 'season rank'),
              _trophy('${myEntry.first.lpSeason}', 'LP'),
            ],
            _trophy('${_active.length}', 'challenges'),
          ],
        ),
      ),
    ];
  }

  Widget _fameRow(SeasonLeaderboardEntry e, {required bool isMe}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: ZveltTokens.surface2Grad,
        borderRadius: BorderRadius.circular(ZveltTokens.rControl),
        border: Border.all(
            color: isMe ? const Color(0x66F5820A) : ZveltTokens.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text('${e.rank}',
                style: ZType.bodyM.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ZveltTokens.brand)),
          ),
          // Prototype JS 2016: uniform 46px solid per-user color circle.
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: _avatarColor(e.label)),
            child: Text(_initials(e.label),
                style: ZType.bodyM.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ZveltTokens.onBrand)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(isMe ? '${e.label} (you)' : e.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZType.bodyM.copyWith(
                    fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
          Text('${_fmtNum(e.lpSeason)} pts',
              style: ZType.bodyS.copyWith(
                  fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _recordHolders() {
    final best = <String, RecentPr>{};
    for (final pr in _prs) {
      final cur = best[pr.exerciseName];
      if (cur == null || pr.weightKg > cur.weightKg) best[pr.exerciseName] = pr;
    }
    final top = best.values.toList()
      ..sort((a, b) => b.weightKg.compareTo(a.weightKg));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        childAspectRatio: 1.9,
        children: [
          for (final pr in top.take(4))
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                gradient: ZveltTokens.surface2Grad,
                borderRadius: BorderRadius.circular(ZveltTokens.rControl),
                border: Border.all(color: ZveltTokens.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(pr.exerciseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZType.monoXS.copyWith(fontSize: 11.5)),
                  const SizedBox(height: 4),
                  Text('${pr.weightKg.toStringAsFixed(0)} kg',
                      style: ZType.bodyL.copyWith(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  Text('You',
                      style: ZType.bodyS.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ZveltTokens.brand)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _trophy(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: ZveltTokens.surface2Grad,
        borderRadius: BorderRadius.circular(ZveltTokens.rControl),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Column(
        children: [
          Text(value,
              style: ZType.bodyL
                  .copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(label, style: ZType.monoXS.copyWith(fontSize: 11)),
        ],
      ),
    );
  }

  // ─── CHALLENGES (5th pill — prototype HTML 569–587) ───────────────────────
  List<Widget> _challengesBlocks() {
    final now = DateTime.now();
    final active = _active.where((c) => c.endsAt.isAfter(now)).toList();
    final nothing =
        _invites.isEmpty && active.isEmpty && _completed.isEmpty && !_loading;

    return [
      _createChallengeBanner(),
      if (_invites.isNotEmpty) ...[
        _challengeSectionTitle('Pending invites'),
        for (final inv in _invites.take(4)) _inviteCard(inv),
      ],
      if (active.isNotEmpty) ...[
        _challengeSectionTitle('Active'),
        for (final c in active.take(4)) _activeChallengeCard(c),
      ],
      if (_completed.isNotEmpty) ...[
        _challengeSectionTitle('Completed'),
        for (final c in _completed.take(4)) _completedChallengeRow(c),
      ],
      if (nothing)
        Container(
          margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ZveltTokens.rBox),
            border: Border.all(color: ZveltTokens.borderStrong),
          ),
          child: Text('No challenges yet — create one above.',
              style: ZType.bodyS),
        ),
    ];
  }

  Widget _challengeSectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
        child: Text(t,
            style:
                ZType.bodyL.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      );

  // Create-a-challenge banner (HTML 570): orange gradient, plus box, copy.
  Widget _createChallengeBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: InkWell(
        onTap: () => _openCreate(),
        borderRadius: BorderRadius.circular(ZveltTokens.rCardSm),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment(-1, -0.4),
              end: Alignment(1, 0.6),
              stops: [0, 0.6, 1],
              colors: [Color(0xFFF58A11), Color(0xFFEE6E08), Color(0xFFD85F04)],
            ),
            borderRadius: BorderRadius.circular(ZveltTokens.rCardSm),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x80EE6E08),
                  blurRadius: 30,
                  offset: Offset(0, 14),
                  spreadRadius: -10),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x38FFFFFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(AppIcons.plus,
                    size: 22, color: ZveltTokens.onBrand),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create a challenge',
                        style: ZType.bodyL.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: ZveltTokens.onBrand)),
                    const SizedBox(height: 2),
                    Text('Streak, volume, PR battle & more',
                        style: ZType.bodyS.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xE6FFFFFF))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Active challenge card (HTML 577–581): violet→orange, compact stats.
  Widget _activeChallengeCard(SocialChallenge c) {
    final daysLeft = c.endsAt.difference(DateTime.now()).inDays;
    final isHero = _hero?.id == c.id;
    final stats = <String>[
      '${c.participantsCount} players',
      if (isHero && _myRank != null) 'Rank #$_myRank',
      if (isHero && _myPts != null) '${_fmtNum(_myPts!.round())} pts',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push<void>(MaterialPageRoute<void>(
                builder: (_) => ChallengeDetailScreen(
                    challengeId: c.id, title: c.title)))
            .then((_) => _load()),
        borderRadius: BorderRadius.circular(ZveltTokens.rCardSm),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [0, 0.55, 1],
              colors: [Color(0xFF7C5CE0), Color(0xFF5B3FD1), Color(0xFFF0720A)],
            ),
            borderRadius: BorderRadius.circular(ZveltTokens.rCardSm),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -24,
                top: -24,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Color(0x24FFFFFF)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(c.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ZType.bodyL.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: ZveltTokens.onBrand)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0x38000000),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                              daysLeft <= 0 ? 'ends today' : '${daysLeft}d left',
                              style: ZType.monoXS.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: ZveltTokens.onBrand)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < stats.length; i++) ...[
                          Text(stats[i],
                              style: ZType.bodyS.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xE6FFFFFF))),
                          if (i < stats.length - 1) const SizedBox(width: 14),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Completed row (HTML 583–586): result line + Rematch.
  Widget _completedChallengeRow(SocialChallenge c) {
    final result = _completedResult[c.id];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surface2Grad,
          borderRadius: BorderRadius.circular(ZveltTokens.rBox),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZType.bodyM.copyWith(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    result ??
                        '${c.durationDays} days · ${c.participantsCount} players',
                    style: ZType.bodyS.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: result != null
                            ? ZveltTokens.brand
                            : ZveltTokens.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: () => _openCreate(),
              borderRadius: BorderRadius.circular(13),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                decoration: BoxDecoration(
                  color: ZveltTokens.chip,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: ZveltTokens.borderStrong),
                ),
                child: Text('Rematch',
                    style: ZType.bodyS.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: ZveltTokens.text)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Two-letter initials from the first two name words (prototype: AR, MI,
  /// CD, MA…); single-word names fall back to the first letter.
  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return 'A';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  static String _fmtNum(int v) {
    final s = '$v';
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '$buf';
  }

  /// Prototype avatar palette — stable per-name color.
  static const _avatarPalette = [
    Color(0xFFF0720A),
    Color(0xFFE8724E),
    Color(0xFF3E8E7E),
    Color(0xFF6C7BE0),
    Color(0xFFC9822F),
    Color(0xFFB060C0),
  ];

  static Color _avatarColor(String seed) =>
      _avatarPalette[seed.codeUnits.fold<int>(0, (a, b) => a + b) %
          _avatarPalette.length];
}
