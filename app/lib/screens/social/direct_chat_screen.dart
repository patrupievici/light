import 'package:chat_bubbles/chat_bubbles.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import '../../theme/zvelt_tokens.dart';
import '../../services/_crash_reporter.dart';
import '../../services/auth_service.dart';
import '../../services/feed_refresh_notifier.dart';
import '../../services/messages_service.dart';
import '../../services/moderation_service.dart';
import '../../services/social_notification_hub.dart';
import '../../utils/relative_time.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';
import 'report_user_sheet.dart';

/// Thread DM cu bule [BubbleNormal] (pachet MIT `chat_bubbles`).
class DirectChatScreen extends StatefulWidget {
  const DirectChatScreen({
    super.key,
    required this.conversationId,
    required this.peer,
  });

  final String conversationId;
  final DmPeer peer;

  /// Conversation currently on screen (topmost DirectChatScreen), or null.
  /// PushMessagingService checks this before navigating so tapping a DM
  /// banner for the chat you're already reading doesn't stack a duplicate
  /// screen (the in-screen refresh listener already shows the new message).
  static String? activeConversationId;

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  final _svc = MessagesService();
  final _auth = AuthService();
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<DmMessage> _msgs = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _myId;

  // Wave 19a-3 — DM pagination. Older messages are loaded in batches of
  // [_pageLimit] via a "Load earlier" header tile at the top of the list.
  static const int _pageLimit = 80;
  bool _loadingEarlier = false;
  bool _hasMoreEarlier = false;
  String? _oldestCursor;

  // Debounce window for FCM-driven refreshes — multiple pushes in quick
  // succession only trigger a single _load().
  static const _pushRefreshThrottle = Duration(seconds: 2);
  DateTime? _lastPushRefresh;
  late final ValueNotifier<int> _dmRefreshNotifier;
  late final VoidCallback _dmRefreshListener;

  @override
  void initState() {
    super.initState();
    DirectChatScreen.activeConversationId = widget.conversationId;
    _dmRefreshNotifier =
        FeedRefreshNotifier.instance.notifier(RefreshScope.dm);
    _dmRefreshListener = _onDmPushBump;
    _dmRefreshNotifier.addListener(_dmRefreshListener);
    _bootstrap();
  }

  @override
  void dispose() {
    // Only clear if WE are still the registered conversation — a second
    // chat pushed on top has already overwritten it with its own id.
    if (DirectChatScreen.activeConversationId == widget.conversationId) {
      DirectChatScreen.activeConversationId = null;
    }
    _dmRefreshNotifier.removeListener(_dmRefreshListener);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Called when [RefreshScope.dm] is bumped (FCM push, etc.). Throttled
  /// to at most one refresh per [_pushRefreshThrottle]. Only updates the
  /// message list — the composer's text input is left untouched.
  void _onDmPushBump() {
    if (!mounted) return;
    final now = DateTime.now();
    final last = _lastPushRefresh;
    if (last != null && now.difference(last) < _pushRefreshThrottle) return;
    _lastPushRefresh = now;
    try {
      // Silent refresh — don't flip the spinner, just refetch.
      _silentReload();
    } catch (e, st) {
      reportError(e, st, reason: 'dm-chat:push-refresh');
    }
  }

  Future<void> _silentReload() async {
    try {
      final page = await _svc.listMessagesPage(
        widget.conversationId,
        limit: _pageLimit,
      );
      if (!mounted) return;
      final list = page.items;
      // Cheap identity check: only rebuild if the count or last id changed.
      final changed = list.length != _msgs.length ||
          (list.isNotEmpty &&
              _msgs.isNotEmpty &&
              list.last.id != _msgs.last.id);
      if (!changed) return;
      setState(() {
        _msgs = list;
        // Re-anchor pagination state — a silent reload always replaces the
        // currently-visible window with the freshest page.
        _oldestCursor = page.nextCursor ?? (list.isNotEmpty ? list.first.id : null);
        _hasMoreEarlier = page.nextCursor != null || list.length >= _pageLimit;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    } catch (e, st) {
      reportError(e, st, reason: 'dm-chat:silent-reload');
    }
  }

  Future<void> _bootstrap() async {
    _myId = await _auth.getCurrentUserId();
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _svc.listMessagesPage(
        widget.conversationId,
        limit: _pageLimit,
      );
      if (!mounted) return;
      setState(() {
        _msgs = page.items;
        _loading = false;
        // If the server gave us an explicit cursor, trust it. Otherwise, fall
        // back to "there might be more if we got a full page".
        _oldestCursor = page.nextCursor ??
            (page.items.isNotEmpty ? page.items.first.id : null);
        _hasMoreEarlier =
            page.nextCursor != null || page.items.length >= _pageLimit;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// Fetches the next page of *older* messages and prepends them to [_msgs],
  /// preserving the user's current scroll position so the message they were
  /// looking at stays in the same place on-screen.
  Future<void> _loadEarlier() async {
    if (_loadingEarlier || !_hasMoreEarlier) return;
    final cursor = _oldestCursor;
    if (cursor == null) return;
    setState(() => _loadingEarlier = true);
    // Snapshot scroll geometry BEFORE the prepend so we can re-anchor after
    // the new tiles are laid out.
    final beforeExtent = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final beforeOffset = _scroll.hasClients ? _scroll.offset : 0.0;
    try {
      final page = await _svc.listMessagesPage(
        widget.conversationId,
        limit: _pageLimit,
        before: cursor,
      );
      if (!mounted) return;
      final older = page.items;
      setState(() {
        if (older.isNotEmpty) {
          _msgs.insertAll(0, older);
          _oldestCursor = page.nextCursor ?? older.first.id;
        }
        // If the server returned an explicit null cursor, or sent fewer than
        // a full page, assume we've hit the start of history.
        if (page.nextCursor == null && older.length < _pageLimit) {
          _hasMoreEarlier = false;
        }
        _loadingEarlier = false;
      });
      // Preserve visible message: after the new items render, the max scroll
      // extent grew by (newExtent - beforeExtent); add that delta to the
      // previous offset so the user's anchor stays in the same place.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final newExtent = _scroll.position.maxScrollExtent;
        final delta = newExtent - beforeExtent;
        if (delta > 0) {
          _scroll.jumpTo((beforeOffset + delta).clamp(0.0, newExtent));
        }
      });
    } catch (e, st) {
      reportError(e, st, reason: 'dm:load-earlier');
      if (!mounted) return;
      setState(() {
        _loadingEarlier = false;
        // Keep _hasMoreEarlier = true so the tile stays visible for retry.
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't load earlier messages — tap to retry"),
          action: SnackBarAction(label: 'Retry', onPressed: _loadEarlier),
        ),
      );
    }
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  /// Send the composer's current text. The input is NOT cleared until the
  /// server confirms — on failure (network drop, 500, timeout) the user's
  /// text stays in the box and a SnackBar with a Retry action is shown.
  /// Guard via [_sending] prevents double-send on rapid Enter taps.
  Future<void> _send() async {
    // Wave 22 P0.3 — explicit guard at the top mirrors the canonical
    // double-tap defense shared with SocialCommentsSheet._send() and
    // PostDetailScreen._sendComment().
    if (_sending) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final m = await _svc.sendMessage(widget.conversationId, text);
      if (!mounted) return;
      setState(() {
        _msgs = [..._msgs, m];
        _input.clear();
      });
      SocialNotificationHub.refresh();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    } catch (e, st) {
      reportError(e, st, reason: 'dm:send');
      if (!mounted) return;
      // Specific copy for "conversation is gone" (blocked / deleted by recipient).
      final raw = e.toString();
      final isGone = raw.contains(' 403') ||
          raw.contains(' 404') ||
          raw.toLowerCase().contains('forbidden') ||
          raw.toLowerCase().contains('not found');
      final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
      if (isGone) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('This conversation is unavailable.'),
            duration: Duration(seconds: 6),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Could not send. Tap retry.'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(label: 'Retry', onPressed: _send),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showModerationMenu() {
    final label = widget.peer.label;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: ZveltTokens.border, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(AppIcons.delete_user, color: ZveltTokens.text2),
                title: Text('Report user', style: TextStyle(color: ZveltTokens.text)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  ReportUserSheet.show(
                    context,
                    userId: widget.peer.userId,
                    username: widget.peer.username,
                    displayName: widget.peer.displayName,
                  );
                },
              ),
              ListTile(
                leading: const Icon(AppIcons.ban, color: ZveltTokens.error),
                title: Text('Block $label', style: const TextStyle(color: ZveltTokens.error)),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _blockPeer();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _blockPeer() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final label = widget.peer.label;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: Text('Block this user?', style: TextStyle(color: ZveltTokens.text)),
        content: Text(
          "You won't see $label's posts, comments, or messages.",
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
      await ModerationService().blockUser(widget.peer.userId);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$label blocked')));
      SocialNotificationHub.refresh();
      // Best-effort: pop back to the conversations list.
      navigator.pop();
    } on ModerationException catch (e, st) {
      if (e.isNotDeployed) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('$label blocked locally')));
        navigator.pop();
        return;
      }
      reportError(e, st, reason: 'dm-chat:block-peer');
      messenger.showSnackBar(
        SnackBar(content: Text(e.isNetworkError ? 'Network error' : "Couldn't block")),
      );
    } catch (e, st) {
      reportError(e, st, reason: 'dm-chat:block-peer');
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't block")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        title: Text(widget.peer.label),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(AppIcons.refresh), onPressed: _loading ? null : _load),
          IconButton(
            icon: const Icon(AppIcons.menu_dots_vertical),
            tooltip: 'More',
            onPressed: _showModerationMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
                : _error != null
                    ? ZveltErrorState(
                        tier: ZveltErrorTier.generic,
                        title: "Couldn't load this chat",
                        onRetry: _load,
                      )
                    : _msgs.isEmpty
                        ? const ZveltEmptyState(
                            icon: AppIcons.comment_alt,
                            title: 'No messages yet. Say hi.',
                            subtitle:
                                "Messages sent through Zvelt — share what you'd share in person.",
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                            // +1 slot reserved for the "Load earlier" header
                            // tile when more history is available.
                            itemCount: _msgs.length + (_hasMoreEarlier ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (_hasMoreEarlier && i == 0) {
                                return _LoadEarlierTile(
                                  key: const ValueKey('dm-load-earlier'),
                                  loading: _loadingEarlier,
                                  onTap: _loadEarlier,
                                );
                              }
                              final msgIndex = _hasMoreEarlier ? i - 1 : i;
                              final m = _msgs[msgIndex];
                              final isMe = _myId != null && m.senderId == _myId;
                              final stampText = safeRelativeTime(m.createdAt);
                              return Padding(
                                // Stable key on message id keeps each bubble's
                                // element identity even when older history is
                                // prepended above it.
                                key: ValueKey('dm-msg-${m.id}'),
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    BubbleNormal(
                                      text: m.body,
                                      isSender: isMe,
                                      color: isMe ? ZveltTokens.brand : ZveltTokens.surface2,
                                      textStyle: TextStyle(
                                        color: isMe ? ZveltTokens.onBrand : ZveltTokens.text,
                                        fontSize: 15,
                                        height: 1.35,
                                      ),
                                      tail: true,
                                    ),
                                    if (stampText.isNotEmpty)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          left: isMe ? 0 : 16,
                                          right: isMe ? 16 : 0,
                                          top: 2,
                                        ),
                                        child: Text(
                                          stampText,
                                          style: TextStyle(
                                            color: ZveltTokens.text2,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
          Container(
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              border: Border(top: BorderSide(color: ZveltTokens.border)),
            ),
            padding: EdgeInsets.only(
              left: 12,
              right: 8,
              top: 10,
              bottom: MediaQuery.paddingOf(context).bottom + 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(color: ZveltTokens.text, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Message…',
                      hintStyle: TextStyle(color: ZveltTokens.text2),
                      filled: true,
                      fillColor: ZveltTokens.surface2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: _sending ? null : (_) => _send(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: _sending ? null : _send,
                  style: IconButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    disabledBackgroundColor:
                        ZveltTokens.brand.withValues(alpha: 0.45),
                    disabledForegroundColor: ZveltTokens.onBrand,
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ZveltTokens.onBrand,
                          ),
                        )
                      : const Icon(AppIcons.paper_plane),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Header tile rendered at the top of the chat list when more older messages
/// are available on the server. Tapping fetches the next page; while a fetch
/// is in flight a small spinner replaces the chevron.
class _LoadEarlierTile extends StatelessWidget {
  const _LoadEarlierTile({super.key, required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Pill chip (light variant) — the old bare gray text read as a label,
    // not a button, so pagination was easy to miss.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s2, horizontal: ZveltTokens.s4),
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rPill),
              border: Border.all(color: ZveltTokens.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ZveltTokens.text2,
                    ),
                  )
                else
                  Icon(
                    AppIcons.angle_small_up,
                    size: 16,
                    color: ZveltTokens.text2,
                  ),
                const SizedBox(width: 6),
                Text(
                  loading ? 'Loading…' : 'Load earlier',
                  style: TextStyle(
                    color: ZveltTokens.text2,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
