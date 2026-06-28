import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';

import '../../models/social_challenge.dart';
import '../../models/social_feed_post.dart';
import '../../services/_crash_reporter.dart';
import '../../services/feed_refresh_notifier.dart';
import '../../services/auth_service.dart';
import '../../services/social_challenge_service.dart';
import '../../services/social_feed_service.dart';
import '../../services/stories_service.dart';
import '../../services/stats_charts_service.dart';
import '../../services/friends_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/social_challenge_card.dart';
import '../../widgets/social_feed_post_card.dart';
import '../../widgets/stories_tray.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';
import 'circle_screen.dart';
import 'create_challenge_flow.dart';
import 'gallery_screen.dart';
import 'challenges_screen.dart';
import 'story_composer_screen.dart';
import 'story_viewer_screen.dart';
import '../workouts/post_workout_screen.dart';

class SocialPlusScreen extends StatefulWidget {
  const SocialPlusScreen({super.key});

  @override
  State<SocialPlusScreen> createState() => _SocialPlusScreenState();
}

class _SocialPlusScreenState extends State<SocialPlusScreen> {
  final _feedService = SocialFeedService();
  final _challengeService = SocialChallengeService();
  final _storiesService = StoriesService();
  final _authService = AuthService();

  List<SocialFeedPost> _posts = [];
  // PRs tab — the user's real recent personal records (from ranking/stats).
  final _statsService = StatsChartsService();
  List<RecentPr> _recentPrs = const [];
  // Challenges tab — pending invites awaiting accept/decline.
  List<ChallengeInvite> _invites = const [];
  // Guards against rapid double-taps firing duplicate accept/decline requests.
  final Set<String> _mutatingInvites = {};
  // Following tab — circle summary (friend count).
  final _friendsService = FriendsService();
  int _friendCount = 0;
  bool _friendCountLoaded = false;
  List<SocialChallenge> _challenges = [];

  // Ephemeral 24h stories shown in the top rail. Loaded separately from (and
  // never blocking) the main feed — a stories failure leaves an empty rail.
  List<StoryAuthorGroup> _storyGroups = const [];
  String? _meId;
  bool _loading = true;
  String? _error;
  SocialFeedException? _feedError;

  /// Participant count for the "Race of the Week" hero card. Fetched lazily
  /// after [_challenges] resolves so the initial page render isn't blocked
  /// on an extra round-trip. Sentinel `0` is ambiguous (could mean "no one
  /// joined yet" OR "still loading") — pair with [_heroLoading] to tell them
  /// apart.
  int _heroParticipantCount = 0;

  /// First letters of up to 5 real participants (design's overlapping
  /// avatar strip on the hero). Empty until the participants fetch lands.
  List<String> _heroParticipantInitials = const [];

  /// Wave 22 P1.1 — true while [_loadHeroParticipants] is in-flight. Without
  /// this the hero subtitle reads "0 athletes competing" during the brief
  /// window between the feed page rendering and the participant count
  /// returning, which feels like an empty race.
  bool _heroLoading = false;

  // Page/limit pagination state (matches backend /v1/posts/feed).
  final ScrollController _scrollController = ScrollController();
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  String _trendingFilter = 'trending';
  String _feedFilter = 'all';

  // Generation counter — every filter change / fresh load bumps this so any
  // in-flight load from a prior generation is ignored when it returns.
  int _loadGen = 0;

  /// Maps current UI filter state to API params. `friends` (from the
  /// trending/friends toggle) is a stricter subset and wins over `following`.
  ({String? sort, String? scope, String? kind}) _filterParams() {
    String? sort;
    String? scope;
    String? kind;
    switch (_feedFilter) {
      case 'following':
        scope = 'following';
        break;
      case 'popular':
        sort = 'popular';
        break;
      case 'races':
        kind = 'race';
        break;
      case 'prs':
        kind = 'pr';
        break;
      // 'all' → leave all null
    }
    if (_trendingFilter == 'trending') {
      // Don't shadow an explicit Popular pill — the toggle's default
      // 'trending' used to overwrite it, making Popular functionally inert.
      sort ??= 'trending';
    } else if (_trendingFilter == 'friends') {
      scope = 'friends'; // stricter; overrides 'following'
    }
    return (sort: sort, scope: scope, kind: kind);
  }

  void _onFilterChanged() {
    setState(() {
      _page = 1;
      _hasMore = true;
    });
    _load();
  }

  bool _hasActiveFilter() {
    // Default state is _feedFilter='all' + _trendingFilter='trending'; that is
    // what the user sees on first load and is treated as "no filter applied"
    // for the empty-state hint. Anything else is considered active.
    return _feedFilter != 'all' || _trendingFilter != 'trending';
  }

  // Light redesign (mockup 9): All / Following / PRs / Challenges. PRs filters on
  // the backend post-kind 'pr' (posts whose workout set a personal record).
  static const _filters = [
    _FeedFilter(id: 'all', label: 'All'),
    _FeedFilter(id: 'following', label: 'Following'),
    _FeedFilter(id: 'prs', label: 'PRs'),
    _FeedFilter(id: 'races', label: 'Challenges'),
  ];

  late final ValueNotifier<int> _feedRefreshTrigger =
      FeedRefreshNotifier.instance.notifier(RefreshScope.feed);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _feedRefreshTrigger.addListener(_onFeedRefreshHint);
    _load();
    _loadRecentPrs();
    _loadInvites();
    _loadFriendCount();
  }

  Future<void> _loadFriendCount() async {
    try {
      final friends = await _friendsService.listFriends();
      if (mounted) {
        setState(() {
          _friendCount = friends.length;
          _friendCountLoaded = true;
        });
      }
    } catch (_) {
      // Best-effort — the circle summary just won't show a count.
    }
  }

  Future<void> _loadRecentPrs() async {
    try {
      final prs = await _statsService.getRecentPrs(days: 90);
      if (mounted) setState(() => _recentPrs = prs);
    } catch (_) {
      // PRs are a best-effort enrichment of the PRs tab — empty is fine.
    }
  }

  Future<void> _loadInvites() async {
    try {
      final invites = await _challengeService.listInvites();
      if (mounted) setState(() => _invites = invites);
    } catch (_) {
      // Pending invites are best-effort — empty is fine.
    }
  }

  Future<void> _acceptInvite(ChallengeInvite inv) async {
    if (!_mutatingInvites.add(inv.id)) return; // already in flight
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _invites = _invites.where((i) => i.id != inv.id).toList());
    try {
      await _challengeService.joinChallenge(inv.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Joined the challenge.')));
      _load(); // the accepted challenge now belongs in the active list
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      _loadInvites(); // restore on failure
    } finally {
      _mutatingInvites.remove(inv.id);
    }
  }

  Future<void> _declineInvite(ChallengeInvite inv) async {
    if (!_mutatingInvites.add(inv.id)) return; // already in flight
    setState(() => _invites = _invites.where((i) => i.id != inv.id).toList());
    try {
      await _challengeService.declineChallenge(inv.id);
    } catch (_) {
      if (!mounted) return;
      _loadInvites(); // restore on failure
    } finally {
      _mutatingInvites.remove(inv.id);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _feedRefreshTrigger.removeListener(_onFeedRefreshHint);
    super.dispose();
  }

  void _onFeedRefreshHint() {
    if (!mounted) return;
    _load();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent * 0.8) _loadMore();
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    final params = _filterParams();
    setState(() {
      _loading = true;
      _error = null;
      _feedError = null;
      _page = 1;
      _hasMore = true;
    });
    try {
      final results = await Future.wait([
        _feedService.getFeedPage(
          page: 1,
          sort: params.sort,
          scope: params.scope,
          kind: params.kind,
        ),
        _challengeService.loadActive(),
      ]);
      if (!mounted || gen != _loadGen) return; // stale result, ignore
      final page = results[0] as SocialFeedPage;
      setState(() {
        _posts = page.posts;
        _page = 2;
        _hasMore = page.hasMore;
        _challenges = results[1] as List<SocialChallenge>;
        // Wave 22 P1.1 — reset count + flip loading flag so the hero card
        // renders "Be the first to join" until participants resolve.
        _heroParticipantCount = 0;
        _heroLoading = _topChallenge != null;
        _loading = false;
      });
      _loadHeroParticipants(gen);
      _loadStories(gen);
    } on SocialFeedException catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _feedError = e;
        _error = e.message;
        _loading = false;
      });
      _snackIfContentVisible("Couldn't refresh the feed.");
    } catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
      _snackIfContentVisible("Couldn't refresh the feed.");
    }
  }

  /// Loads the stories rail out-of-band so it never blocks (or breaks) the main
  /// feed. Resolves the current user id once so the rail can flag "your story"
  /// and the viewer can offer delete.
  Future<void> _loadStories(int gen) async {
    try {
      final results = await Future.wait([
        _storiesService.getFeed(),
        if (_meId == null) _authService.getCurrentUserId() else Future.value(_meId),
      ]);
      if (!mounted || gen != _loadGen) return;
      final stories = results[0] as List<Story>;
      final meId = results.length > 1 ? results[1] as String? : _meId;
      setState(() {
        _meId = meId;
        _storyGroups = groupStoriesByAuthor(stories, meId: meId);
      });
    } catch (e, st) {
      // Stories are non-critical — log and leave the rail empty.
      reportError(e, st, reason: 'social:loadStories');
    }
  }

  Future<void> _openStoryComposer() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => StoryComposerScreen(service: _storiesService)),
    );
    if (created == true && mounted) _loadStories(_loadGen);
  }


  void _openStoryGroup(int groupIndex) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(
          groups: _storyGroups,
          initialGroup: groupIndex,
          service: _storiesService,
          meId: _meId,
          onChanged: () {
            if (mounted) _loadStories(_loadGen);
          },
        ),
      ),
    );
  }

  /// Background-refresh failures with content on screen get a snackbar —
  /// the full error state only replaces an EMPTY feed (see build()).
  void _snackIfContentVisible(String msg) {
    if (!mounted || (_posts.isEmpty && _challenges.isEmpty)) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final gen = _loadGen;
    final params = _filterParams();
    setState(() => _loadingMore = true);
    try {
      final page = await _feedService.getFeedPage(
        page: _page,
        sort: params.sort,
        scope: params.scope,
        kind: params.kind,
      );
      if (!mounted || gen != _loadGen) return; // filter changed mid-flight
      setState(() {
        // Dedup by id: offset pagination over createdAt-desc can repeat a row
        // across a page boundary if a new post is inserted at the top.
        final existing = _posts.map((p) => p.id).toSet();
        _posts = [..._posts, ...page.posts.where((p) => !existing.contains(p.id))];
        if (page.hasMore) _page += 1;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e, st) {
      reportError(e, st, reason: 'social-plus:load-more-feed');
      if (!mounted || gen != _loadGen) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't load more. Try scrolling again.")),
      );
    }
  }


  Future<void> _newPost() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const PostWorkoutScreen()),
    );
    if (ok == true && mounted) _load();
  }

  Future<void> _createChallenge() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const CreateChallengeFlow(),
      ),
    );
    if (mounted) _load(); // refresh after returning from the flow/detail
  }

  // ── Following tab — circle summary (count + entry to your circle) ─────────
  Widget _buildCircleSummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          onTap: _openCircle,
          child: Container(
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              boxShadow: ZveltTokens.shadowCard,
            ),
            padding: const EdgeInsets.all(ZveltTokens.s4),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ZveltTokens.brandTint,
                    borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                  ),
                  child: const Icon(AppIcons.users, size: 20, color: ZveltTokens.brand),
                ),
                const SizedBox(width: ZveltTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('YOUR CIRCLE',
                          style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
                      const SizedBox(height: 2),
                      Text(
                        _friendCount == 0
                            ? (_friendCountLoaded ? 'Add friends to fill your feed' : 'Loading your circle…')
                            : 'Posts from your $_friendCount friend${_friendCount == 1 ? '' : 's'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                      ),
                    ],
                  ),
                ),
                if (_friendCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ZveltTokens.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      border: Border.all(color: ZveltTokens.success.withValues(alpha: 0.22)),
                    ),
                    child: Text('$_friendCount IN CIRCLE',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: ZveltTokens.success,
                          letterSpacing: 1.6,
                        )),
                  )
                else
                  Icon(AppIcons.angle_small_right, size: 20, color: ZveltTokens.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Challenges tab — pending invites (accept/decline inline) ──────────────
  Widget _buildPendingInvites() {
    if (_invites.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PENDING INVITES', style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
          const SizedBox(height: 12),
          for (final inv in _invites) ...[
            _inviteCard(inv),
            const SizedBox(height: ZveltTokens.cardGap),
          ],
        ],
      ),
    );
  }

  String _inviteSubtitle(ChallengeInvite inv) {
    final from = inv.fromName?.trim();
    final type = _challengeTypeLabel(inv.scoringType);
    if (from != null && from.isNotEmpty) return '$from invited you · $type';
    return type;
  }

  String _challengeTypeLabel(String? scoringType) {
    switch (scoringType) {
      case 'workout_streak':
        return 'Workout Streak';
      case 'most_workouts':
        return 'Most Workouts';
      case 'total_volume':
        return 'Total Volume';
      case 'pr_battle':
        return 'PR Battle';
      case 'consistency':
        return 'Consistency';
      default:
        return 'Challenge';
    }
  }

  Widget _inviteCard(ChallengeInvite inv) {
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      padding: const EdgeInsets.all(ZveltTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                ),
                child: const Icon(AppIcons.trophy, size: 20, color: ZveltTokens.brand),
              ),
              const SizedBox(width: ZveltTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.bodyM.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(_inviteSubtitle(inv),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s3),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _declineInvite(inv),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => _acceptInvite(inv),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── PRs tab — your real recent records + "Challenge this PR" ───────────────
  Widget _buildPrRecords() {
    if (_recentPrs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR RECENT PRs', style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
          const SizedBox(height: 12),
          for (final pr in _recentPrs.take(12)) ...[
            _prCard(pr),
            const SizedBox(height: ZveltTokens.cardGap),
          ],
        ],
      ),
    );
  }

  Widget _prCard(RecentPr pr) {
    final delta = pr.deltaKg;
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      padding: const EdgeInsets.all(ZveltTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                ),
                child: const Icon(AppIcons.trophy, size: 20, color: ZveltTokens.brand),
              ),
              const SizedBox(width: ZveltTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pr.exerciseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.bodyM.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(pr.headline, style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                  ],
                ),
              ),
              if (delta > 0)
                Text('+${delta % 1 == 0 ? delta.toInt() : delta.toStringAsFixed(1)} kg',
                    style: ZType.bodyM.copyWith(color: ZveltTokens.success, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: ZveltTokens.s3),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: ZveltTokens.brandTint,
              borderRadius: BorderRadius.circular(ZveltTokens.rMd),
              child: InkWell(
                borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                onTap: () => _challengeThisPr(pr),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text('Challenge this PR',
                        style: ZType.bodyS.copyWith(color: ZveltTokens.brand, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _challengeThisPr(RecentPr pr) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => CreateChallengeFlow(
        initialScoringType: 'pr_battle',
        initialExerciseId: pr.exerciseId,
        initialExerciseName: pr.exerciseName,
      ),
    ));
    if (mounted) _load();
  }

  Future<void> _confirmRemoveChallenge(SocialChallenge c) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove challenge?'),
        content: Text('Remove "${c.title}" from your list?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    await _challengeService.remove(c.id);
    await _load();
  }

  void _openCircle() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CircleScreen()),
    );
  }

  void _openGallery() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GalleryScreen()),
    );
  }

  // Guards against rapid re-taps: without these, every tap on "JOIN THE
  // RACE" queued another join + push, stacking N RaceHub screens.
  bool _openingRaceHub = false;
  bool _joiningRace = false;

  Future<void> _openRaceHub({String? initialChallengeId}) async {
    if (_openingRaceHub) return;
    _openingRaceHub = true;
    try {
      // Await the push — the flag stays up while the hub is open, so taps
      // that land during the route transition can't stack a second copy.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ChallengesScreen(),
        ),
      );
    } finally {
      _openingRaceHub = false;
    }
  }

  /// Picks the "Race of the Week" hero — currently the most-recently-created
  /// active challenge (`loadActive()` already sorts by `createdAt DESC`).
  /// TODO(v1.1): swap to a `trendingScore` field on the server response so
  /// the hero genuinely tracks viral races instead of newest.
  SocialChallenge? get _topChallenge =>
      _challenges.isEmpty ? null : _challenges.first;

  Future<void> _joinAndOpenRace(SocialChallenge c) async {
    if (_joiningRace || _openingRaceHub) return;
    _joiningRace = true;
    try {
      await _challengeService.joinChallenge(c.id);
    } catch (e, st) {
      // Already-joined / network failures are non-fatal — we still open the
      // hub so the user lands somewhere actionable.
      reportError(e, st, reason: 'social-plus:join-from-hero');
    } finally {
      _joiningRace = false;
    }
    if (!mounted) return;
    await _openRaceHub(initialChallengeId: c.id);
  }

  /// Wave 22 P1.1 — guarded with the same [_loadGen] counter as [_load] so
  /// rapid filter changes can't cause a stale participant fetch to overwrite
  /// a newer one. Flips [_heroLoading] off only when the response for the
  /// *current* generation lands.
  Future<void> _loadHeroParticipants(int gen) async {
    final c = _topChallenge;
    if (c == null) {
      if (mounted && gen == _loadGen) setState(() => _heroLoading = false);
      return;
    }
    try {
      final res = await _challengeService.getChallengeParticipants(c.id);
      if (!mounted || gen != _loadGen) return; // stale, ignore
      setState(() {
        _heroParticipantCount = (res['total'] as num?)?.toInt() ?? 0;
        // Design hero shows overlapping participant avatars — REAL initials
        // from the participants payload, never invented letters.
        _heroParticipantInitials = ((res['data'] as List<dynamic>?) ?? const [])
            .take(5)
            .map((p) {
              final name =
                  ((p as Map<String, dynamic>)['displayName'] as String?)?.trim() ?? '';
              return name.isNotEmpty ? name[0].toUpperCase() : '?';
            })
            .toList();
        _heroLoading = false;
      });
    } catch (e, st) {
      reportError(e, st, reason: 'social-plus:hero-participants');
      if (!mounted || gen != _loadGen) return;
      setState(() => _heroLoading = false);
    }
  }

  Widget _buildFeedErrorState() {
    final err = _feedError;
    final ZveltErrorTier tier;
    if (err?.isNetworkError ?? false) {
      tier = ZveltErrorTier.network;
    } else if (err?.isAuthError ?? false) {
      tier = ZveltErrorTier.auth;
    } else if (err?.isServerError ?? false) {
      tier = ZveltErrorTier.server;
    } else {
      tier = ZveltErrorTier.generic;
    }
    return ZveltErrorState(
      tier: tier,
      title: "Couldn't load your feed",
      onRetry: _load,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        bottom: false,
        // Full-screen spinner ONLY on first load. With content on screen a
        // reload (pull-to-refresh, push refresh-hint, filter change) keeps
        // the list visible — previously a friend liking your post mid-read
        // wiped the feed to a spinner and reset your scroll to the top.
        child: _loading && _posts.isEmpty && _challenges.isEmpty
            ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
            : _error != null && _posts.isEmpty
                ? _buildFeedErrorState()
                : RefreshIndicator(
                    color: ZveltTokens.brand,
                    onRefresh: _load,
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverToBoxAdapter(child: _buildHeader()),
                        SliverToBoxAdapter(
                          child: StoriesTray(
                            groups: _storyGroups,
                            onAddStory: _openStoryComposer,
                            onOpenGroup: _openStoryGroup,
                          ),
                        ),
                        SliverToBoxAdapter(child: _buildRaceHeroCard()),
                        SliverToBoxAdapter(child: _buildFeedControls()),
                        if (_feedFilter == 'following')
                          SliverToBoxAdapter(child: _buildCircleSummary()),
                        if (_feedFilter == 'races' && _invites.isNotEmpty)
                          SliverToBoxAdapter(child: _buildPendingInvites()),
                        if (_challenges.isNotEmpty) ...[
                          SliverToBoxAdapter(child: _buildChallengeHeader()),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => SocialChallengeCard(
                                key: ValueKey('chall-${_challenges[i].id}'),
                                challenge: _challenges[i],
                                onDelete: () => _confirmRemoveChallenge(_challenges[i]),
                              ),
                              childCount: _challenges.length,
                            ),
                          ),
                        ],
                        if (_feedFilter == 'prs')
                          SliverToBoxAdapter(child: _buildPrRecords()),
                        SliverToBoxAdapter(child: _buildFeedHeader()),
                        if (_posts.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              child: _hasActiveFilter()
                                  ? ZveltEmptyState(
                                      compact: true,
                                      icon: AppIcons.filter_slash,
                                      title: 'No posts matching this filter',
                                      subtitle: 'Try the All filter to widen your feed.',
                                      action: TextButton(
                                        onPressed: () {
                                          _feedFilter = 'all';
                                          _trendingFilter = 'trending';
                                          _onFilterChanged();
                                        },
                                        child: const Text('Reset filter'),
                                      ),
                                    )
                                  : const ZveltEmptyState(
                                      mascot: 'assets/mascot/m8.png',
                                      icon: AppIcons.camera,
                                      title: 'Your feed is quiet',
                                      subtitle: 'Post your first workout or challenge a friend.',
                                    ),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) {
                                final post = _posts[i];
                                return RepaintBoundary(
                                  child: SocialFeedPostCard(
                                  key: ValueKey(post.id),
                                  post: post,
                                  service: _feedService,
                                  onLike: () {},
                                  // Without these, Hide/Block/Delete left the
                                  // card on screen (a blocked user's post kept
                                  // staring at you) and edited captions only
                                  // showed after a full reload.
                                  onDelete: () => setState(() =>
                                      _posts.removeWhere((p) => p.id == post.id)),
                                  onEdit: (updated) => setState(() {
                                    final idx = _posts
                                        .indexWhere((p) => p.id == updated.id);
                                    if (idx != -1) _posts[idx] = updated;
                                  }),
                                  ),
                                );
                              },
                              childCount: _posts.length,
                            ),
                          ),
                        if (_posts.isNotEmpty)
                          SliverToBoxAdapter(child: _buildFeedFooter()),
                        SliverToBoxAdapter(child: SizedBox(height: mq.padding.bottom + 24)),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ── header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Feed',
                  style: ZType.h1.copyWith(letterSpacing: -0.5),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Open gallery',
            child: GestureDetector(
              onTap: _openGallery,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZveltTokens.surface,
                  border: Border.all(color: ZveltTokens.border),
                ),
                child: Icon(AppIcons.camera, color: ZveltTokens.text2, size: 20),
              ),
            ),
          ),
          const SizedBox(width: ZveltTokens.s2),
          Semantics(
            button: true,
            label: 'Open your circle',
            child: GestureDetector(
              onTap: _openCircle,
              behavior: HitTestBehavior.opaque,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: ZveltTokens.gradBtn,
                      boxShadow: [
                        BoxShadow(
                          color: ZveltTokens.brand.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(AppIcons.users, color: Colors.white, size: 20),
                  ),
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ZveltTokens.success,
                        border: Border.all(color: ZveltTokens.bg, width: 1.5),
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

  // ── stories ────────────────────────────────────────────────────────────────

  // ── race hero card ─────────────────────────────────────────────────────────

  Widget _buildRaceHeroCard() {
    final top = _topChallenge;
    // No active challenges yet — show a soft CTA pointing to the Race Hub
    // so the user can create the first one. Hiding the card entirely would
    // leave the screen feeling empty for new accounts.
    if (top == null) return _buildEmptyRaceHeroCard();

    final daysLeft = top.endsAt.difference(DateTime.now()).inDays.clamp(0, 999);
    final athletes = _heroParticipantCount;
    final endsLabel = daysLeft == 0
        ? 'ends today'
        : daysLeft == 1
            ? 'ends in 1 day'
            : 'ends in $daysLeft days';
    // Wave 22 P1.1 — distinguish "still loading" from "no one joined yet".
    // While the participant fetch is in flight, show only the time-left
    // line. Once it lands, render either "Be the first to join · ends …"
    // (zero participants) or "N athlete(s) competing · ends …".
    final String subtitle;
    if (_heroLoading) {
      subtitle = endsLabel.substring(0, 1).toUpperCase() + endsLabel.substring(1);
    } else if (athletes == 0) {
      subtitle = 'Be the first to join · $endsLabel';
    } else {
      final athletesLabel = athletes == 1 ? '1 athlete' : '$athletes athletes';
      subtitle = '$athletesLabel competing · $endsLabel';
    }

    // ── Design (screens-social.jsx hero): quiet white card r20 p18 —
    // trophy eyebrow, title 18/600, "N athletes · ends in X" meta, then a
    // compact dark "Join challenge" pill + overlapping REAL participant
    // initials. Replaces the V1 take (900-italic title, TRENDING/PUBLIC
    // badges, full-width CTA). Whole card taps into the Race Hub.
    final initials = _heroParticipantInitials;
    final overflow = (athletes - initials.length).clamp(0, 99999);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: GestureDetector(
        onTap: _openRaceHub,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(ZveltTokens.s5),
          decoration: BoxDecoration(
            gradient: ZveltTokens.gradBrand,
            borderRadius: BorderRadius.circular(ZveltTokens.rXl),
            boxShadow: ZveltTokens.shadowHero,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(AppIcons.trophy, size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    'ACTIVE CHALLENGE',
                    style: ZType.eyebrow.copyWith(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                top.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ZType.h4.copyWith(color: Colors.white),
              ),
              const SizedBox(height: ZveltTokens.s1),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: ZveltTokens.s3),
              Row(
                children: [
                  // Compact dark join pill (design PillBtn dark/sm + bolt).
                  Semantics(
                    button: true,
                    label: 'Join challenge',
                    child: GestureDetector(
                    onTap: () => _joinAndOpenRace(top),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: ZveltTokens.s4, vertical: ZveltTokens.s2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(AppIcons.bolt, size: 14, color: ZveltTokens.brand),
                          SizedBox(width: 6),
                          Text(
                            'Join challenge',
                            style: TextStyle(
                              fontFamily: ZveltTokens.fontPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: ZveltTokens.brand,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ),
                  const Spacer(),
                  // Overlapping participant initials — real names only.
                  if (initials.isNotEmpty) ...[
                    SizedBox(
                      height: 24,
                      width: 24.0 + (initials.length - 1) * 14.0,
                      child: Stack(
                        children: [
                          for (var i = 0; i < initials.length; i++)
                            Positioned(
                              left: i * 14.0,
                              child: Container(
                                width: 24,
                                height: 24,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: ZveltTokens.brandDeep,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: Text(
                                  initials[i],
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (overflow > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '+$overflow',
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fallback hero shown when there are zero active challenges — links to
  /// the Race Hub so the user can launch the first one.
  Widget _buildEmptyRaceHeroCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: GestureDetector(
        onTap: () => _openRaceHub(),
        child: Container(
          padding: const EdgeInsets.all(ZveltTokens.s5),
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            boxShadow: ZveltTokens.shadowCard,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZveltTokens.brand.withValues(alpha: 0.12),
                  border: Border.all(
                      color: ZveltTokens.brand.withValues(alpha: 0.25)),
                ),
                child: const Icon(AppIcons.flag,
                    color: ZveltTokens.brand, size: 20),
              ),
              const SizedBox(width: ZveltTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No active races',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: ZveltTokens.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Launch the first race in the Hub',
                      style: TextStyle(
                          fontSize: 11,
                          color: ZveltTokens.text2),
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.angle_small_right,
                  color: ZveltTokens.text2),
            ],
          ),
        ),
      ),
    );
  }

  // ── feed controls ──────────────────────────────────────────────────────────

  Widget _buildFeedControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Single filter row (spec): All / Following / PRs / Challenges
          // Filter pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.map((f) {
                final sel = _feedFilter == f.id;
                return Padding(
                  padding: const EdgeInsets.only(right: ZveltTokens.s2),
                  child: Semantics(
                    button: true,
                    selected: f.id != 'races' && sel,
                    label: f.id == 'races' ? 'Races, opens Race Hub' : '${f.label} filter',
                    child: GestureDetector(
                      onTap: () {
                        // Wave 22 P1.2 — Races pill is a navigation shortcut to
                        // the dedicated Race Hub, NOT a feed filter. Previously
                        // it mutated _feedFilter='races' before opening the hub,
                        // leaving the feed stuck on an empty filter when the
                        // user came back. Other pills behave as before.
                        if (f.id == 'races') {
                          _openRaceHub();
                          return;
                        }
                        // _onFilterChanged() actually reloads the feed — the
                        // old bare setState only repainted the pill highlight
                        // while the posts stayed on the previous filter.
                        _feedFilter = f.id;
                        _onFilterChanged();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3),
                        decoration: BoxDecoration(
                          color: sel ? ZveltTokens.text : ZveltTokens.surface,
                          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                          border: sel ? null : Border.all(color: ZveltTokens.border),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          f.label,
                          style: TextStyle(
                            color: sel ? ZveltTokens.bg : ZveltTokens.text2,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            fontFamily: ZveltTokens.fontPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── challenges header ──────────────────────────────────────────────────────

  Widget _buildChallengeHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Icon(AppIcons.trophy, size: 14, color: ZveltTokens.text2),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'ACTIVE CHALLENGES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: ZveltTokens.text2,
                letterSpacing: 2.0,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'New challenge',
            child: GestureDetector(
            onTap: _createChallenge,
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: ZveltTokens.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                border: Border.all(color: ZveltTokens.brand.withValues(alpha: 0.25)),
              ),
              alignment: Alignment.center,
              child: const Text(
                '+ NEW',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: ZveltTokens.brand,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }

  // ── pagination footer ──────────────────────────────────────────────────────

  Widget _buildFeedFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.brand),
          ),
        ),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Center(
          child: Text(
            "You've reached the end",
            style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // ── community feed header ──────────────────────────────────────────────────

  Widget _buildFeedHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'COMMUNITY FEED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: ZveltTokens.text2,
                letterSpacing: 2.0,
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'New post',
            child: GestureDetector(
              onTap: _newPost,
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  gradient: ZveltTokens.gradBtn,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  boxShadow: [
                    BoxShadow(
                      color: ZveltTokens.brand.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text(
                  '+ POST',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── filter model ───────────────────────────────────────────────────────────────

class _FeedFilter {
  const _FeedFilter({required this.id, required this.label});
  final String id;
  final String label;
}

// ── story widgets ──────────────────────────────────────────────────────────────
