import 'dart:convert';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart' show v1Base;
import '../../services/_crash_reporter.dart';
import '../../services/auth_service.dart';
import '../../services/friends_service.dart';
import '../../services/messages_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../social/direct_chat_screen.dart';
import '../social/friends_screen.dart';

// TODO(v1.1): if backend ships /v1/friends/{userId}/poke + nudges feed,
// reintroduce POKE button here.

class CircleScreen extends StatefulWidget {
  const CircleScreen({super.key});

  @override
  State<CircleScreen> createState() => _CircleScreenState();
}

class _CircleScreenState extends State<CircleScreen> {
  final _searchCtrl = TextEditingController();
  final _friendsService = FriendsService(auth: AuthService());
  final _messagesService = MessagesService();
  // userIds currently opening a DM — disables the chat button while in-flight.
  final Set<String> _openingChatFor = {};

  List<FriendSummary> _friends = [];
  // Lowercased trimmed query bound to _searchCtrl. Empty = show all.
  // Wired client-side because /v1/friends already returns the full list
  // and we'd rather not fire a /v1/users/search per keystroke.
  String _searchQuery = '';
  final Map<String, int> _friendStreaks = {};
  // userIds whose streak result is known (loaded OR timed-out/failed).
  // We use this to distinguish "still fetching" from "fetch finished but
  // no data" so the row can show a dim "—" instead of spinning forever.
  final Set<String> _streakResolved = {};
  bool _loadingFriends = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final friends = await _friendsService.listFriends();
      if (!mounted) return;
      // Render the friend list IMMEDIATELY with placeholder streaks. The
      // streak fetch is fired separately so a slow backend never blocks
      // the rest of the UI.
      setState(() {
        _friends = friends;
        _loadingFriends = false;
      });
      _fetchStreaksNonBlocking(friends);
    } catch (e, st) {
      reportError(e, st, reason: 'circle:load-friends');
      if (!mounted) return;
      setState(() => _loadingFriends = false);
    }
  }

  /// Fires the bulk streak fetch with a 10s timeout. Updates each friend
  /// row independently as data arrives; any friend missing from the
  /// response (or all of them on timeout) stays as a dim "—". Errors are
  /// swallowed silently — we show at most one global toast.
  void _fetchStreaksNonBlocking(List<FriendSummary> friends) {
    () async {
      final token = await AuthService().getAccessToken();
      if (token == null) throw Exception('no token');
      final res = await http
          .get(
            Uri.parse('$v1Base/friends/streaks'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('http ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rawList = (body['data'] as List<dynamic>? ?? []);
      final result = <String, int>{};
      for (final entry in rawList) {
        final map = entry as Map<String, dynamic>;
        final userId = map['userId'] as String?;
        final streak = map['currentStreak'] as int?;
        if (userId != null && streak != null) result[userId] = streak;
      }
      return result;
    }()
        .then((streaks) {
      if (!mounted) return;
      setState(() {
        _friendStreaks.addAll(streaks);
        for (final f in friends) {
          _streakResolved.add(f.userId);
        }
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        for (final f in friends) {
          _streakResolved.add(f.userId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't load some streaks"),
          duration: Duration(seconds: 3),
        ),
      );
    });
  }

  static int _hueFrom(String name) =>
      (name.codeUnits.fold(0, (s, c) => s + c) % 9);

  List<_StreakUser> get _topStreaks {
    // Sort by actual streak (descending, unknowns last) so the 'TOP STREAKS'
    // heading is true — it used to be just the first 3 friends in whatever
    // order /v1/friends returned, which could showcase a 0-day streak while
    // hiding the real leader.
    final sorted = List.of(_filteredFriends)
      ..sort((a, b) {
        final sa = _friendStreaks[a.userId] ?? -1;
        final sb = _friendStreaks[b.userId] ?? -1;
        return sb.compareTo(sa);
      });
    return sorted.take(3).map((f) {
      final resolved = _streakResolved.contains(f.userId);
      return _StreakUser(
        name: f.label,
        // null = unknown (still fetching, timed out, or missing in response)
        days: resolved ? _friendStreaks[f.userId] : null,
        hue: _hueFrom(f.label),
      );
    }).toList();
  }

  List<_RecentUser> get _recent => _filteredFriends.take(5).map((f) {
        return _RecentUser(
          userId: f.userId,
          name: f.label,
          sub: 'IN YOUR CIRCLE',
          hue: _hueFrom(f.label),
          online: false,
        );
      }).toList();

  Future<void> _openChat(_RecentUser u) async {
    if (_openingChatFor.contains(u.userId)) return;
    setState(() => _openingChatFor.add(u.userId));
    try {
      final opened = await _messagesService.openConversation(u.userId);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DirectChatScreen(
            conversationId: opened.conversationId,
            peer: opened.peer,
          ),
        ),
      );
    } catch (e, st) {
      reportError(e, st, reason: 'circle:open-chat');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingChatFor.remove(u.userId));
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 16),
                children: [
                  const SizedBox(height: 16),
                  _buildSearchBar(),
                  if (_loadingFriends)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator(color: ZveltTokens.brand, strokeWidth: 2)),
                    )
                  else ...[
                  const SizedBox(height: 22),
                  if (_topStreaks.isNotEmpty) _buildTopStreaks(),
                  const SizedBox(height: 22),
                  _buildRecentlyActive(),
                  ],
                  const SizedBox(height: 22),
                  _buildFindMoreCta(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(AppIcons.angle_small_left, size: 18),
            color: ZveltTokens.text2,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              'THE CIRCLE',
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: ZveltTokens.text,
                letterSpacing: 1.5,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const FriendsScreen()),
            ),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ZveltTokens.gradBtn,
                boxShadow: [
                  BoxShadow(
                    color: ZveltTokens.brand.withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(AppIcons.user_add, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: ZveltTokens.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(AppIcons.search, color: ZveltTokens.text2, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: ZveltTokens.text, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search your friends…',
                hintStyle: TextStyle(color: ZveltTokens.text2, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(AppIcons.cross_small,
                            color: ZveltTokens.text2, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
              ),
              onChanged: (v) =>
                  setState(() => _searchQuery = v.trim().toLowerCase()),
            ),
          ),
        ],
      ),
    );
  }

  /// Friend list filtered by [_searchQuery] on displayName + username.
  /// Empty query returns the full list. Both fields are nullable on
  /// [FriendSummary] so we coalesce to empty string before matching.
  List<FriendSummary> get _filteredFriends {
    if (_searchQuery.isEmpty) return _friends;
    return _friends.where((f) {
      final name = (f.displayName ?? '').toLowerCase();
      final user = (f.username ?? '').toLowerCase();
      return name.contains(_searchQuery) || user.contains(_searchQuery);
    }).toList();
  }

  Widget _buildTopStreaks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🔥  TOP STREAKS',
          style: ZType.eyebrow.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: ZveltTokens.text2,
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: _topStreaks.map((s) => _StreakAvatar(user: s)).toList(),
        ),
      ],
    );
  }

  Widget _buildRecentlyActive() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'RECENTLY ACTIVE',
                style: ZType.eyebrow.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: ZveltTokens.text2,
                  letterSpacing: 2.2,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: ZveltTokens.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                border: Border.all(color: ZveltTokens.success.withValues(alpha: 0.22)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: ZveltTokens.success,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _searchQuery.isEmpty
                        ? '${_friends.length} IN CIRCLE'
                        : '${_filteredFriends.length} OF ${_friends.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: ZveltTokens.success,
                      letterSpacing: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_recent.isEmpty)
          const ZveltEmptyState(
            compact: true,
            icon: AppIcons.users,
            title: 'No recent activity',
            subtitle: 'Add friends to see their activity here.',
          )
        else Container(
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            boxShadow: ZveltTokens.shadowCard,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: _recent.asMap().entries.map((e) {
              final i = e.key;
              final u = e.value;
              final opening = _openingChatFor.contains(u.userId);
              return _RecentUserRow(
                user: u,
                isLast: i == _recent.length - 1,
                opening: opening,
                onChat: opening ? null : () => _openChat(u),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // Clean CTA that replaces the former hardcoded "Discover Athletes" panel.
  // No fake users; just a clear path to find real friends by username.
  Widget _buildFindMoreCta() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FIND MORE ATHLETES',
          style: ZType.eyebrow.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: ZveltTokens.text2,
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(height: 10),
        Container(
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
                  color: ZveltTokens.surface2,
                  border: Border.all(color: ZveltTokens.border),
                ),
                child: Icon(
                  AppIcons.search,
                  color: ZveltTokens.text2,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Search by username to add real friends.',
                  style: ZType.bodyS.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ZveltTokens.text2,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const FriendsScreen()),
                ),
                child: Container(
                  height: 36,
                  constraints: const BoxConstraints(minWidth: 80),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: ZveltTokens.gradBtn,
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                    boxShadow: [
                      BoxShadow(
                        color: ZveltTokens.brand.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'SEARCH',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── data ──────────────────────────────────────────────────────────────────────

class _StreakUser {
  const _StreakUser({required this.name, required this.days, required this.hue});
  final String name;
  // null = streak unknown (still loading or timed out). Distinct from 0
  // which is a valid loaded value.
  final int? days;
  final int hue;
}

class _RecentUser {
  const _RecentUser({
    required this.userId,
    required this.name,
    required this.sub,
    required this.hue,
    required this.online,
  });
  final String userId;
  final String name;
  final String sub;
  final int hue;
  final bool online;
}

// ── widgets ───────────────────────────────────────────────────────────────────

class _CircleAvatar extends StatelessWidget {
  const _CircleAvatar({required this.name, required this.hue, this.size = 42, this.online = false});

  final String name;
  final int hue;
  final double size;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = HSVColor.fromAHSV(1, hue * 40.0, 0.7, 0.85).toColor();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, color.withValues(alpha: 0.6)],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontSize: size * 0.42,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        if (online)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: size * 0.26,
              height: size * 0.26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ZveltTokens.success,
                border: Border.all(color: ZveltTokens.bg, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

class _StreakAvatar extends StatelessWidget {
  const _StreakAvatar({required this.user});
  final _StreakUser user;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            // (Removed a vestigial 8px 'streak ring' that rendered entirely
            // behind the 64px avatar — dead pixels on every card.)
            _CircleAvatar(name: user.name, hue: user.hue, size: 64),
            Positioned(
              bottom: -4,
              right: -4,
              child: Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  gradient: ZveltTokens.gradBtn,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  border: Border.all(color: ZveltTokens.bg, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: ZveltTokens.brand.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppIcons.flame,
                      color: user.days == null
                          ? Colors.white.withValues(alpha: 0.55)
                          : Colors.white,
                      size: 9,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      user.days?.toString() ?? '—',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        // Dim color when streak is unknown (still loading
                        // or timed out) — visually distinct from a real 0.
                        color: user.days == null
                            ? Colors.white.withValues(alpha: 0.55)
                            : Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          user.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: ZveltTokens.text,
          ),
        ),
      ],
    );
  }
}

class _RecentUserRow extends StatelessWidget {
  const _RecentUserRow({
    required this.user,
    required this.isLast,
    required this.opening,
    required this.onChat,
  });
  final _RecentUser user;
  final bool isLast;
  final bool opening;
  final VoidCallback? onChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: ZveltTokens.border)),
      ),
      child: Row(
        children: [
          _CircleAvatar(name: user.name, hue: user.hue, size: 42, online: user.online),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: ZveltTokens.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  user.sub,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: ZveltTokens.text2,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SmallCircleBtn(
            onTap: onChat,
            child: opening
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: ZveltTokens.text2,
                    ),
                  )
                : Icon(AppIcons.comment_alt,
                    color: ZveltTokens.text2, size: 14),
          ),
        ],
      ),
    );
  }
}

class _SmallCircleBtn extends StatelessWidget {
  const _SmallCircleBtn({
    required this.onTap,
    required this.child,
  });

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ZveltTokens.surface2,
          border: Border.all(color: ZveltTokens.border),
        ),
        child: child,
      ),
    );
  }
}
