import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../screens/profile_screen.dart';
import '../theme/zvelt_tokens.dart';

/// Shown on Home when profile has no valid bodyweight (BW_REQUIRED guardrail).
class BodyweightBanner extends StatelessWidget {
  const BodyweightBanner({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s3),
      child: Material(
        color: ZveltTokens.warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        child: InkWell(
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
          ),
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ZveltTokens.rMd),
              border: Border.all(color: ZveltTokens.warn.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(AppIcons.balance_scale_left, color: ZveltTokens.warn, size: 22),
                const SizedBox(width: ZveltTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add bodyweight to unlock ranks',
                          style: TextStyle(color: ZveltTokens.text, fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: ZveltTokens.s1),
                      Text('Required for LP and seasonal leaderboard.',
                          style: TextStyle(color: ZveltTokens.text2, fontSize: 11)),
                    ],
                  ),
                ),
                Icon(AppIcons.angle_small_right, color: ZveltTokens.text2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
