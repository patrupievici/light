import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';
import 'z_card.dart';

/// Compact V2 metric tile — used by `ZVitalsRow` for 4-up biometric grids.
/// Mirrors the `MetricTile` design from screens-train.jsx.
///
/// Visual: small (16px) brand-tinted icon · label · big value with optional
/// unit suffix · optional sub-line. Card is white with the standard
/// shadow-only treatment. Tap optional (the whole tile becomes a button).
class ZMetricTile extends StatelessWidget {
  const ZMetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.unit,
    this.sub,
    this.onTap,
    this.valueFontSize = 19,
    this.iconColor,
    this.iconFilled = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? unit;
  final String? sub;
  final VoidCallback? onTap;
  /// Default 19 — matches design. Override down to 16-17 for longer values
  /// (e.g. "6,842" or "7h 32m") that would otherwise overflow.
  final double valueFontSize;
  /// Defaults to [ZveltTokens.brand]. Override for biometric category tints
  /// (e.g. [ZveltTokens.recovery] for HRV, [ZveltTokens.sleep] for sleep).
  final Color? iconColor;
  /// True draws the icon as a filled glyph (matches design's `fill` flag for
  /// the flame metric — visually heavier signal).
  final bool iconFilled;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? ZveltTokens.brand;
    return ZCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
      radius: ZveltTokens.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ZveltTokens.text2,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.stat.copyWith(
                    fontSize: valueFontSize,
                    color: ZveltTokens.text,
                  ),
                ),
              ),
              if (unit != null && unit!.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  unit!,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: ZveltTokens.text3,
                  ),
                ),
              ],
            ],
          ),
          if (sub != null && sub!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 11,
                color: ZveltTokens.text3,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
