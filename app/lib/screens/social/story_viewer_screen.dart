import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/api_config.dart' show mediaAbsoluteUrl;
import '../../services/_crash_reporter.dart';
import '../../services/stories_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../utils/relative_time.dart';
import '../../widgets/zvelt_avatar.dart';
import '../../widgets/zvelt_network_image.dart';

/// Full-screen Instagram-style story viewer. Plays each author's stories
/// oldest→newest with a segmented progress bar that auto-advances every 5s; tap
/// right/left to skip, long-press to pause, swipe down to close. Own stories can
/// be deleted; others' can be hearted.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.groups,
    required this.initialGroup,
    required this.service,
    this.meId,
    this.onChanged,
  });

  final List<StoryAuthorGroup> groups;
  final int initialGroup;
  final StoriesService service;
  final String? meId;

  /// Called (once) when something changed (a like toggled, a story deleted) so
  /// the feed can refresh its tray on return.
  final VoidCallback? onChanged;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const _perStory = Duration(seconds: 5);

  late final List<StoryAuthorGroup> _groups;
  late final AnimationController _progress;

  int _groupIdx = 0;
  int _storyIdx = 0;
  bool _paused = false;
  bool _changed = false;
  bool _liking = false;

  // Local like overrides keyed by story id (so a tap reflects instantly without
  // a feed reload).
  final Map<String, ({bool liked, int count})> _likeState = {};

  @override
  void initState() {
    super.initState();
    // Defensive copy with growable story lists so deletes can mutate in place.
    _groups = widget.groups
        .where((g) => g.stories.isNotEmpty)
        .map((g) => StoryAuthorGroup(
              userId: g.userId,
              authorName: g.authorName,
              stories: List<Story>.of(g.stories),
              isMe: g.isMe,
            ))
        .toList();
    _groupIdx = widget.initialGroup.clamp(0, (_groups.length - 1).clamp(0, 1 << 30));
    _progress = AnimationController(vsync: this, duration: _perStory)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _advance();
      });
    // Immersive full-screen: hide the status/nav bars so the media is true
    // full-bleed and system UI can't sit over the top progress bars.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restart());
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _progress.dispose();
    super.dispose();
  }

  StoryAuthorGroup get _group => _groups[_groupIdx];
  Story get _story => _group.stories[_storyIdx];

  bool get _likedNow =>
      _likeState[_story.id]?.liked ?? _story.likedByMe;
  int get _likeCountNow =>
      _likeState[_story.id]?.count ?? _story.likeCount;

  void _restart() {
    if (!mounted) return;
    _progress
      ..reset()
      ..forward();
  }

  void _advance() {
    if (_storyIdx + 1 < _group.stories.length) {
      setState(() => _storyIdx++);
      _restart();
    } else if (_groupIdx + 1 < _groups.length) {
      setState(() {
        _groupIdx++;
        _storyIdx = 0;
      });
      _restart();
    } else {
      _close();
    }
  }

  void _rewind() {
    if (_storyIdx > 0) {
      setState(() => _storyIdx--);
      _restart();
    } else if (_groupIdx > 0) {
      setState(() {
        _groupIdx--;
        _storyIdx = _groups[_groupIdx].stories.length - 1;
      });
      _restart();
    } else {
      _restart(); // already at the very first — just replay it
    }
  }

  void _close() {
    if (_changed) widget.onChanged?.call();
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _onTapUp(TapUpDetails d) {
    final w = MediaQuery.of(context).size.width;
    if (d.localPosition.dx < w * 0.32) {
      _rewind();
    } else {
      _advance();
    }
  }

  void _setPaused(bool v) {
    if (_paused == v) return;
    setState(() => _paused = v);
    if (v) {
      _progress.stop();
    } else {
      _progress.forward();
    }
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    setState(() => _liking = true);
    final id = _story.id;
    // Optimistic flip.
    final wasLiked = _likedNow;
    final wasCount = _likeCountNow;
    setState(() => _likeState[id] =
        (liked: !wasLiked, count: wasCount + (wasLiked ? -1 : 1)));
    try {
      final r = await widget.service.toggleLike(id);
      if (!mounted) return;
      setState(() => _likeState[id] = (liked: r.liked, count: r.likeCount));
      _changed = true;
    } catch (e, st) {
      reportError(e, st, reason: 'stories:like');
      if (!mounted) return;
      // Roll back the optimistic flip.
      setState(() => _likeState[id] = (liked: wasLiked, count: wasCount));
    } finally {
      if (mounted) setState(() => _liking = false);
    }
  }

  Future<void> _confirmDelete() async {
    _setPaused(true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: Text('Delete story?', style: ZType.h4.copyWith(color: ZveltTokens.text)),
        content: Text('This can\'t be undone.',
            style: ZType.bodyM.copyWith(color: ZveltTokens.text3)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: ZType.bodyM.copyWith(color: ZveltTokens.error)),
          ),
        ],
      ),
    );
    if (ok != true) {
      _setPaused(false);
      return;
    }
    final id = _story.id;
    try {
      await widget.service.deleteStory(id);
      if (!mounted) return;
      _changed = true;
      _removeCurrentStory();
    } catch (e, st) {
      reportError(e, st, reason: 'stories:delete');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t delete the story.')),
      );
      _setPaused(false);
    }
  }

  /// Drops the on-screen story after a successful delete and moves on.
  void _removeCurrentStory() {
    _group.stories.removeAt(_storyIdx);
    if (_group.stories.isEmpty) {
      _groups.removeAt(_groupIdx);
      if (_groups.isEmpty) {
        _close();
        return;
      }
      if (_groupIdx >= _groups.length) _groupIdx = _groups.length - 1;
      _storyIdx = 0;
    } else if (_storyIdx >= _group.stories.length) {
      _storyIdx = _group.stories.length - 1;
    }
    setState(() => _paused = false);
    _restart();
  }

  @override
  Widget build(BuildContext context) {
    // Defensive: a delete that empties everything pops before this runs, but
    // guard anyway so we never index into an empty list.
    if (_groups.isEmpty) return const Scaffold(backgroundColor: Colors.black);
    final story = _story;
    final group = _group;
    final hasImage = story.imageUrl != null && story.imageUrl!.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Media ────────────────────────────────────────────────────────
          Positioned.fill(
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: hasImage
                  ? ZveltNetworkImage(
                      key: ValueKey(story.id),
                      url: mediaAbsoluteUrl(story.imageUrl),
                      fit: BoxFit.contain,
                      width: double.infinity,
                      cacheWidth: ZveltImageCacheWidth.feedFull,
                      placeholder: (_) => const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      ),
                    )
                  : _TextStory(caption: story.caption),
            ),
          ),

          // ── Gesture layer (tap zones, pause, swipe-to-close) ─────────────
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _onTapUp,
              onLongPressStart: (_) => _setPaused(true),
              onLongPressEnd: (_) => _setPaused(false),
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 250) _close();
              },
              child: const SizedBox.expand(),
            ),
          ),

          // ── Top: progress segments + header ──────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(ZveltTokens.s3, ZveltTokens.s2, ZveltTokens.s3, 0),
              child: Column(
                children: [
                  IgnorePointer(
                    child: Row(
                      children: [
                        for (var j = 0; j < group.stories.length; j++) ...[
                          Expanded(child: _Segment(
                            controller: _progress,
                            state: j < _storyIdx
                                ? _SegState.done
                                : j == _storyIdx
                                    ? _SegState.active
                                    : _SegState.pending,
                          )),
                          if (j != group.stories.length - 1)
                            const SizedBox(width: 4),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: ZveltTokens.s3),
                  Row(
                    children: [
                      ZveltAvatar(
                        size: AvatarSize.sm,
                        displayName: group.authorName,
                        userId: group.userId,
                      ),
                      const SizedBox(width: ZveltTokens.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              group.isMe ? 'Your story' : group.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ZType.bodyM.copyWith(
                                  color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              relativeTime(story.createdAt.toLocal()),
                              style: ZType.bodyS.copyWith(
                                  color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      if (group.isMe)
                        IconButton(
                          onPressed: _confirmDelete,
                          icon: const Icon(AppIcons.trash, color: Colors.white, size: 20),
                          tooltip: 'Delete',
                        ),
                      IconButton(
                        onPressed: _close,
                        icon: const Icon(AppIcons.cross_small, color: Colors.white, size: 24),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom: caption + location + like ────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(
              story: story,
              // A text-only story already renders its caption big-centered, so
              // don't repeat it in the bottom bar.
              showCaption: hasImage,
              liked: _likedNow,
              likeCount: _likeCountNow,
              onLike: group.isMe ? null : _toggleLike,
            ),
          ),
        ],
      ),
    );
  }
}

enum _SegState { done, active, pending }

class _Segment extends StatelessWidget {
  const _Segment({required this.controller, required this.state});
  final AnimationController controller;
  final _SegState state;

  @override
  Widget build(BuildContext context) {
    final track = Colors.white.withValues(alpha: 0.3);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: switch (state) {
          _SegState.done => Container(color: Colors.white),
          _SegState.pending => Container(color: track),
          _SegState.active => Stack(
              children: [
                Container(color: track),
                AnimatedBuilder(
                  animation: controller,
                  builder: (_, __) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: controller.value.clamp(0.0, 1.0),
                    child: Container(color: Colors.white),
                  ),
                ),
              ],
            ),
        },
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.story,
    required this.showCaption,
    required this.liked,
    required this.likeCount,
    required this.onLike,
  });

  final Story story;
  final bool showCaption;
  final bool liked;
  final int likeCount;
  final VoidCallback? onLike;

  @override
  Widget build(BuildContext context) {
    final hasCaption =
        showCaption && story.caption != null && story.caption!.trim().isNotEmpty;
    final hasLocation = story.location != null && story.location!.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.72), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s8, ZveltTokens.s5, ZveltTokens.s6),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasLocation) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AppIcons.location_alt, color: Colors.white70, size: 14),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      story.location!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZType.bodyS.copyWith(color: Colors.white70),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZveltTokens.s2),
            ],
            if (hasCaption) ...[
              Text(
                story.caption!.trim(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: ZType.bodyL.copyWith(color: Colors.white, height: 1.3),
              ),
              const SizedBox(height: ZveltTokens.s3),
            ],
            Row(
              children: [
                if (onLike != null)
                  Semantics(
                    button: true,
                    label: liked ? 'Unlike' : 'Like',
                    child: GestureDetector(
                      onTap: onLike,
                      behavior: HitTestBehavior.opaque,
                      // Padding lifts the hit area to a 44dp minimum touch target.
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(AppIcons.heart,
                                color: liked ? ZveltTokens.error : Colors.white, size: 26),
                            if (likeCount > 0) ...[
                              const SizedBox(width: 6),
                              Text('$likeCount',
                                  style: ZType.bodyM.copyWith(
                                      color: Colors.white, fontWeight: FontWeight.w600)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  // Own story — read-only heart tally of viewers' likes.
                  const Icon(AppIcons.heart, color: Colors.white70, size: 22),
                  const SizedBox(width: 6),
                  Text('$likeCount likes',
                      style: ZType.bodyM.copyWith(color: Colors.white70)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Fallback for a caption-only (no photo) story — centered text on a brand wash.
class _TextStory extends StatelessWidget {
  const _TextStory({required this.caption});
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: ZveltTokens.gradBrand),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(ZveltTokens.s8),
      child: Text(
        (caption != null && caption!.trim().isNotEmpty) ? caption!.trim() : '…',
        textAlign: TextAlign.center,
        style: ZType.h2.copyWith(color: Colors.white, height: 1.3),
      ),
    );
  }
}
