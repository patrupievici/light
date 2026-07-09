import 'package:flutter/material.dart';
import '../theme/zvelt_tokens.dart';
import 'z/z_pressable.dart';

/// Tertiary CTA — text-only / ghost button. Lowest emphasis tier.
///
/// Used for low-emphasis actions like "Mark all read", "Cancel", "See all",
/// "Maybe later", "UNBLOCK". No background, just brand-colored text with an
/// optional leading icon. Pressed feedback via [InkWell].
///
/// Touch target is forced to ≥44pt high via internal padding even when
/// [dense] is true, so it remains accessible.
class ZveltTertiaryButton extends StatelessWidget {
  const ZveltTertiaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.dense = false,
    this.disabled = false,
    this.color,
  });

  final String label;
  final VoidCallback onTap;

  /// Optional leading icon.
  final IconData? icon;

  /// Visually compact — smaller font (13 vs 14) and tighter horizontal
  /// padding. The 44pt touch target is still preserved.
  final bool dense;

  final bool disabled;

  /// Override the text/icon color. Defaults to [ZveltTokens.brand] (brand).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? ZveltTokens.brand;
    final double fontSize = dense ? 13 : 14;
    final double iconSize = dense ? 16 : 18;
    final EdgeInsets padding = dense
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 14, vertical: 12);

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: ZPressable(
        onTap: disabled ? null : onTap,
        semanticLabel: label,
        pressedScale: 0.975,
        child: ConstrainedBox(
          // Enforce ≥44pt touch target even in dense mode.
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: iconSize, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    fontFamily: ZveltTokens.fontPrimary,
                    letterSpacing: 0.2,
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
