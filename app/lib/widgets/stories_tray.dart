import 'package:flutter/material.dart';

import '../config/api_config.dart' show mediaAbsoluteUrl;
import '../services/stories_service.dart';
import '../theme/app_icons.dart';
import '../theme/zvelt_tokens.dart';
import 'zvelt_avatar.dart';
import 'zvelt_network_image.dart';

/// Horizontal "stories" rail at the top of the feed. The first bubble always
/// adds a new story; the rest are one bubble per author with active stories
/// (the current user's own group, if any, is pulled to the front by
/// [groupStoriesByAuthor]).
class StoriesTray extends StatelessWidget {
  const StoriesTray({
    super.key,
    required this.groups,
    required this.onAddStory,
    required this.onOpenGroup,
  });

  final List<StoryAuthorGroup> groups;
  final VoidCallback onAddStory;

  /// Opens the full-screen viewer starting at [groupIndex] (index into
  /// [groups]).
  final void Function(int groupIndex) onOpenGroup;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s2),
        itemCount: groups.length + 1, // +1 = the "add" bubble at the front
        separatorBuilder: (_, __) => const SizedBox(width: ZveltTokens.s3),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _AddBubble(onTap: onAddStory);
          }
          final g = groups[i - 1];
          return _StoryBubble(
            group: g,
            onTap: () => onOpenGroup(i - 1),
          );
        },
      ),
    );
  }
}

class _AddBubble extends StatelessWidget {
  const _AddBubble({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _BubbleColumn(
      label: 'Adaugă',
      onTap: onTap,
      ring: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: ZveltTokens.surface2,
          shape: BoxShape.circle,
          border: Border.all(color: ZveltTokens.border, width: 1.5),
        ),
        child: const Icon(AppIcons.plus, color: ZveltTokens.brand, size: 26),
      ),
    );
  }
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({required this.group, required this.onTap});
  final StoryAuthorGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumb = group.thumbUrl;
    return _BubbleColumn(
      label: group.isMe ? 'Story-ul tău' : group.authorName,
      onTap: onTap,
      ring: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: ZveltTokens.gradBrand,
        ),
        padding: const EdgeInsets.all(2.5),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
          ).copyWith(color: ZveltTokens.surface),
          padding: const EdgeInsets.all(2),
          child: ClipOval(
            child: thumb != null
                ? ZveltNetworkImage(
                    url: mediaAbsoluteUrl(thumb),
                    fit: BoxFit.cover,
                    width: 56,
                    height: 56,
                    cacheWidth: ZveltImageCacheWidth.storyThumb,
                  )
                : ZveltAvatar(
                    size: AvatarSize.lg,
                    displayName: group.authorName,
                    userId: group.userId,
                  ),
          ),
        ),
      ),
    );
  }
}

class _BubbleColumn extends StatelessWidget {
  const _BubbleColumn({required this.label, required this.ring, required this.onTap});
  final String label;
  final Widget ring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ring,
            const SizedBox(height: ZveltTokens.s1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
