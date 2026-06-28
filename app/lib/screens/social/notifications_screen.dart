import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../services/_crash_reporter.dart';
import '../../services/notifications_service.dart';
import '../../services/social_notification_hub.dart';
import '../../services/messages_service.dart';
import '../../utils/relative_time.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';
import '../../widgets/zvelt_tertiary_button.dart';
import 'challenge_detail_screen.dart';
import 'direct_chat_screen.dart';
import 'friends_screen.dart';
import 'post_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const int _pageLimit = 40;

  final _svc = NotificationsService();
  final ScrollController _scrollCtrl = ScrollController();
  List<AppNotification> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return;
    final ratio = _scrollCtrl.position.pixels / max;
    if (ratio >= 0.8) _loadMore();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _hasMore = true;
      _items = [];
    });
    try {
      final page = await _svc.listPage(page: 1, limit: _pageLimit);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _hasMore = page.hasMore;
        _loading = false;
      });
      await SocialNotificationHub.refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final page = await _svc.listPage(page: next, limit: _pageLimit);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _page = next;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e, st) {
      reportError(e, st, reason: 'notifications:load-more');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _markAll() async {
    // Wave 22 P1.6 — surface real failure when the backend can't mark all
    // read. Previously the call would silently throw and the UI would
    // re-fetch, masking server-state drift behind a successful-looking flow.
    try {
      await _svc.markAllRead();
      if (!mounted) return;
      await _load();
    } on NotificationsException catch (e, st) {
      reportError(e, st, reason: 'notifications:mark-all-read');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't mark all read — try again"),
        ),
      );
      // Intentionally do NOT re-fetch — keep UI as-is so the user can retry
      // without flicker.
    } catch (e, st) {
      reportError(e, st, reason: 'notifications:mark-all-read');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't mark all read — try again"),
        ),
      );
    }
  }

  String _titleLine(AppNotification n) {
    switch (n.type) {
      case 'friend_request':
        return '${n.actorLabel} sent you a friend request';
      case 'friend_accepted':
        return '${n.actorLabel} accepted your friend request';
      case 'post_like':
        return '${n.actorLabel} liked your post';
      case 'post_comment':
        return '${n.actorLabel} commented on your post';
      case 'dm_message':
        return '${n.actorLabel} sent you a message';
      case 'challenge_invite':
        return '${n.actorLabel} invited you to a challenge';
      case 'streak_risk':
        return 'Your streak is at risk';
      case 'challenge_ending_soon':
        return 'A challenge ends soon';
      case 'challenge_ended':
        final won = n.payload['youWon'] == true;
        return won ? 'You won a challenge! 🏆' : 'A challenge just ended';
      default:
        return 'Notification';
    }
  }

  String? _subtitle(AppNotification n) {
    if (n.type == 'post_comment' || n.type == 'dm_message') {
      final p = n.payload['bodyPreview'] as String?;
      if (p != null && p.isNotEmpty) return p;
    }
    if (n.type == 'challenge_invite') {
      final t = n.payload['title'] as String?;
      if (t != null && t.trim().isNotEmpty) return t.trim();
    }
    if (n.type == 'streak_risk') {
      return 'Post a workout today to keep it going';
    }
    if (n.type == 'challenge_ending_soon') {
      final t = n.payload['title'] as String?;
      return (t != null && t.trim().isNotEmpty) ? '${t.trim()} — sprint to the finish' : 'Less than 24h left';
    }
    if (n.type == 'challenge_ended') {
      final title = (n.payload['title'] as String?)?.trim();
      final winner = (n.payload['winnerName'] as String?)?.trim();
      final rank = n.payload['myRank'];
      if (n.payload['youWon'] == true) return title != null && title.isNotEmpty ? '$title — you finished #1' : 'You finished #1';
      if (winner != null && winner.isNotEmpty) return 'Winner: $winner${rank is num ? ' · you placed #${rank.toInt()}' : ''}';
      return title;
    }
    return null;
  }

  Future<void> _onTap(AppNotification n) async {
    if (n.isUnread) {
      // Mark read in place — the old full `_load()` at the end of this
      // method threw away pagination and scroll position on every tap.
      try {
        await _svc.markRead(n.id);
      } catch (_) {/* low-stakes; server catches up on next sync */}
      if (mounted) {
        setState(() {
          final i = _items.indexWhere((e) => e.id == n.id);
          if (i != -1) _items[i] = _items[i].asRead();
        });
      }
    }
    if (!mounted) return;

    switch (n.type) {
      case 'friend_request':
      case 'friend_accepted':
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const FriendsScreen()),
        );
        break;
      case 'post_like':
      case 'post_comment':
        final postId = n.payload['postId'] as String?;
        if (postId != null && postId.isNotEmpty) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
          );
        }
        break;
      case 'dm_message':
        final cid = n.payload['conversationId'] as String?;
        if (cid != null && cid.isNotEmpty && n.actorId != null) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => DirectChatScreen(
                conversationId: cid,
                peer: DmPeer(
                  userId: n.actorId!,
                  username: n.actorUsername,
                  displayName: n.actorDisplayName,
                ),
              ),
            ),
          );
        }
        break;
      case 'challenge_invite':
        final challengeId = n.payload['challengeId'] as String?;
        if (challengeId != null && challengeId.isNotEmpty) {
          final endsRaw = n.payload['endsAt'] as String?;
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => ChallengeDetailScreen(
                challengeId: challengeId,
                title: n.payload['title'] as String?,
                scoringType: n.payload['scoringType'] as String?,
                endsAt: endsRaw != null ? DateTime.tryParse(endsRaw) : null,
                showAcceptDecline: true,
              ),
            ),
          );
        }
        break;
      case 'challenge_ending_soon':
      case 'challenge_ended':
        final challengeId = n.payload['challengeId'] as String?;
        if (challengeId != null && challengeId.isNotEmpty) {
          final endsRaw = n.payload['endsAt'] as String?;
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => ChallengeDetailScreen(
                challengeId: challengeId,
                title: n.payload['title'] as String?,
                scoringType: n.payload['scoringType'] as String?,
                endsAt: endsRaw != null ? DateTime.tryParse(endsRaw) : null,
              ),
            ),
          );
        }
        break;
      case 'streak_risk':
        // No deep target — the user just needs to log/post today. Marking read
        // (handled above) is enough; tapping dismisses.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final hasUnread = _items.any((e) => e.isUnread);
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Custom header ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(AppIcons.angle_small_left, size: 18),
                    color: ZveltTokens.text2,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'ACTIVITY',
                        style: TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: ZveltTokens.text,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ),
                  ),
                  if (hasUnread)
                    // Tertiary CTA — low emphasis bulk action.
                    ZveltTertiaryButton(
                      label: 'MARK READ',
                      dense: true,
                      color: ZveltTokens.brand3,
                      onTap: _markAll,
                    )
                  else
                    const SizedBox(width: 72),
                ],
              ),
            ),
            // ── Body ────────────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
                  : _error != null
                      ? ZveltErrorState(
                          tier: ZveltErrorTier.generic,
                          title: "Couldn't load notifications",
                          onRetry: _load,
                        )
                      : RefreshIndicator(
                          color: ZveltTokens.brand,
                          onRefresh: _load,
                          child: ListView(
                            controller: _scrollCtrl,
                            padding: EdgeInsets.fromLTRB(16, 12, 16, mq.padding.bottom + 32),
                            children: [
                              // TODO(v1.1): show real friend suggestions from /v1/friends/suggestions if backend ships.
                              // Neutral label — 'EARLIER TODAY' claimed
                              // recency for week-old items (each card shows
                              // its own real timestamp anyway), and rendered
                              // above the empty state labeling nothing.
                              if (_items.isNotEmpty) ...[
                                _buildSectionLabel('RECENT'),
                                const SizedBox(height: 10),
                              ],
                              if (_items.isEmpty)
                                const ZveltEmptyState(
                                  compact: true,
                                  icon: AppIcons.bell,
                                  title: 'No notifications yet',
                                  subtitle: 'Your activity will appear here.',
                                )
                              else
                                ..._items.map((n) => Padding(
                                      key: ValueKey('notif-${n.id}'),
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _NotifCard(
                                        n: n,
                                        title: _titleLine(n),
                                        subtitle: _subtitle(n),
                                        timeAgo: safeRelativeTime(n.createdAt),
                                        onTap: () => _onTap(n),
                                      ),
                                    )),
                              const SizedBox(height: 12),
                              if (_loadingMore)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: ZveltTokens.brand,
                                        strokeWidth: 2.4,
                                      ),
                                    ),
                                  ),
                                )
                              else if (!_hasMore && _items.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: Text(
                                      'No more notifications',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: ZveltTokens.text2,
                                        letterSpacing: 1.4,
                                      ),
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
    );
  }

  Widget _buildSectionLabel(String label) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: ZveltTokens.text2,
            letterSpacing: 2.2,
          ),
        ),
      ],
    );
  }
}

// ── helper widgets ─────────────────────────────────────────────────────────────

class _NotifCard extends StatelessWidget {
  const _NotifCard({
    required this.n,
    required this.title,
    required this.subtitle,
    required this.timeAgo,
    required this.onTap,
  });

  final AppNotification n;
  final String title;
  final String? subtitle;
  final String timeAgo;
  final VoidCallback onTap;

  IconData get _icon {
    switch (n.type) {
      case 'friend_request':
      case 'friend_accepted':
        return AppIcons.user_add;
      case 'post_like':
        return AppIcons.heart;
      case 'post_comment':
        return AppIcons.comment_alt;
      case 'dm_message':
        return AppIcons.envelope;
      case 'challenge_invite':
      case 'challenge_ended':
        return AppIcons.trophy;
      case 'challenge_ending_soon':
        return AppIcons.clock;
      case 'streak_risk':
        return AppIcons.flame;
      default:
        return AppIcons.bell;
    }
  }

  Color get _iconColor {
    switch (n.type) {
      case 'post_like':
        return const Color(0xFFEC4899);
      case 'friend_request':
      case 'friend_accepted':
        return ZveltTokens.success;
      case 'dm_message':
        return ZveltTokens.info;
      default:
        return ZveltTokens.brand;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(ZveltTokens.s4),
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          border: Border.all(
            color: n.isUnread
                ? ZveltTokens.brand.withValues(alpha: 0.25)
                : ZveltTokens.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (n.isUnread)
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 6, right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZveltTokens.brand,
                  boxShadow: [
                    BoxShadow(
                        color: ZveltTokens.brand.withValues(alpha: 0.6),
                        blurRadius: 6),
                  ],
                ),
              )
            else
              const SizedBox(width: 13),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(ZveltTokens.rSm),
              ),
              child: Icon(_icon, color: _iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ZveltTokens.text,
                      fontSize: 13,
                      fontWeight: n.isUnread ? FontWeight.w700 : FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ZveltTokens.text2,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  // safeRelativeTime already returns 'ago'-suffixed strings
                  // ('2h ago') or absolute forms ('Mar 14') — appending a
                  // second ' ago' here produced '2h ago ago' on every card.
                  timeAgo,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: ZveltTokens.text3,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
