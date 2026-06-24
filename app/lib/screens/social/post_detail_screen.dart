import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../models/social_feed_post.dart';
import '../../services/_crash_reporter.dart';
import '../../services/moderation_service.dart';
import '../../services/social_feed_service.dart';
import '../../services/auth_service.dart';
import '../../utils/display_name.dart';
import '../../utils/relative_time.dart';
import '../../widgets/social_feed_post_card.dart';
import '../../widgets/zvelt_avatar.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';
import 'report_user_sheet.dart';
import 'user_profile_screen.dart';

/// Post + listă comentarii + composer (Excel #36 parțial — fără reply nested în DB).
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _service = SocialFeedService();
  final _commentCtrl = TextEditingController();
  SocialFeedPost? _post;
  List<Map<String, dynamic>> _comments = [];
  bool _loadingPost = true;
  bool _loadingComments = true;
  bool _sending = false;
  String? _error;
  String? _myUserId;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadPost();
    _loadComments();
    AuthService().getCurrentUserId().then((id) {
      if (mounted) setState(() => _myUserId = id);
    });
  }

  Future<void> _loadPost() async {
    setState(() {
      _loadingPost = true;
      _error = null;
    });
    try {
      final p = await _service.getPost(widget.postId);
      if (!mounted) return;
      if (p == null) {
        setState(() {
          _loadingPost = false;
          _error = 'Post not found or no access';
        });
        return;
      }
      setState(() {
        _post = p;
        _loadingPost = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPost = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadComments() async {
    setState(() => _loadingComments = true);
    try {
      final list = await _service.getComments(widget.postId);
      if (!mounted) return;
      setState(() {
        _comments = list;
        _loadingComments = false;
      });
    } catch (e, st) {
      reportError(e, st, reason: 'post-detail:load-comments');
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  Future<void> _sendComment() async {
    // Wave 22 P0.3 — explicit guard at the top mirrors the canonical
    // double-tap defense shared with SocialCommentsSheet._send() and
    // DirectChatScreen._send().
    if (_sending) return;
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    var ok = false;
    try {
      ok = await _service.addComment(widget.postId, text);
      if (ok && mounted) {
        _commentCtrl.clear();
        await _loadComments();
      }
    } catch (_) {
      // Network error — keep the text in the composer so the user can retry.
      ok = false;
    } finally {
      // An unguarded throw used to leave _sending=true forever (dead send
      // button for the rest of the screen's life).
      if (mounted) setState(() => _sending = false);
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not post comment — try again.')),
      );
    }
  }

  bool get _isOwner => _myUserId != null && _post != null && _myUserId == _post!.userId;

  void _showOwnerMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl))),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: ZveltTokens.border, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
              ),
            ),
            const SizedBox(height: 16),
            _OwnerMenuItem(
              icon: AppIcons.edit,
              label: 'Edit post',
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _showEditDialog();
              },
            ),
            _OwnerMenuItem(
              icon: AppIcons.trash,
              label: 'Delete post',
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _showDeleteConfirm();
              },
              danger: true,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditDialog() async {
    // Wave 22 P1.3 — dialog body is a StatefulWidget that owns and disposes
    // its TextEditingController. The previous inline-controller pattern
    // leaked the controller every time the dialog was dismissed.
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => _PostDetailEditCaptionDialog(
        initialCaption: _post?.caption ?? '',
      ),
    );
    if (result == null || !mounted) return;
    try {
      final updated =
          await _service.editPost(widget.postId, caption: result.trim());
      if (updated != null && mounted) {
        setState(() => _post = updated);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _showDeleteConfirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: Text('Delete post', style: TextStyle(color: ZveltTokens.text)),
        content: Text(
          'This action cannot be undone. Are you sure?',
          style: TextStyle(color: ZveltTokens.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text('Cancel', style: TextStyle(color: ZveltTokens.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete', style: TextStyle(color: ZveltTokens.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deletePost(widget.postId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  /// Long-press a comment → moderation actions. Apple §1.2 surface.
  void _showCommentMenu(Map<String, dynamic> comment) {
    final commentUserId = comment['userId'] as String?;
    if (commentUserId == null || commentUserId.isEmpty) return;
    // Don't show on your own comments.
    if (_myUserId != null && commentUserId == _myUserId) return;
    final displayName = _commentAuthor(comment);
    final username = ((comment['user'] as Map<String, dynamic>?)?['profile']
        as Map<String, dynamic>?)?['username'] as String?;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(AppIcons.delete_user, color: ZveltTokens.text2),
              title: Text('Report user', style: TextStyle(color: ZveltTokens.text)),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await ReportUserSheet.show(
                  context,
                  userId: commentUserId,
                  username: username,
                  displayName: displayName,
                );
              },
            ),
            ListTile(
              leading: const Icon(AppIcons.ban, color: ZveltTokens.error),
              title: Text('Block $displayName', style: const TextStyle(color: ZveltTokens.error)),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _blockFromComment(commentUserId, displayName);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _blockFromComment(String userId, String label) async {
    final messenger = ScaffoldMessenger.of(context);
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
      await ModerationService().blockUser(userId);
      if (!mounted) return;
      setState(() {
        _comments = _comments.where((c) => c['userId'] != userId).toList();
      });
      messenger.showSnackBar(SnackBar(content: Text('$label blocked')));
    } on ModerationException catch (e, st) {
      if (e.isNotDeployed) {
        if (!mounted) return;
        setState(() {
          _comments = _comments.where((c) => c['userId'] != userId).toList();
        });
        messenger.showSnackBar(SnackBar(content: Text('$label blocked locally')));
        return;
      }
      reportError(e, st, reason: 'post-detail:block-user');
      messenger.showSnackBar(
        SnackBar(content: Text(e.isNetworkError ? 'Network error' : "Couldn't block")),
      );
    } catch (e, st) {
      reportError(e, st, reason: 'post-detail:block-user');
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't block")));
    }
  }

  static String _commentAuthor(Map<String, dynamic> c) {
    final u = c['user'] as Map<String, dynamic>?;
    final p = u?['profile'] as Map<String, dynamic>?;
    return resolveDisplayName(
      displayName: p?['displayName'] as String?,
      username: p?['username'] as String?,
      userId: c['userId'] as String?,
    );
  }

  void _openCommentProfile(Map<String, dynamic> c) {
    final uid = c['userId'] as String?;
    if (uid == null || uid.isEmpty) return;
    final p = (c['user'] as Map<String, dynamic>?)?['profile'] as Map<String, dynamic>?;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: uid,
          displayName: p?['displayName'] as String?,
          username: p?['username'] as String?,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        title: const Text('Post'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(AppIcons.refresh),
            onPressed: () {
              _loadPost();
              _loadComments();
            },
          ),
          if (_isOwner)
            IconButton(
              tooltip: 'More options',
              icon: const Icon(AppIcons.menu_dots_vertical),
              onPressed: _showOwnerMenu,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadingPost
                ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
                : _error != null
                    ? ZveltErrorState(
                        tier: _error!.toLowerCase().contains('not found') ||
                                _error!.toLowerCase().contains('no access')
                            ? ZveltErrorTier.auth
                            : ZveltErrorTier.generic,
                        title: "Couldn't load this post",
                        message: _error,
                        onRetry: _loadPost,
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          if (_post != null)
                            SocialFeedPostCard(
                              post: _post!,
                              service: _service,
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              onLike: () => _loadPost(),
                              onEdit: (updated) => setState(() => _post = updated),
                              onDelete: () => Navigator.of(context).pop(),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Text(
                              'Comments',
                              style: TextStyle(
                                color: ZveltTokens.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_loadingComments)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                child: CircularProgressIndicator(color: ZveltTokens.brand),
                              ),
                            )
                          else if (_comments.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: ZveltEmptyState(
                                compact: true,
                                icon: AppIcons.comment_alt,
                                title: 'No comments yet',
                                subtitle: 'Be the first to leave one.',
                              ),
                            )
                          else
                            ..._comments.map((c) {
                              final authorLabel = _commentAuthor(c);
                              return GestureDetector(
                                onLongPress: () => _showCommentMenu(c),
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ZveltAvatar(
                                      size: AvatarSize.sm,
                                      displayName: ((c['user'] as Map<String, dynamic>?)?['profile']
                                              as Map<String, dynamic>?)?['displayName']
                                          as String?,
                                      username: ((c['user'] as Map<String, dynamic>?)?['profile']
                                              as Map<String, dynamic>?)?['username']
                                          as String?,
                                      userId: c['userId'] as String?,
                                      onTap: () => _openCommentProfile(c),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: GestureDetector(
                                                  onTap: () => _openCommentProfile(c),
                                                  behavior: HitTestBehavior.opaque,
                                                  child: Text(
                                                    authorLabel,
                                                    maxLines: 1,
                                                    style: TextStyle(
                                                      color: ZveltTokens.text,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                safeRelativeTime(c['createdAt'] as String?),
                                                style: TextStyle(
                                                  color: ZveltTokens.text2,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            c['body'] as String? ?? '',
                                            style: TextStyle(
                                              color: ZveltTokens.text,
                                              fontSize: 13,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                ),
                              );
                            }),
                        ],
                      ),
          ),
          Material(
            color: ZveltTokens.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.of(context).viewInsets.bottom),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentCtrl,
                        minLines: 1,
                        maxLines: 4,
                        // Spec: comment.body max 500 chars.
                        maxLength: 500,
                        style: TextStyle(color: ZveltTokens.text),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Write a comment…',
                          hintStyle: TextStyle(color: ZveltTokens.text2),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _sendComment(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Send comment',
                      onPressed: _sending ? null : _sendComment,
                      icon: _sending
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.brand),
                            )
                          : const Icon(AppIcons.paper_plane, color: ZveltTokens.brand),
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

class _OwnerMenuItem extends StatelessWidget {
  const _OwnerMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? ZveltTokens.error : ZveltTokens.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZveltTokens.rMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4, horizontal: ZveltTokens.s1),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? ZveltTokens.error : ZveltTokens.text2),
            const SizedBox(width: 16),
            Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

/// Wave 22 P1.3 — dialog body that owns its [TextEditingController] so the
/// controller is reliably disposed when the dialog goes away (Pop, barrier
/// tap, back gesture). The prior inline-controller pattern leaked the
/// controller every time an edit dialog was dismissed.
class _PostDetailEditCaptionDialog extends StatefulWidget {
  const _PostDetailEditCaptionDialog({required this.initialCaption});
  final String initialCaption;

  @override
  State<_PostDetailEditCaptionDialog> createState() =>
      _PostDetailEditCaptionDialogState();
}

class _PostDetailEditCaptionDialogState
    extends State<_PostDetailEditCaptionDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialCaption);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ZveltTokens.surface,
      title: Text('Edit post', style: TextStyle(color: ZveltTokens.text)),
      content: TextField(
        controller: _ctrl,
        style: TextStyle(color: ZveltTokens.text),
        decoration: InputDecoration(
          hintText: 'Caption',
          hintStyle: TextStyle(color: ZveltTokens.text2),
        ),
        maxLines: 5,
        maxLength: 500,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<String?>(context, null),
          child: Text('Cancel', style: TextStyle(color: ZveltTokens.text2)),
        ),
        TextButton(
          onPressed: () => Navigator.pop<String?>(context, _ctrl.text),
          child: const Text('Save', style: TextStyle(color: ZveltTokens.brand)),
        ),
      ],
    );
  }
}
