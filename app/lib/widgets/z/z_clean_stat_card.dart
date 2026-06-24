import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';
import 'z_card.dart';
import 'z_eyebrow.dart';
import 'z_sparkline.dart';

/// Reusable stat card matching the design's `CleanStatCard` pattern.
/// Composition: small accent-tinted icon · eyebrow label · big value (with
/// optional unit) · sparkline at bottom (line or bars).
///
/// Use for things like "Resting HR · 30 days", "Volume · 7 days",
/// "Calories · today", etc. Pairs naturally with [ZSparkline.bars] for
/// daily quantities and the default line for cumulative metrics.
class ZCleanStatCard extends StatelessWidget {
  const ZCleanStatCard({
    super.key,
    required this.eyebrow,
    required this.icon,
    required this.value,
    this.unit,
    this.iconColor,
    this.valueColor,
    this.sparkValues = const [],
    this.sparkColor,
    this.sparkBars = false,
    this.onTap,
  });

  final String eyebrow;
  final IconData icon;
  /// Defaults to [ZveltTokens.brand].
  final Color? iconColor;
  final String value;
  final String? unit;
  /// Defaults to [ZveltTokens.text].
  final Color? valueColor;
  /// Optional time-series for the sparkline. Empty list = no sparkline.
  final List<double> sparkValues;
  /// Defaults to [iconColor] or brand if both unset — keeps a card visually
  /// monochromatic so the metric pops.
  final Color? sparkColor;
  /// True draws bars (daily quantities); false draws a smooth line (trends).
  final bool sparkBars;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ic = iconColor ?? ZveltTokens.brand;
    final vc = valueColor ?? ZveltTokens.text;
    final sc = sparkColor ?? ic;
    final hasSpark = sparkValues.isNotEmpty;

    return ZCard(
      onTap: onTap,
      padding: const EdgeInsets.all(ZveltTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: ic),
              const SizedBox(width: 6),
              ZEyebrow(eyebrow),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.stat.copyWith(fontSize: 28, color: vc),
                ),
              ),
              if (unit != null && unit!.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  unit!,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: ZveltTokens.text3,
                  ),
                ),
              ],
            ],
          ),
          if (hasSpark) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 28,
              child: LayoutBuilder(
                builder: (context, c) => ZSparkline(
                  values: sparkValues,
                  color: sc,
                  width: c.maxWidth,
                  height: 28,
                  bars: sparkBars,
                  fill: !sparkBars,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
