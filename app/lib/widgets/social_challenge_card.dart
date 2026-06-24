import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../models/social_challenge.dart';
import '../theme/zvelt_tokens.dart';

class SocialChallengeCard extends StatelessWidget {
  const SocialChallengeCard({
    super.key,
    required this.challenge,
    this.onDelete,
  });

  final SocialChallenge challenge;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final daysLeft = challenge.endsAt.difference(DateTime.now()).inDays.clamp(0, 9999);
    final scopeLabel = challenge.visibility == 'public' ? 'Public' : 'Friends only';
    final scopeIcon = challenge.visibility == 'public' ? AppIcons.globe : AppIcons.users;

    return Card(
      margin: const EdgeInsets.fromLTRB(ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s2, ZveltTokens.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(ZveltTokens.s2),
              decoration: BoxDecoration(
                color: ZveltTokens.brandTint.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(ZveltTokens.rMd),
              ),
              child: const Icon(AppIcons.gym, color: ZveltTokens.brand, size: 22),
            ),
            const SizedBox(width: ZveltTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    challenge.title,
                    style: ZType.h4.copyWith(fontSize: 15),
                  ),
                  if (!challenge.isMine) ...[
                    const SizedBox(height: ZveltTokens.s1),
                    Text(
                      'by ${challenge.creatorDisplayName?.trim().isNotEmpty == true ? challenge.creatorDisplayName! : 'Someone'}',
                      style: ZType.monoS,
                    ),
                  ],
                  if (challenge.targetHint != null && challenge.targetHint!.isNotEmpty) ...[
                    const SizedBox(height: ZveltTokens.s1),
                    Text(
                      challenge.targetHint!,
                      style: const TextStyle(color: ZveltTokens.info, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: ZveltTokens.s2),
                  Wrap(
                    spacing: ZveltTokens.s2,
                    runSpacing: ZveltTokens.s2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        avatar: Icon(scopeIcon, size: 16, color: ZveltTokens.text2),
                        label: Text(scopeLabel, style: TextStyle(fontSize: 11, color: ZveltTokens.text2)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        side: BorderSide(color: ZveltTokens.border.withValues(alpha: 0.8)),
                        backgroundColor: ZveltTokens.surface2,
                      ),
                      Text(
                        daysLeft == 0 ? 'Ends today' : '$daysLeft days left',
                        style: TextStyle(color: ZveltTokens.text2, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(AppIcons.cross_small, size: 20),
                color: ZveltTokens.text2,
                tooltip: 'Remove',
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
