import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/services.dart';
import '../theme/zvelt_tokens.dart';
import '../config/api_config.dart' show mediaAbsoluteUrl;
import '../models/social_feed_post.dart';
import '../screens/social/report_user_sheet.dart';
import '../screens/social/user_profile_screen.dart';
import '../services/_crash_reporter.dart';
import '../services/moderation_service.dart';
import '../services/social_feed_service.dart';
import '../services/auth_service.dart';
import '../utils/display_name.dart';
import '../utils/relative_time.dart';
import 'zvelt_avatar.dart';
import 'zvelt_network_image.dart';

class SocialFeedPostCard extends StatefulWidget {
  const SocialFeedPostCard({
    super.key,
    required this.post,
    required this.service,
    required this.onLike,
    // Design: 18px screen gutters (screens-social.jsx `padding: '70px 18px'`).
    this.margin = const EdgeInsets.fromLTRB(18, 0, 18, 14),
    this.onDelete,
    this.onEdit,
    this.initiallyBookmarked = false,
    this.onBookmarkChanged,
  });

  final SocialFeedPost post;
  final SocialFeedService service;
  final VoidCallback onLike;
  final EdgeInsets margin;
  final VoidCallback? onDelete;
  final Function(SocialFeedPost)? onEdit;
  /// Seeds the in-card bookmark state. Surfaces from contexts like the
  /// "My Bookmarks" screen where every rendered card is, by definition,
  /// already bookmarked.
  final bool initiallyBookmarked;
  /// Fires after a successful bookmark toggle with the new server state.
  /// Lets parent screens (e.g. BookmarksScreen) remove a card when the user
  /// un-bookmarks it from the action button or post menu.
  final ValueChanged<bool>? onBookmarkChanged;

  @override
  State<SocialFeedPostCard> createState() => _SocialFeedPostCardState();
}

class _SocialFeedPostCardState extends State<SocialFeedPostCard> {
  bool _liked = false;
  bool _bookmarked = false;
  // Per-card in-flight lock for the like toggle. Debounces double-tap so we
  // never fire two parallel POSTs that race on the server, and gives the heart
  // icon a dim state while the request is in flight. See Wave 19a-2.
  bool _liking = false;
  late int _likeCount;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    // Seed heart state + count from the model — the backend now reports
    // `likedByMe` per post, so a post the viewer already liked renders with
    // a filled heart instead of the previously hardcoded `false`.
    _liked = widget.post.likedByMe;
    _likeCount = widget.post.likeCount;
    _bookmarked = widget.initiallyBookmarked;
    AuthService().getCurrentUserId().then((id) {
      if (mounted) setState(() => _myUserId = id);
    });
  }

  @override
  void didUpdateWidget(covariant SocialFeedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post.id != widget.post.id) {
      // Card recycled for a different post — reseed everything.
      _liked = widget.post.likedByMe;
      _likeCount = widget.post.likeCount;
      return;
    }
    if (oldWidget.post.likeCount != widget.post.likeCount) {
      _likeCount = widget.post.likeCount;
    }
    // Reconcile the heart with fresh server data (e.g. PostDetailScreen
    // reloads the post after onLike) — but never while our own optimistic
    // toggle is still in flight, or the server's pre-toggle snapshot would
    // stomp the flip.
    if (!_liking && oldWidget.post.likedByMe != widget.post.likedByMe) {
      _liked = widget.post.likedByMe;
    }
  }

  String _getUserDisplayName() => resolveDisplayName(
        displayName: widget.post.authorName,
        username: widget.post.authorUsername,
        userId: widget.post.userId,
      );

  bool get _isOwner => _myUserId != null && _myUserId == widget.post.userId;

  void _openAuthorProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: widget.post.userId,
          displayName: widget.post.authorName,
          username: widget.post.authorUsername,
        ),
      ),
    );
  }

  Future<void> _showPostMenu(BuildContext ctx) async {
    final postId = widget.post.id;
    final isOwner = _isOwner;
    final messenger = ScaffoldMessenger.of(ctx);

    await showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl))),
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: ZveltTokens.border, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
              ),
            ),
            const SizedBox(height: ZveltTokens.s4),
            // Bookmark
            _PostMenuItem(
              icon: _bookmarked ? AppIcons.bookmark : AppIcons.bookmark,
              label: _bookmarked ? 'Remove bookmark' : 'Bookmark post',
              onTap: () async {
                Navigator.pop(sheetCtx);
                try {
                  final newState = await widget.service.toggleBookmark(postId);
                  if (mounted) setState(() => _bookmarked = newState);
                  widget.onBookmarkChanged?.call(newState);
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                    );
                  }
                }
              },
            ),
            // Share
            _PostMenuItem(
              icon: AppIcons.share,
              label: 'Share post',
              onTap: () async {
                Navigator.pop(sheetCtx);
                final link = 'zvelt://post/$postId';
                await Clipboard.setData(ClipboardData(text: link));
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Link copied!'), duration: Duration(seconds: 2)),
                  );
                }
              },
            ),
            // Hide
            _PostMenuItem(
              icon: AppIcons.eye_crossed,
              label: 'Hide this post',
              onTap: () async {
                Navigator.pop(sheetCtx);
                try {
                  await widget.service.hidePost(postId);
                  widget.onDelete?.call();
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                    );
                  }
                }
              },
            ),
            // Report
            _PostMenuItem(
              icon: AppIcons.flag,
              label: 'Report post',
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _showReportDialog(ctx, postId);
              },
              danger: true,
            ),
            // Block user (only if not the owner of the post)
            if (!isOwner)
              _PostMenuItem(
                icon: AppIcons.ban,
                label: 'Block ${_blockMenuLabel()}',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _confirmAndBlockAuthor(ctx);
                },
                danger: true,
              ),
            // Report user (only if not the owner)
            if (!isOwner)
              _PostMenuItem(
                icon: AppIcons.delete_user,
                label: 'Report user',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await ReportUserSheet.show(
                    ctx,
                    userId: widget.post.userId,
                    displayName: _getUserDisplayName(),
                  );
                },
                danger: true,
              ),
            // Edit (only owner)
            if (isOwner)
              _PostMenuItem(
                icon: AppIcons.edit,
                label: 'Edit post',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _showEditDialog(ctx, postId);
                },
              ),
            // Delete (only owner)
            if (isOwner)
              _PostMenuItem(
                icon: AppIcons.trash,
                label: 'Delete post',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _showDeleteConfirm(ctx, postId);
                },
                danger: true,
              ),
          ],
        ),
      ),
    );
  }

  String _blockMenuLabel() {
    final name = _getUserDisplayName();
    return name.startsWith('@') ? name : '@$name';
  }

  Future<void> _confirmAndBlockAuthor(BuildContext ctx) async {
    final messenger = ScaffoldMessenger.of(ctx);
    final name = _getUserDisplayName();
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: Text('Block this user?', style: TextStyle(color: ZveltTokens.text)),
        content: Text(
          "You won't see $name's posts, comments, or messages. You can unblock this user later.",
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
    if (ok != true) return;
    try {
      await ModerationService().blockUser(widget.post.userId);
      // Remove this post from the feed view — same UX as "Hide".
      widget.onDelete?.call();
      messenger.showSnackBar(SnackBar(content: Text('$name blocked')));
    } on ModerationException catch (e, st) {
      if (e.isNotDeployed) {
        widget.onDelete?.call();
        messenger.showSnackBar(SnackBar(content: Text('$name blocked locally')));
        return;
      }
      reportError(e, st, reason: 'feed-card:block-user');
      messenger.showSnackBar(
        SnackBar(content: Text(e.isNetworkError ? 'Network error' : "Couldn't block — try again")),
      );
    } catch (e, st) {
      reportError(e, st, reason: 'feed-card:block-user');
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't block — try again")));
    }
  }

  Future<void> _showReportDialog(BuildContext ctx, String postId) async {
    final messenger = ScaffoldMessenger.of(ctx);
    // Wave 22 P1.3 — dialog body is now a StatefulWidget that owns its
    // controller and disposes it. Previously this method created a
    // TextEditingController inline and never disposed it, leaking listeners
    // and selection state every time a report dialog opened.
    final result = await showDialog<String?>(
      context: ctx,
      builder: (_) => const _ReportReasonDialog(),
    );
    if (result == null) return;
    try {
      final reason = result.trim();
      await widget.service.reportPost(
        postId,
        reason: reason.isEmpty ? null : reason,
      );
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Reported'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _showEditDialog(BuildContext ctx, String postId) async {
    final messenger = ScaffoldMessenger.of(ctx);
    // Wave 22 P1.3 — see _showReportDialog.
    final result = await showDialog<String?>(
      context: ctx,
      builder: (_) => _EditCaptionDialog(initialCaption: widget.post.caption ?? ''),
    );
    if (result == null) return;
    try {
      final updated =
          await widget.service.editPost(postId, caption: result.trim());
      if (updated != null && mounted) {
        widget.onEdit?.call(updated);
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _showDeleteConfirm(BuildContext ctx, String postId) async {
    final messenger = ScaffoldMessenger.of(ctx);
    final confirmed = await showDialog<bool>(
      context: ctx,
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
    if (confirmed != true) return;
    try {
      await widget.service.deletePost(postId);
      widget.onDelete?.call();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  /// Optimistic like toggle with revert-on-failure.
  ///
  /// - `_liking` guards against double-tap firing two parallel POSTs (Wave 19a-2).
  /// - We flip the UI immediately, then call the service. On failure (typed
  ///   exception or unexpected server state) we revert both `_liked` and
  ///   `_likeCount` and surface a SnackBar so the user knows to retry.
  /// - If the server response carries the authoritative `liked` state and it
  ///   disagrees with our optimistic flip, we trust the server.
  Future<void> _handleLikeTap() async {
    if (_liking) return; // debounce double-tap
    final wasLiked = _liked;
    final newLiked = !wasLiked;
    setState(() {
      _liking = true;
      _liked = newLiked;
      _likeCount += newLiked ? 1 : -1;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final serverLiked = await widget.service.toggleLike(widget.post.id);
      if (!mounted) return;
      // If the server told us the authoritative state and it disagrees with
      // our optimistic flip, reconcile to the server's truth.
      if (serverLiked != null && serverLiked != newLiked) {
        setState(() {
          _liked = serverLiked;
          _likeCount += serverLiked ? 1 : -1;
          _likeCount += newLiked ? -1 : 1; // undo our optimistic delta
        });
      }
      widget.onLike();
    } catch (e, st) {
      reportError(e, st, reason: 'feed:toggle-like');
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _likeCount += newLiked ? -1 : 1; // revert delta
      });
      messenger?.showSnackBar(
        const SnackBar(content: Text("Couldn't update like — try again")),
      );
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  void _showComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      builder: (_) => SocialCommentsSheet(
        postId: widget.post.id,
        service: widget.service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final workSets = post.exercises
        .expand((e) => e.sets)
        .where((s) => s.tag == 'WORK')
        .length;

    // Headline lift: the heaviest WORK set across the post's exercises — drives
    // the hero stat block (the design's centerpiece).
    SocialFeedSet? topSet;
    String topName = '';
    for (final ex in post.exercises) {
      for (final s in ex.sets) {
        if (s.tag != 'WORK') continue;
        if (topSet == null || s.weightKg > topSet.weightKg) {
          topSet = s;
          topName = ex.name;
        }
      }
    }
    final showHeadline = topSet != null && !post.hideWeights && topSet.weightKg > 0;

    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // Design card padding: '18px 18px 14px'.
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              children: [
                ZveltAvatar(
                  size: AvatarSize.md,
                  displayName: widget.post.authorName,
                  username: widget.post.authorUsername,
                  userId: widget.post.userId,
                  onTap: _openAuthorProfile,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _openAuthorProfile,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          _getUserDisplayName(),
                          style: TextStyle(
                            color: ZveltTokens.text, fontSize: 13, fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _PrivacyBadge(visibility: post.visibility),
                          const SizedBox(width: 6),
                          Text(
                            relativeTime(post.createdAt),
                            style: TextStyle(color: ZveltTokens.text3, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (post.exercises.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ZveltTokens.brandTint,
                      borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      border: Border.all(color: ZveltTokens.brand.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${post.exercises.length} exercises',
                      style: const TextStyle(
                        color: ZveltTokens.brand, fontSize: 11, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Semantics(
                  label: 'Post options',
                  button: true,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => _showPostMenu(context),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Icon(AppIcons.menu_dots, size: 18, color: ZveltTokens.text2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (post.caption != null && post.caption!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text(
                post.caption!,
                style: TextStyle(color: ZveltTokens.text, fontSize: 13, height: 1.4),
              ),
            ),
          // ── Hero stat block: the headline lift (design centerpiece) ──────────
          if (showHeadline)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Container(
                padding: const EdgeInsets.all(ZveltTokens.s4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [ZveltTokens.brandTint, const Color(0xFFFFE0C0)],
                  ),
                  borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topName.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: ZveltTokens.fontMono,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                              color: ZveltTokens.text2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                topSet.weightKg.toStringAsFixed(topSet.weightKg % 1 == 0 ? 0 : 1),
                                style: TextStyle(
                                  fontFamily: ZveltTokens.fontMono,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: ZveltTokens.text,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text('kg',
                                  style: TextStyle(fontSize: 12, color: ZveltTokens.text2, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!post.hideReps)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: ZveltTokens.brand,
                          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                        ),
                        child: Text(
                          '× ${topSet.reps}',
                          style: const TextStyle(
                            color: ZveltTokens.onBrand,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (post.imageUrl != null && post.imageUrl!.isNotEmpty) ...[
            Divider(height: 1, color: ZveltTokens.border),
            Semantics(
              label: 'Workout photo by ${_getUserDisplayName()}',
              image: true,
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: ZveltNetworkImage(
                  url: mediaAbsoluteUrl(post.imageUrl),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  cacheWidth: ZveltImageCacheWidth.feedFull,
                  placeholder: (_) => Container(
                    color: ZveltTokens.bg2,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.brand),
                    ),
                  ),
                  errorWidget: (_) => Container(
                    color: ZveltTokens.bg2,
                    alignment: Alignment.center,
                    child: Icon(AppIcons.picture, color: ZveltTokens.text2, size: 40),
                  ),
                ),
              ),
            ),
          ],
          if (post.exercises.isNotEmpty) ...[
            Divider(height: 1, color: ZveltTokens.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
              child: Column(
                children: post.exercises.take(3).map((ex) {
                  final workSetsForEx = ex.sets.where((s) => s.tag == 'WORK').toList();
                  if (workSetsForEx.isEmpty) return const SizedBox.shrink();
                  final best = workSetsForEx.reduce((a, b) => a.weightKg > b.weightKg ? a : b);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(ex.name,
                              style: TextStyle(
                                color: ZveltTokens.text, fontSize: 13, fontWeight: FontWeight.w500,
                              )),
                        ),
                        if (!post.hideWeights && !post.hideReps)
                          Text(
                            '${workSetsForEx.length} sets · ${best.weightKg.toStringAsFixed(0)} kg × ${best.reps}',
                            style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
                          )
                        else if (!post.hideWeights)
                          Text('${best.weightKg.toStringAsFixed(0)} kg',
                              style: TextStyle(color: ZveltTokens.text2, fontSize: 12))
                        else
                          Text('${workSetsForEx.length} sets',
                              style: TextStyle(color: ZveltTokens.text2, fontSize: 12)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            if (post.exercises.length > 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: Text(
                  '+${post.exercises.length - 3} more exercises',
                  style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
                ),
              ),
          ],
          if (workSets > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Row(
                children: [
                  Text(
                    '$workSets sets logged',
                    style: TextStyle(color: ZveltTokens.text2, fontSize: 11),
                  ),
                ],
              ),
            ),
          Divider(height: 1, color: ZveltTokens.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Semantics(
                  label: _liked ? 'Unlike post' : 'Like post',
                  value: '$_likeCount likes',
                  button: true,
                  excludeSemantics: true,
                  child: _SocialActionButton(
                    icon: _liked ? AppIcons.heart : AppIcons.heart,
                    label: '$_likeCount',
                    color: _liked ? ZveltTokens.brand : ZveltTokens.text2,
                    opacity: _liking ? 0.6 : 1.0,
                    onTap: _handleLikeTap,
                  ),
                ),
                Semantics(
                  label: 'View comments',
                  value: '${post.commentCount} comments',
                  button: true,
                  excludeSemantics: true,
                  child: _SocialActionButton(
                    icon: AppIcons.comment_alt,
                    label: '${post.commentCount}',
                    color: ZveltTokens.text2,
                    onTap: _showComments,
                  ),
                ),
                // Design: share is a first-class action icon in the row, not
                // just a menu entry. Same copy-link behavior as the menu.
                Semantics(
                  label: 'Share post',
                  button: true,
                  excludeSemantics: true,
                  child: _SocialActionButton(
                    icon: AppIcons.share,
                    label: '',
                    color: ZveltTokens.text2,
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                          ClipboardData(text: 'zvelt://post/${post.id}'));
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                              content: Text('Link copied!'),
                              duration: Duration(seconds: 2)),
                        );
                      }
                    },
                  ),
                ),
                const Spacer(),
                Semantics(
                  label: _bookmarked ? 'Remove bookmark' : 'Save post',
                  button: true,
                  excludeSemantics: true,
                  child: _SocialActionButton(
                    icon: _bookmarked ? AppIcons.bookmark : AppIcons.bookmark,
                    label: '',
                    color: _bookmarked ? ZveltTokens.brand : ZveltTokens.text2,
                    onTap: () async {
                      try {
                        final newState = await widget.service.toggleBookmark(post.id);
                        if (mounted) setState(() => _bookmarked = newState);
                        widget.onBookmarkChanged?.call(newState);
                      } catch (e, st) {
                        reportError(e, st, reason: 'feed-card:toggle-bookmark');
                        // Failure = state UNCHANGED. The old handler flipped
                        // _bookmarked to the target state without the server
                        // having changed anything, and stayed silent.
                        if (mounted) {
                          // ignore: use_build_context_synchronously
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Couldn't update bookmark — try again.")),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialActionButton extends StatelessWidget {
  const _SocialActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.opacity = 1.0,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  // Visual dim while an action is in-flight (e.g. like POST pending).
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 13)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: 10),
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
    );
  }
}

class SocialCommentsSheet extends StatefulWidget {
  const SocialCommentsSheet({super.key, required this.postId, required this.service});
  final String postId;
  final SocialFeedService service;

  @override
  State<SocialCommentsSheet> createState() => _SocialCommentsSheetState();
}

class _SocialCommentsSheetState extends State<SocialCommentsSheet> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Offline used to leave _loading=true forever (infinite spinner, no
    // retry) because getComments threw a raw SocketException.
    try {
      final comments = await widget.service.getComments(widget.postId);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load comments. Check your connection.';
      });
    }
  }

  Future<void> _send() async {
    // Wave 22 P0.3 — guard against rapid double-tap on the Send button.
    // Without this, two POSTs land before the IconButton's onPressed=null
    // disabled state propagates, producing duplicate comments.
    if (_sending) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    var ok = false;
    try {
      ok = await widget.service.addComment(widget.postId, text);
      if (ok) {
        _ctrl.clear();
        await _load();
      }
    } catch (_) {
      // Network error — keep the user's text in the composer for retry.
      ok = false;
    } finally {
      // Previously an exception here left _sending=true forever, disabling
      // the send button for the rest of the sheet's life.
      if (mounted) setState(() => _sending = false);
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not post comment — try again.')),
      );
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

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, controller) => Column(
        children: [
          Center(child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(color: ZveltTokens.border, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('Comments', style: TextStyle(
              color: ZveltTokens.text, fontSize: 15, fontWeight: FontWeight.w700,
            )),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!,
                                style: TextStyle(color: ZveltTokens.text2)),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _loading = true;
                                  _error = null;
                                });
                                _load();
                              },
                              child: const Text('Retry',
                                  style: TextStyle(
                                      color: ZveltTokens.brand,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      )
                : _comments.isEmpty
                    ? Center(child: Text('No comments yet',
                        style: TextStyle(color: ZveltTokens.text2)))
                    : ListView.builder(
                        controller: controller,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _comments.length,
                        itemBuilder: (_, i) {
                          final c = _comments[i];
                          final authorLabel = _commentAuthor(c);
                          final commentUserId = c['userId'] as String?;
                          final userMap = c['user'] as Map<String, dynamic>?;
                          final profileMap = userMap?['profile'] as Map<String, dynamic>?;
                          void openProfile() {
                            if (commentUserId == null || commentUserId.isEmpty) return;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => UserProfileScreen(
                                  userId: commentUserId,
                                  displayName: profileMap?['displayName'] as String?,
                                  username: profileMap?['username'] as String?,
                                ),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ZveltAvatar(
                                  size: AvatarSize.sm,
                                  displayName: profileMap?['displayName'] as String?,
                                  username: profileMap?['username'] as String?,
                                  userId: commentUserId,
                                  onTap: openProfile,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          GestureDetector(
                                            onTap: openProfile,
                                            behavior: HitTestBehavior.opaque,
                                            child: Text(
                                              authorLabel,
                                              style: TextStyle(
                                                color: ZveltTokens.text, fontSize: 12, fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            safeRelativeTime(c['createdAt'] as String?),
                                            style: TextStyle(color: ZveltTokens.text2, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        c['body'] as String? ?? '',
                                        style: TextStyle(color: ZveltTokens.text, fontSize: 13, height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    // Spec caps comment.body at 500 chars — enforcing it here
                    // beats a server rejection with a generic error.
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Add a comment...',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _sending
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: ZveltTokens.brand))
                      : const Icon(AppIcons.paper_plane, color: ZveltTokens.brand),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostMenuItem extends StatelessWidget {
  const _PostMenuItem({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? ZveltTokens.error : ZveltTokens.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
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

/// Tiny pill showing the post's audience (public / friends / private). Mandated
/// by CLAUDE.md's "Privacy by default" principle — users must see at a glance
/// who can read each post they publish. Tap → tooltip with full explanation.
class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge({required this.visibility});
  final PostVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final spec = _spec(visibility);
    return Semantics(
      label: '${spec.label} post',
      value: spec.tooltip,
      child: Tooltip(
        message: spec.tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: spec.bg,
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
            border: Border.all(color: spec.fg.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(spec.icon, size: 10, color: spec.fg),
              const SizedBox(width: 4),
              Text(
                spec.label,
                style: TextStyle(
                  color: spec.fg,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _PrivacySpec _spec(PostVisibility v) {
    switch (v) {
      case PostVisibility.public:
        return _PrivacySpec(
          label: 'PUBLIC',
          icon: AppIcons.globe,
          fg: ZveltTokens.text2,
          bg: ZveltTokens.text2.withValues(alpha: 0.10),
          tooltip: 'This post is visible to everyone',
        );
      case PostVisibility.private:
        return _PrivacySpec(
          label: 'PRIVATE',
          icon: AppIcons.lock,
          fg: ZveltTokens.warn,
          bg: ZveltTokens.warn.withValues(alpha: 0.14),
          tooltip: 'Only you can see this post',
        );
      case PostVisibility.friends:
        return _PrivacySpec(
          label: 'FRIENDS',
          icon: AppIcons.users,
          fg: ZveltTokens.brand,
          bg: ZveltTokens.brandTint,
          tooltip: 'This post is visible to your friends only',
        );
    }
  }
}

class _PrivacySpec {
  const _PrivacySpec({
    required this.label,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.tooltip,
  });
  final String label;
  final IconData icon;
  final Color fg;
  final Color bg;
  final String tooltip;
}

/// Wave 22 P1.3 — dialog body for the "Report post" action. Owning the
/// controller in a [State] guarantees [TextEditingController.dispose] runs
/// when the dialog is dismissed (Pop / barrier tap / back button), which
/// the prior inline-controller pattern silently leaked.
///
/// Pops the dialog with the entered reason text, or `null` on cancel.
class _ReportReasonDialog extends StatefulWidget {
  const _ReportReasonDialog();

  @override
  State<_ReportReasonDialog> createState() => _ReportReasonDialogState();
}

class _ReportReasonDialogState extends State<_ReportReasonDialog> {
  late final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ZveltTokens.surface,
      title: Text('Report post', style: TextStyle(color: ZveltTokens.text)),
      content: TextField(
        controller: _ctrl,
        style: TextStyle(color: ZveltTokens.text),
        decoration: InputDecoration(
          hintText: 'Reason (optional)',
          hintStyle: TextStyle(color: ZveltTokens.text2),
        ),
        maxLines: 3,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop<String?>(context, null),
          child: Text('Cancel', style: TextStyle(color: ZveltTokens.text2)),
        ),
        TextButton(
          onPressed: () => Navigator.pop<String?>(context, _ctrl.text),
          child: const Text('Report', style: TextStyle(color: ZveltTokens.error)),
        ),
      ],
    );
  }
}

/// Wave 22 P1.3 — dialog body for the "Edit post" action. Same controller
/// ownership rationale as [_ReportReasonDialog].
///
/// Pops with the edited caption on Save, or `null` on Cancel.
class _EditCaptionDialog extends StatefulWidget {
  const _EditCaptionDialog({required this.initialCaption});
  final String initialCaption;

  @override
  State<_EditCaptionDialog> createState() => _EditCaptionDialogState();
}

class _EditCaptionDialogState extends State<_EditCaptionDialog> {
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
          child: const Text('Save', style: TextStyle(color: ZveltTokens.info)),
        ),
      ],
    );
  }
}
