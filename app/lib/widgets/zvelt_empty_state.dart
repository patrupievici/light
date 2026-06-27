import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../theme/zvelt_tokens.dart';

/// Shared "empty state" surface used across the Feed / Social area
/// (consolidates Wave 19 audit finding #F4 — 4 different empty styles
/// folded into one).
///
/// Visual: centered column with a soft icon, a bold title, an optional
/// subtitle, and an optional CTA action. Use [compact] inside small
/// containers (cards, inline rows) and the default (full) mode for
/// screen-filling empty states.
class ZveltEmptyState extends StatelessWidget {
  const ZveltEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = AppIcons.inbox,
    this.iconColor,
    this.action,
    this.compact = false,
    this.mascot,
  });

  final String title;
  final String? subtitle;
  final IconData icon;

  /// Optional 3D coach-mascot asset (e.g. 'assets/mascot/m8.png'). When set
  /// (and not [compact]) it replaces the soft icon chip — the periwinkle
  /// design leads empty states with the rabbit coach.
  final String? mascot;

  /// Defaults to [ZveltTokens.text3] so the icon reads as a "soft" cue
  /// rather than an interactive element.
  final Color? iconColor;

  /// Optional CTA below the subtitle. Caller chooses the button
  /// flavor (`FilledButton`, `ZveltSecondaryButton`, etc.).
  final Widget? action;

  /// Smaller layout for in-card / in-sheet usage (no min height,
  /// shrunken type and icon, tighter padding).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final resolvedIconColor = iconColor ?? ZveltTokens.text3;
    final iconSize = compact ? 36.0 : 56.0;
    final titleSize = compact ? 14.0 : 16.0;
    final subtitleSize = compact ? 11.0 : 13.0;
    final verticalPad = compact ? 16.0 : 32.0;
    final minHeight = compact ? 0.0 : 220.0;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: ZveltTokens.s6, vertical: verticalPad),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mascot != null && !compact)
                Image.asset(
                  mascot!,
                  height: 120,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.all(ZveltTokens.s5),
                    decoration: BoxDecoration(
                      color: ZveltTokens.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: iconSize * 0.7, color: resolvedIconColor),
                  ),
                )
              else
                Container(
                  padding: EdgeInsets.all(compact ? ZveltTokens.s3 : ZveltTokens.s5),
                  decoration: BoxDecoration(
                    color: ZveltTokens.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: iconSize * 0.7, color: resolvedIconColor),
                ),
              SizedBox(height: compact ? ZveltTokens.s3 : ZveltTokens.s4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: ZType.h4.copyWith(
                  color: ZveltTokens.text,
                  fontSize: titleSize,
                  height: 1.3,
                ),
              ),
              if (subtitle != null) ...[
                SizedBox(height: compact ? ZveltTokens.s1 : 6),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: ZType.bodyS.copyWith(
                    color: ZveltTokens.text2,
                    fontSize: subtitleSize,
                    height: 1.4,
                  ),
                ),
              ],
              if (action != null) ...[
                SizedBox(height: compact ? ZveltTokens.s3 : ZveltTokens.s4),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
