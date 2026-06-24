import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';

/// GitHub-style activity heatmap. Mirrors `ActivityGrid` from
/// screens-train.jsx — a grid of `weeks × 7` squares colored by intensity
/// (0 = empty surface · 1-4 = increasing brand opacity).
///
/// The widget is pure presentation — pass a list of intensities
/// (0..maxIntensity per cell) and it renders. Cells are laid out
/// column-by-column (one column = one week, top row = Monday).
///
/// Layout note: cells are aspect-ratio 1 within the available column width,
/// so the overall grid height is determined by parent width / weeks.
class ZActivityGrid extends StatelessWidget {
  const ZActivityGrid({
    super.key,
    required this.weeks,
    required this.intensities,
    this.maxIntensity = 4,
    this.gap = 4,
    this.color,
  });

  /// Number of week columns (typically 8).
  final int weeks;
  /// Flat array of intensities, length = weeks * 7. Index `wi * 7 + di`
  /// where wi is column (week) and di is row (day-of-week, 0 = Monday).
  /// Values clamped to [0, maxIntensity].
  final List<int> intensities;
  final int maxIntensity;
  final double gap;
  /// Defaults to [ZveltTokens.brand].
  final Color? color;

  /// Helper: build the [intensities] list from a Set of YMD dates the
  /// user trained on, ending at [endDate] (default today, local time).
  /// Density bucketed by simple session count per day:
  ///   0 = no session, 1 = 1 session, 2 = 2 sessions, 3 = 3, 4 = 4+.
  static List<int> fromTrainingDays({
    required int weeks,
    required Map<String, int> sessionsByYmd,
    DateTime? endDate,
  }) {
    final end = endDate ?? DateTime.now();
    // Anchor at the most recent Sunday so columns align to weeks Mon-Sun.
    final endMonday = end.subtract(Duration(days: (end.weekday - 1)));
    final out = List<int>.filled(weeks * 7, 0);
    for (var wi = 0; wi < weeks; wi++) {
      // wi = 0 is the OLDEST column on the left.
      final colMonday = endMonday.subtract(Duration(days: (weeks - 1 - wi) * 7));
      for (var di = 0; di < 7; di++) {
        final d = colMonday.add(Duration(days: di));
        final key = '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        final n = sessionsByYmd[key] ?? 0;
        out[wi * 7 + di] = n.clamp(0, 4);
      }
    }
    return out;
  }

  Color _cellColor(int v, Color brand) {
    switch (v) {
      case 0:
        return ZveltTokens.surface2;
      case 1:
        return brand.withValues(alpha: 0.18);
      case 2:
        return brand.withValues(alpha: 0.40);
      case 3:
        return brand.withValues(alpha: 0.70);
      default:
        return brand;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? ZveltTokens.brand;
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalGap = gap * (weeks - 1);
        final cellW = (constraints.maxWidth - totalGap) / weeks;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var wi = 0; wi < weeks; wi++) ...[
              if (wi > 0) SizedBox(width: gap),
              SizedBox(
                width: cellW,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var di = 0; di < 7; di++) ...[
                      if (di > 0) SizedBox(height: gap),
                      AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _cellColor(_intensityAt(wi, di), c),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  int _intensityAt(int wi, int di) {
    final idx = wi * 7 + di;
    if (idx < 0 || idx >= intensities.length) return 0;
    return intensities[idx].clamp(0, maxIntensity);
  }
}

/// Small legend strip shown under the grid — "Less" + 5 sample squares +
/// "More". Match the design's heatmap legend. Optional — most callers just
/// show the grid alone.
class ZActivityGridLegend extends StatelessWidget {
  const ZActivityGridLegend({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? ZveltTokens.brand;
    Color sample(int v) {
      switch (v) {
        case 0:
          return ZveltTokens.surface2;
        case 1:
          return c.withValues(alpha: 0.18);
        case 2:
          return c.withValues(alpha: 0.40);
        case 3:
          return c.withValues(alpha: 0.70);
        default:
          return c;
      }
    }
    Text label(String s) => Text(
          s,
          style: TextStyle(
            fontFamily: ZveltTokens.fontPrimary,
            fontSize: 11,
            color: ZveltTokens.text3,
          ),
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        label('Less'),
        Row(
          children: [
            for (var v = 0; v < 5; v++) ...[
              if (v > 0) const SizedBox(width: 3),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: sample(v),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ],
        ),
        label('More'),
      ],
    );
  }
}
