import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../theme/zvelt_tokens.dart';
import 'z_metric_tile.dart';

/// One row of vital signs in a 4-up grid. Mirrors `VitalsRow` from
/// screens-train.jsx — Heart Rate · Steps · Sleep · Stress by default,
/// but fully customizable via [tiles].
///
/// Use either:
///   - the default constructor with explicit values (real biometric data
///     pushed in from the parent), OR
///   - [ZVitalsRow.placeholder] for design previews and screens that don't
///     yet have biometric integration wired up.
class ZVitalsRow extends StatelessWidget {
  const ZVitalsRow({super.key, required this.tiles, this.gap = 7});

  /// Up to 4 vital tiles. Constraint not enforced — extra tiles will
  /// overflow the row visually; trim before passing.
  final List<ZVitalTile> tiles;
  final double gap;

  /// Placeholder set that matches the design screenshot — useful for
  /// previews while real biometric data plumbing lands.
  factory ZVitalsRow.placeholder({Key? key, VoidCallback? onTap}) {
    return ZVitalsRow(
      key: key,
      tiles: [
        ZVitalTile(
          icon: AppIcons.heart,
          label: 'Heart Rate',
          value: '128',
          unit: 'bpm',
          sub: 'Zone 2',
          iconColor: ZveltTokens.cardio,
          onTap: onTap,
        ),
        ZVitalTile(
          icon: AppIcons.running,
          label: 'Steps',
          value: '6,842',
          sub: 'Goal 10k',
          valueFontSize: 17,
          onTap: onTap,
        ),
        ZVitalTile(
          icon: AppIcons.moon,
          label: 'Sleep',
          value: '7h 32m',
          sub: 'Good',
          valueFontSize: 16,
          iconColor: ZveltTokens.sleep,
          onTap: onTap,
        ),
        ZVitalTile(
          icon: AppIcons.flame,
          label: 'Stress',
          value: '36',
          sub: 'Low',
          iconColor: ZveltTokens.stress,
          iconFilled: true,
          onTap: onTap,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            child: ZMetricTile(
              icon: tiles[i].icon,
              label: tiles[i].label,
              value: tiles[i].value,
              unit: tiles[i].unit,
              sub: tiles[i].sub,
              onTap: tiles[i].onTap,
              valueFontSize: tiles[i].valueFontSize,
              iconColor: tiles[i].iconColor,
              iconFilled: tiles[i].iconFilled,
            ),
          ),
        ],
      ],
    );
  }
}

/// Data-only descriptor passed to [ZVitalsRow]. Mirrors the props on
/// [ZMetricTile] but keeps the row's content decoupled from widget
/// construction so callers can build the list inline.
class ZVitalTile {
  const ZVitalTile({
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
  final double valueFontSize;
  final Color? iconColor;
  final bool iconFilled;
}
