import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';
import 'dart:collection';

import 'package:flutter/material.dart';
import '../../theme/zvelt_tokens.dart';
import '../../services/_crash_reporter.dart';
import '../../services/friends_service.dart';
import '../../services/messages_service.dart';
import '../../services/moderation_service.dart';
import '../../services/social_notification_hub.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';
import 'direct_chat_screen.dart';

/// Prieteni: listă, căutare după username, cereri primite / trimise.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  final _service = FriendsService();
  final _messages = MessagesService();
  late TabController _tabs;

  List<FriendSummary> _friends = [];
  List<FriendRequestRow> _incoming = [];
  List<FriendRequestRow> _outgoing = [];
  bool _loading = true;
  String? _error;

  final _searchCtrl = TextEditingController();
  List<FriendSummary> _searchResults = [];
  bool _searching = false;
  bool _searchPending = false; // debounce in flight (waiting to fire)
  String? _searchError;
  String _lastQueryShown = '';
  bool _searchTipShown = false;

  // Wave 19 — PII enumeration hardening.
  // Min 3 chars + 350ms debounce + 1 req/sec hard rate limit + suspicious-pattern detection.
  static const int _minSearchChars = 3;
  static const Duration _searchDebounceDelay = Duration(milliseconds: 350);
  static const Duration _searchMinInterval = Duration(milliseconds: 1000);
  static const int _suspiciousQueryThreshold = 20;
  static const Duration _suspiciousWindow = Duration(seconds: 60);

  Timer? _searchDebounce;
  DateTime? _lastSearchAt;
  final Queue<DateTime> _recentSearches = Queue<DateTime>();
  bool _suspiciousReported = false;

  // Wave 22 P1.5 — generation counter to discard stale search responses.
  // Without this, typing "abcd" then "abc" can race: the slower "abcd"
  // response can land *after* "abc"'s and overwrite results, showing the
  // user matches for a query they're no longer typing.
  int _searchGen = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _searchCtrl.addListener(_onSearchChanged);
    _reload();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabs.dispose();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final f = await _service.listFriends();
      final inc = await _service.incomingRequests();
      final out = await _service.outgoingRequests();
      if (!mounted) return;
      setState(() {
        _friends = f;
        _incoming = inc;
        _outgoing = out;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    _searchDebounce?.cancel();
    if (q.length < _minSearchChars) {
      // Below gate — clear pending state, hide results without firing HTTP.
      if (_searchResults.isNotEmpty || _searchPending || _searchError != null) {
        setState(() {
          _searchResults = [];
          _searchPending = false;
          _searchError = null;
        });
      }
      return;
    }
    setState(() {
      _searchPending = true;
      _searchError = null;
    });
    _searchDebounce = Timer(_searchDebounceDelay, _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.length < _minSearchChars) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _searchPending = false;
        });
      }
      return;
    }

    // Hard rate limit: max 1 req/sec. Defer instead of dropping to keep latest query.
    final now = DateTime.now();
    final last = _lastSearchAt;
    if (last != null) {
      final since = now.difference(last);
      if (since < _searchMinInterval) {
        final wait = _searchMinInterval - since;
        _searchDebounce?.cancel();
        _searchDebounce = Timer(wait, _runSearch);
        return;
      }
    }
    _lastSearchAt = now;

    // Suspicious-pattern detection — sliding 60s window over recent searches.
    _recentSearches.addLast(now);
    while (_recentSearches.isNotEmpty &&
        now.difference(_recentSearches.first) > _suspiciousWindow) {
      _recentSearches.removeFirst();
    }
    if (_recentSearches.length > _suspiciousQueryThreshold && !_suspiciousReported) {
      _suspiciousReported = true;
      reportError(
        StateError('friends search rate ${_recentSearches.length}/60s'),
        StackTrace.current,
        reason: 'friends:search-suspicious-pattern',
      );
    }

    if (!mounted) return;
    // Wave 22 P1.5 — bump generation; any in-flight prior search will be
    // ignored when it returns because its captured myGen != _searchGen.
    final myGen = ++_searchGen;
    setState(() {
      _searching = true;
      _searchPending = false;
      _searchError = null;
      _lastQueryShown = q;
    });
    try {
      final r = await _service.searchByUsername(q);
      if (!mounted || myGen != _searchGen) return; // stale response, discard
      setState(() {
        _searchResults = r;
        _searching = false;
      });
      if (!_searchTipShown && r.isNotEmpty) {
        _searchTipShown = true;
        _snack('Tip — search by exact username for best results.');
      }
    } catch (e, st) {
      reportError(e, st, reason: 'friends:search');
      if (!mounted || myGen != _searchGen) return; // stale failure, discard
      setState(() {
        _searching = false;
        _searchError = 'Search failed. Try again.';
      });
    }
  }

  String _emptyStateCopy() {
    final q = _searchCtrl.text.trim();
    if (q.length < _minSearchChars) return 'Type at least 3 characters to search.';
    if (_searchPending) return 'Waiting…';
    if (_searching) return 'Searching…';
    if (_searchError != null) return _searchError!;
    final shown = _lastQueryShown.isEmpty ? q : _lastQueryShown;
    return "No athletes found for '$shown'. Try fewer characters.";
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addFriend(FriendSummary u) async {
    try {
      final res = await _service.sendRequest(u.userId);
      final status = res['status'] as String?;
      if (!mounted) return;
      _snack(status == 'accepted' ? 'You are now friends' : 'Friend request sent');
      await _reload();
      SocialNotificationHub.refresh();
      setState(() {
        _searchResults = _searchResults.where((x) => x.userId != u.userId).toList();
      });
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _accept(FriendRequestRow r) async {
    try {
      await _service.acceptRequest(r.userId);
      if (!mounted) return;
      _snack('Friend added');
      await _reload();
      SocialNotificationHub.refresh();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _openDm(FriendSummary u) async {
    try {
      final opened = await _messages.openConversation(u.userId);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DirectChatScreen(
            conversationId: opened.conversationId,
            peer: opened.peer,
          ),
        ),
      );
      SocialNotificationHub.refresh();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _blockFriend(FriendSummary u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: Text('Block this user?', style: TextStyle(color: ZveltTokens.text)),
        content: Text(
          "You won't see ${u.label}'s posts, comments, or messages. They will also be removed from your friends list.",
          style: TextStyle(color: ZveltTokens.text2),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Block')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ModerationService().blockUser(u.userId);
      // Best-effort auto-unfriend — server should also do this; client mirrors.
      try {
        await _service.removeOrCancel(u.userId);
      } catch (e, st) {
        reportError(e, st, reason: 'friends:auto-unfriend-on-block');
      }
      if (!mounted) return;
      _snack('${u.label} blocked');
      setState(() {
        _friends = _friends.where((f) => f.userId != u.userId).toList();
      });
    } on ModerationException catch (e, st) {
      if (e.isNotDeployed) {
        if (!mounted) return;
        _snack('${u.label} blocked locally');
        setState(() {
          _friends = _friends.where((f) => f.userId != u.userId).toList();
        });
        return;
      }
      reportError(e, st, reason: 'friends:block');
      if (!mounted) return;
      _snack(e.isNetworkError ? 'Network error' : "Couldn't block");
    } catch (e, st) {
      reportError(e, st, reason: 'friends:block');
      if (!mounted) return;
      _snack("Couldn't block");
    }
  }

  Future<void> _removeFriend(FriendSummary u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: Text('Remove friend?', style: TextStyle(color: ZveltTokens.text)),
        content: Text(
          'Remove ${u.label} from your friends?',
          style: TextStyle(color: ZveltTokens.text2),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.removeOrCancel(u.userId);
      if (!mounted) return;
      _snack('Removed');
      await _reload();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _cancelOutgoing(FriendRequestRow r) async {
    try {
      await _service.removeOrCancel(r.userId);
      if (!mounted) return;
      _snack('Request cancelled');
      await _reload();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Decline an incoming request. Same endpoint as the outgoing cancel —
  /// before this, the only escape from an unwanted request was accepting
  /// the person or hunting them down to block them.
  Future<void> _decline(FriendRequestRow r) async {
    try {
      await _service.removeOrCancel(r.userId);
      if (!mounted) return;
      _snack('Request declined');
      await _reload();
      SocialNotificationHub.refresh();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  bool _isFriend(String userId) => _friends.any((f) => f.userId == userId);
  bool _isOutgoing(String userId) => _outgoing.any((o) => o.userId == userId);
  bool _isIncoming(String userId) => _incoming.any((i) => i.userId == userId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        title: const Text('Friends'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: ZveltTokens.brand,
          labelColor: ZveltTokens.brand,
          unselectedLabelColor: ZveltTokens.text2,
          tabs: [
            Tab(text: 'Friends (${_friends.length})'),
            const Tab(text: 'Find'),
            Tab(text: 'Requests${_incoming.isEmpty ? '' : ' (${_incoming.length})'}'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
          : _error != null
              ? ZveltErrorState(
                  tier: ZveltErrorTier.generic,
                  title: "Couldn't load friends",
                  onRetry: _reload,
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _friendsTab(),
                    _findTab(),
                    _requestsTab(),
                  ],
                ),
    );
  }

  Widget _friendsTab() {
    if (_friends.isEmpty) {
      return const ZveltEmptyState(
        icon: AppIcons.user_add,
        title: 'No friends yet',
        subtitle: 'Use Find to search for athletes by username.',
      );
    }
    return RefreshIndicator(
      color: ZveltTokens.brand,
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _friends.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final u = _friends[i];
          return GestureDetector(
            onLongPress: () => _blockFriend(u),
            child: _UserTile(
              key: ValueKey('friend-${u.userId}'),
              label: u.label,
              subtitle: u.username != null ? '@${u.username}' : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Message',
                    icon: const Icon(AppIcons.comment_alt, color: ZveltTokens.brand),
                    onPressed: () => _openDm(u),
                  ),
                  IconButton(
                    tooltip: 'Remove friend',
                    icon: Icon(AppIcons.delete_user, color: ZveltTokens.text2),
                    onPressed: () => _removeFriend(u),
                  ),
                  IconButton(
                    tooltip: 'Block',
                    icon: Icon(AppIcons.ban, color: ZveltTokens.text2),
                    onPressed: () => _blockFriend(u),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _findTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Type at least 3 characters',
                    prefixIcon: Icon(AppIcons.search, color: ZveltTokens.text2),
                  ),
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  onSubmitted: (_) {
                    _searchDebounce?.cancel();
                    _runSearch();
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _searching
                    ? null
                    : () {
                        _searchDebounce?.cancel();
                        _runSearch();
                      },
                child: _searching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.brand),
                      )
                    : const Text('Search'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Search matches the start of a username (min 3 characters). Set a username in Profile if you have not.',
            style: TextStyle(color: ZveltTokens.text2, fontSize: 12, height: 1.4),
          ),
        ),
        Expanded(
          child: _searchResults.isEmpty
              ? ZveltEmptyState(
                  compact: true,
                  icon: AppIcons.search,
                  title: 'No results',
                  subtitle: _emptyStateCopy(),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final u = _searchResults[i];
                    final friend = _isFriend(u.userId);
                    final out = _isOutgoing(u.userId);
                    final inc = _isIncoming(u.userId);
                    return Container(
                      key: ValueKey('friend-search-${u.userId}'),
                      decoration: BoxDecoration(
                        color: ZveltTokens.surface,
                        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                        boxShadow: ZveltTokens.shadowCard,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  u.label,
                                  style: TextStyle(
                                    color: ZveltTokens.text,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                if (u.username != null)
                                  Text(
                                    '@${u.username}',
                                    style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                          if (friend)
                            Text('Friends', style: TextStyle(color: ZveltTokens.text2, fontSize: 12))
                          else if (out)
                            const Text('Pending', style: TextStyle(color: ZveltTokens.brand, fontSize: 12))
                          else if (inc)
                            FilledButton(
                              onPressed: () => _accept(
                                FriendRequestRow(
                                  friendshipId: '',
                                  userId: u.userId,
                                  username: u.username,
                                  displayName: u.displayName,
                                  emailHint: u.emailHint,
                                  createdAt: '',
                                ),
                              ),
                              child: const Text('Accept'),
                            )
                          else
                            TextButton(
                              onPressed: () => _addFriend(u),
                              child: const Text('Add'),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _requestsTab() {
    return RefreshIndicator(
      color: ZveltTokens.brand,
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'Incoming',
            style: TextStyle(
              color: ZveltTokens.text2,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.06,
            ),
          ),
          const SizedBox(height: 8),
          if (_incoming.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text('No pending requests', style: TextStyle(color: ZveltTokens.text2, fontSize: 13)),
            )
          else
            ..._incoming.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: ZveltTokens.surface,
                    borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                    boxShadow: ZveltTokens.shadowCard,
                  ),
                  padding: const EdgeInsets.all(ZveltTokens.s3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.label,
                              style: TextStyle(
                                color: ZveltTokens.text,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            if (r.username != null)
                              Text(
                                '@${r.username}',
                                style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _decline(r),
                        style: TextButton.styleFrom(foregroundColor: ZveltTokens.text2),
                        child: const Text('Decline'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(onPressed: () => _accept(r), child: const Text('Accept')),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Sent',
            style: TextStyle(
              color: ZveltTokens.text2,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.06,
            ),
          ),
          const SizedBox(height: 8),
          if (_outgoing.isEmpty)
            Text('No outgoing requests', style: TextStyle(color: ZveltTokens.text2, fontSize: 13))
          else
            ..._outgoing.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: ZveltTokens.surface,
                    borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                    boxShadow: ZveltTokens.shadowCard,
                  ),
                  padding: const EdgeInsets.all(ZveltTokens.s3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.label,
                              style: TextStyle(
                                color: ZveltTokens.text,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            if (r.username != null)
                              Text(
                                '@${r.username}',
                                style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _cancelOutgoing(r),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({super.key, required this.label, this.subtitle, this.trailing});
  final String label;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: ZveltTokens.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle!, style: TextStyle(color: ZveltTokens.text2, fontSize: 12)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
