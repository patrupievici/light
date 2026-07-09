import 'package:flutter/material.dart';
import '../theme/zvelt_tokens.dart';
import 'z/z_pressable.dart';

/// Visual variant for [ZveltPrimaryButton].
///
/// - [gradient] — default brand gradient pill (orange). High-emphasis CTA on
///   neutral backgrounds.
/// - [darkInverse] — solid near-black pill with white text. Use ONLY when the
///   surrounding card already carries the brand color/glow (e.g. the orange
///   "race hero" card on social_plus_screen) — the gradient would clash, so
///   we invert to dark for contrast.
/// - [lightInverse] — solid white pill with near-black text. Use ONLY when
///   the surrounding card is dark and saturated (e.g. the configurator card
///   on race_hub_screen) — again, the gradient would disappear, so we
///   invert to white for contrast.
enum ZveltPrimaryVariant { gradient, darkInverse, lightInverse }

/// Primary CTA button — the highest-emphasis tier in the Zvelt design system.
///
/// Defaults to a 56-tall gradient pill. Two opt-in inversions
/// ([ZveltPrimaryVariant.darkInverse], [ZveltPrimaryVariant.lightInverse])
/// exist for documented edge cases where the gradient would clash with the
/// surrounding card. Set [small] for a 40-tall compact variant.
class ZveltPrimaryButton extends StatelessWidget {
  const ZveltPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.variant = ZveltPrimaryVariant.gradient,
    this.small = false,
    this.icon,
    this.busy = false,
    this.busyLabel,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final ZveltPrimaryVariant variant;

  /// When true, render at h=40 with smaller text/icon. Default h=56.
  final bool small;

  /// Optional trailing icon shown after the label.
  final IconData? icon;

  /// When true, replaces the icon with a spinner and disables the tap. Use
  /// for short in-flight ops (network call to launch/save/post).
  final bool busy;

  /// Label to show while [busy] is true. Defaults to [label].
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    final double height = small ? 40 : 56;
    final double radius = height / 2;
    final double fontSize = small ? 13 : 16;
    final double iconSize = small ? 14 : 18;

    final Color fg;
    final Color? bg;
    final Gradient? gradient;
    final Border? border;
    switch (variant) {
      case ZveltPrimaryVariant.gradient:
        fg = ZveltTokens.onBrand;
        bg = null;
        gradient = ZveltTokens.gradBtn;
        border = null;
        break;
      case ZveltPrimaryVariant.darkInverse:
        // Near-black pill → text must be light. (Pre-V2 ZveltTokens.text was
        // white; after the light-theme migration it's #111, which rendered
        // black-on-black here.)
        fg = Colors.white;
        bg = const Color(0xFF0A0A0C);
        gradient = null;
        border = Border.all(color: ZveltTokens.border);
        break;
      case ZveltPrimaryVariant.lightInverse:
        // White pill → text must be dark. (Symmetric V2 fix: ZveltTokens.bg is
        // a near-white cream, which was nearly invisible on white.)
        fg = ZveltTokens.text;
        bg = Colors.white;
        gradient = null;
        border = null;
        break;
    }

    final bool interactable = enabled && !busy;
    final String currentLabel = busy ? (busyLabel ?? label) : label;

    return Opacity(
      opacity: interactable ? 1 : 0.55,
      child: ZPressable(
        onTap: interactable ? onTap : null,
        semanticLabel: currentLabel,
        pressedScale: 0.975,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: bg,
            gradient: gradient,
            borderRadius: BorderRadius.circular(radius),
            border: border,
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy) ...[
                    SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(fg),
                      ),
                    ),
                    SizedBox(width: small ? 6 : 10),
                  ],
                  Text(
                    currentLabel,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                  ),
                  if (icon != null && !busy) ...[
                    SizedBox(width: small ? 6 : 8),
                    Icon(icon, size: iconSize, color: fg),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
