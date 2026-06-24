import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart' show v1Base, mediaAbsoluteUrl;
import '../../models/social_feed_post.dart';
import '../../services/_crash_reporter.dart';
import '../../services/auth_service.dart';
import '../../services/friends_service.dart';
import '../../services/messages_service.dart';
import '../../services/moderation_service.dart';
import '../../services/social_feed_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../utils/display_name.dart';
import '../../widgets/social_feed_post_card.dart';
import '../../widgets/zvelt_avatar.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';
import 'direct_chat_screen.dart';
import 'report_user_sheet.dart';

/// Public profile of another athlete. Tapping the avatar / name from a
/// feed post or comment row pushes this screen.
///
/// Loads `GET /v1/users/:userId` (basic identity + relationship pill) and
/// `GET /v1/users/:userId/posts?limit=20` (recent posts). Both endpoints
/// degrade gracefully: 404 → "User not found", 403 → private-profile copy.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.userId,
    this.displayName,
    this.username,
  });

  final String userId;
  final String? displayName;
  final String? username;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _auth = AuthService();
  final _friends = FriendsService();
  final _messages = MessagesService();
  final _moderation = ModerationService();
  final _feedService = SocialFeedService();

  _ProfileSummary? _summary;
  List<SocialFeedPost> _posts = [];
  bool _loadingProfile = true;
  bool _loadingPosts = true;
  bool _postsError = false;
  bool _isMe = false;
  bool _addingFriend = false;
  bool _openingChat = false;
  String? _profileError; // 'not_found' | 'private' | generic message

  @override
  void initState() {
    super.initState();
    _resolveSelf();
    _loadProfile();
    _loadPosts();
  }

  Future<void> _resolveSelf() async {
    final id = await _auth.getCurrentUserId();
    if (!mounted) return;
    setState(() => _isMe = id == widget.userId);
  }

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getAccessToken();
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loadingProfile = true;
      _profileError = null;
    });
    try {
      final res = await http
          .get(
            Uri.parse('$v1Base/users/${widget.userId}'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 45));
      if (!mounted) return;
      if (res.statusCode == 404) {
        setState(() {
          _loadingProfile = false;
          _profileError = 'not_found';
        });
        return;
      }
      if (res.statusCode == 403) {
        setState(() {
          _loadingProfile = false;
          _profileError = 'private';
        });
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        setState(() {
          _loadingProfile = false;
          _profileError = 'Could not load profile (${res.statusCode})';
        });
        return;
      }
      final body = jsonDecode(res.body);
      final raw = (body is Map<String, dynamic>)
          ? (body['data'] as Map<String, dynamic>? ?? body)
          : <String, dynamic>{};
      setState(() {
        _summary = _ProfileSummary.fromJson(raw, fallbackUserId: widget.userId);
        _loadingProfile = false;
      });
    } on SocketException catch (e, st) {
      reportError(e, st, reason: 'user-profile:load');
      if (mounted) {
        setState(() {
          _loadingProfile = false;
          _profileError = 'Network unavailable';
        });
      }
    } on TimeoutException catch (e, st) {
      reportError(e, st, reason: 'user-profile:load');
      if (mounted) {
        setState(() {
          _loadingProfile = false;
          _profileError = 'Request timed out';
        });
      }
    } catch (e, st) {
      reportError(e, st, reason: 'user-profile:load');
      if (mounted) {
        setState(() {
          _loadingProfile = false;
          _profileError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _loadPosts() async {
    setState(() => _loadingPosts = true);
    try {
      final res = await http
          .get(
            Uri.parse('$v1Base/users/${widget.userId}/posts?limit=20'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 45));
      if (!mounted) return;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // Don't masquerade a failure as 'No posts yet' — a friend whose
        // posts endpoint 500s is not someone who never posted.
        setState(() {
          _posts = [];
          _postsError = true;
          _loadingPosts = false;
        });
        return;
      }
      final body = jsonDecode(res.body);
      final list = (body is Map<String, dynamic>)
          ? (body['data'] as List<dynamic>? ?? const [])
          : (body is List ? body : const []);
      setState(() {
        _posts = list
            .map((p) => SocialFeedPost.fromJson(p as Map<String, dynamic>))
            .toList();
        _postsError = false;
        _loadingPosts = false;
      });
    } catch (e, st) {
      reportError(e, st, reason: 'user-profile:posts');
      if (mounted) {
        setState(() {
          _postsError = true;
          _loadingPosts = false;
        });
      }
    }
  }

  Future<void> _addFriend() async {
    if (_addingFriend) return;
    setState(() => _addingFriend = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _friends.sendRequest(widget.userId);
      if (!mounted) return;
      setState(() {
        _summary = _summary?.copyWith(relationship: 'pending');
      });
      messenger.showSnackBar(const SnackBar(content: Text('Friend request sent')));
    } catch (e, st) {
      reportError(e, st, reason: 'user-profile:add-friend');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _addingFriend = false);
    }
  }

  Future<void> _message() async {
    if (_openingChat) return;
    setState(() => _openingChat = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await _messages.openConversation(widget.userId);
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
      reportError(e, st, reason: 'user-profile:open-chat');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  Future<void> _confirmAndBlock() async {
    final messenger = ScaffoldMessenger.of(context);
    final label = _displayLabel;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: Text('Block this user?', style: TextStyle(color: ZveltTokens.text)),
        content: Text(
          "You won't see $label's posts, comments, or messages. You can unblock from Settings.",
          style: TextStyle(color: ZveltTokens.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text('Cancel', style: TextStyle(color: ZveltTokens.text2)),
          ),
          FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Block')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _moderation.blockUser(widget.userId);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$label blocked')));
      Navigator.of(context).pop();
    } on ModerationException catch (e, st) {
      if (e.isNotDeployed) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('$label blocked locally')));
        Navigator.of(context).pop();
        return;
      }
      reportError(e, st, reason: 'user-profile:block');
      messenger.showSnackBar(
        SnackBar(content: Text(e.isNetworkError ? 'Network error' : "Couldn't block — try again")),
      );
    } catch (e, st) {
      reportError(e, st, reason: 'user-profile:block');
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't block — try again")));
    }
  }

  String get _displayLabel => resolveDisplayName(
        displayName: _summary?.displayName ?? widget.displayName,
        username: _summary?.username ?? widget.username,
        userId: widget.userId,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        title: Text(_displayLabel),
        actions: [
          if (!_isMe && _profileError == null)
            PopupMenuButton<String>(
              icon: const Icon(AppIcons.menu_dots_vertical),
              tooltip: 'More options',
              color: ZveltTokens.surface,
              onSelected: (v) {
                if (v == 'block') _confirmAndBlock();
                if (v == 'report') {
                  ReportUserSheet.show(
                    context,
                    userId: widget.userId,
                    username: _summary?.username ?? widget.username,
                    displayName: _summary?.displayName ?? widget.displayName,
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'report',
                  child: Text('Report user', style: TextStyle(color: ZveltTokens.text)),
                ),
                const PopupMenuItem(
                  value: 'block',
                  child: Text('Block user', style: TextStyle(color: ZveltTokens.error)),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingProfile) {
      return const Center(child: CircularProgressIndicator(color: ZveltTokens.brand));
    }
    if (_profileError == 'not_found') {
      return const ZveltEmptyState(
        icon: AppIcons.delete_user,
        title: 'User not found',
        subtitle: 'This account may have been deleted.',
      );
    }
    if (_profileError == 'private') {
      return ZveltEmptyState(
        icon: AppIcons.lock,
        title: 'This profile is private',
        subtitle: "Send a friend request to see $_displayLabel's posts.",
        action: _isMe
            ? null
            : FilledButton(
                onPressed: _addingFriend ? null : _addFriend,
                child: Text(_addingFriend ? 'Sending…' : 'Add friend'),
              ),
      );
    }
    if (_profileError != null) {
      final tier = _profileError == 'Network unavailable' ||
              _profileError == 'Request timed out'
          ? ZveltErrorTier.network
          : ZveltErrorTier.generic;
      return ZveltErrorState(
        tier: tier,
        title: 'Could not load profile',
        message: _profileError,
        onRetry: _loadProfile,
      );
    }

    return RefreshIndicator(
      color: ZveltTokens.brand,
      onRefresh: () async {
        await Future.wait([_loadProfile(), _loadPosts()]);
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _buildHeader(),
          const SizedBox(height: ZveltTokens.s4),
          _buildActionsRow(),
          _buildStatsCard(),
          const SizedBox(height: ZveltTokens.s2),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Posts',
              style: TextStyle(
                color: ZveltTokens.text, fontSize: 15, fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_loadingPosts)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: ZveltTokens.brand)),
            )
          else if (_postsError && _posts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Center(
                child: Column(
                  children: [
                    Text("Couldn't load posts",
                        style: TextStyle(color: ZveltTokens.text2, fontSize: 13)),
                    TextButton(
                      onPressed: _loadPosts,
                      child: const Text('Retry',
                          style: TextStyle(
                              color: ZveltTokens.brand,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            )
          else if (_posts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: ZveltEmptyState(
                compact: true,
                icon: AppIcons.camera,
                title: 'No posts yet',
              ),
            )
          else
            ..._posts.map(
              (p) => SocialFeedPostCard(
                key: ValueKey(p.id),
                post: p,
                service: _feedService,
                onLike: () {},
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final avatar = _summary?.avatarUrl;
    final bio = _summary?.bio;
    final username = (_summary?.username ?? '').trim();
    final tier = (_summary?.tier ?? '').trim();
    final sub = <String>[
      if (username.isNotEmpty) '@$username',
      if (tier.isNotEmpty) tier,
    ].join(' · ');
    return Padding(
      // Centered hero, matching the design.
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ZveltAvatar(
            size: AvatarSize.xl,
            imageUrl: (avatar != null && avatar.isNotEmpty) ? mediaAbsoluteUrl(avatar) : null,
            displayName: _summary?.displayName ?? widget.displayName,
            username: _summary?.username ?? widget.username,
            userId: widget.userId,
          ),
          const SizedBox(height: ZveltTokens.s4),
          Text(
            _summary?.displayName?.isNotEmpty == true ? _summary!.displayName! : _displayLabel,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ZveltTokens.text,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: TextStyle(color: ZveltTokens.text3, fontSize: 12),
            ),
          ],
          if (bio != null && bio.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              bio,
              textAlign: TextAlign.center,
              style: TextStyle(color: ZveltTokens.text, fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  /// Stats card (Sessions · PRs · Streak). null = the backend didn't send a
  /// stats block — render '—', NOT 0: a veteran with 300 sessions must not
  /// look like a brand-new account (fabricated-data principle).
  Widget _buildStatsCard() {
    final s = _summary;
    final stats = <(String, String)>[
      ('Sessions', s?.sessions?.toString() ?? '—'),
      ('PRs', s?.prs?.toString() ?? '—'),
      ('Streak', s?.streak?.toString() ?? '—'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(ZveltTokens.s4),
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          boxShadow: ZveltTokens.shadowCard,
        ),
        child: Row(
          children: [
            for (final (label, value) in stats)
              Expanded(
                child: Column(
                  children: [
                    Text(
                      value,
                      style: TextStyle(color: ZveltTokens.text, fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontMono,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                        color: ZveltTokens.text3,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsRow() {
    if (_isMe) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            boxShadow: ZveltTokens.shadowCard,
          ),
          child: Text(
            "This is you. Edit profile from Settings.",
            style: TextStyle(color: ZveltTokens.text2, fontSize: 13),
          ),
        ),
      );
    }
    final rel = _summary?.relationship;
    final isFriend = rel == 'friend' || rel == 'accepted';
    final isPending = rel == 'pending' || rel == 'outgoing';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: isFriend
                  ? 'You are friends'
                  : (isPending ? 'Friend request pending' : 'Add friend'),
              child: FilledButton.icon(
                onPressed: (isFriend || isPending || _addingFriend) ? null : _addFriend,
                icon: Icon(
                  isFriend
                      ? AppIcons.check
                      : (isPending ? AppIcons.clock : AppIcons.user_add),
                  size: 18,
                ),
                label: Text(
                  isFriend
                      ? 'Friends'
                      : (isPending ? 'Pending' : (_addingFriend ? 'Sending...' : 'Add friend')),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Send message',
              child: OutlinedButton.icon(
                onPressed: _openingChat ? null : _message,
                icon: const Icon(AppIcons.comment_alt, size: 18),
                label: Text(_openingChat ? 'Opening...' : 'Message'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSummary {
  const _ProfileSummary({
    required this.userId,
    this.displayName,
    this.username,
    this.bio,
    this.avatarUrl,
    this.relationship,
    this.recentPostsCount,
    this.tier,
    this.sessions,
    this.prs,
    this.streak,
  });

  final String userId;
  final String? displayName;
  final String? username;
  final String? bio;
  final String? avatarUrl;
  /// 'self' | 'friend' | 'pending' | 'blocked' | 'none' | etc.
  final String? relationship;
  final int? recentPostsCount;
  // ── Stats — parsed if the backend sends them; null until then so the UI
  //    shows honest zeros for a brand-new account (no fabricated numbers).
  final String? tier;
  final int? sessions;
  final int? prs;
  final int? streak;

  factory _ProfileSummary.fromJson(Map<String, dynamic> j, {required String fallbackUserId}) {
    final profile = j['profile'] as Map<String, dynamic>? ?? j;
    final stats = j['stats'] as Map<String, dynamic>? ?? const {};
    int? asInt(dynamic v) => v is num ? v.toInt() : null;
    String? rel = j['relationship'] as String?;
    if (rel == null) {
      if (j['isFriend'] == true) {
        rel = 'friend';
      } else if (j['hasOutgoingRequest'] == true || j['isPending'] == true) {
        rel = 'pending';
      } else if (j['isBlocked'] == true) {
        rel = 'blocked';
      }
    }
    return _ProfileSummary(
      userId: j['id'] as String? ?? j['userId'] as String? ?? fallbackUserId,
      displayName: (profile['displayName'] as String?)?.trim(),
      username: (profile['username'] as String?)?.trim(),
      bio: (profile['bio'] as String?)?.trim(),
      avatarUrl: (profile['avatarUrl'] as String?) ?? (j['avatarUrl'] as String?),
      relationship: rel,
      recentPostsCount: j['recentPostsCount'] as int?,
      tier: (profile['tier'] as String?) ?? (j['tier'] as String?),
      sessions: asInt(stats['sessions'] ?? stats['totalWorkouts'] ?? j['totalWorkouts']),
      prs: asInt(stats['prs'] ?? j['prs']),
      streak: asInt(stats['streak'] ?? stats['currentStreak'] ?? j['currentStreak']),
    );
  }

  _ProfileSummary copyWith({String? relationship}) {
    return _ProfileSummary(
      userId: userId,
      displayName: displayName,
      username: username,
      bio: bio,
      avatarUrl: avatarUrl,
      relationship: relationship ?? this.relationship,
      recentPostsCount: recentPostsCount,
      tier: tier,
      sessions: sessions,
      prs: prs,
      streak: streak,
    );
  }
}


