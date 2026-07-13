import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';

/// Variants per the design bundle's `.z-chip` class.
enum ZChipVariant {
  /// Default — soft surface, secondary text. Background: surface2.
  neutral,
  /// Brand — orange-tinted background, deep brand text. Used for active state.
  brand,
  /// Solid — full brand fill, white text. Strongest emphasis.
  solid,
}

/// V2 chip primitive — pill shape, no border, small font.
/// Mirrors the `.z-chip` CSS class from tokens.css.
class ZChip extends StatelessWidget {
  const ZChip({
    super.key,
    required this.label,
    this.icon,
    this.variant = ZChipVariant.neutral,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final ZChipVariant variant;
  final VoidCallback? onTap;

  Color get _bg {
    switch (variant) {
      case ZChipVariant.neutral:
        return ZveltTokens.surface2;
      case ZChipVariant.brand:
        return ZveltTokens.brandTint;
      case ZChipVariant.solid:
        return ZveltTokens.brand;
    }
  }

  Color get _fg {
    switch (variant) {
      case ZChipVariant.neutral:
        return ZveltTokens.text2;
      case ZChipVariant.brand:
        return ZveltTokens.brandDeep;
      case ZChipVariant.solid:
        return ZveltTokens.onBrand;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: _fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 11,
                letterSpacing: 0.01 * 11,
                color: _fg,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );

    final pill = Container(
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
      child: content,
    );

    if (onTap == null) return pill;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(ZveltTokens.rPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        onTap: onTap,
        child: pill,
      ),
    );
  }
}
