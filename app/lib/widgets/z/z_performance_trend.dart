import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../theme/zvelt_tokens.dart';
import 'z_card.dart';
import 'z_eyebrow.dart';

/// Headline performance trend card with full-width smooth area chart.
/// Mirrors `PerformanceTrend` from screens-train.jsx — the "Training load
/// · 30 days" panel with eyebrow, big stat, delta chip and the curve.
///
/// Domain-agnostic: pass any numeric series + label and it reads correct
/// (volume, e1RM, calories, HRV, etc.). The endpoint marker dot is drawn
/// in white-stroked brand so it pops on the gradient fill.
class ZPerformanceTrend extends StatelessWidget {
  const ZPerformanceTrend({
    super.key,
    required this.eyebrow,
    required this.value,
    required this.unit,
    required this.points,
    this.deltaPct,
    this.deltaLabel = 'improving',
    this.xLabels = const [],
    this.scopeLabel = '30D',
    this.onScopeTap,
    this.height = 160,
    this.color,
  });

  final String eyebrow;
  final String value;
  final String unit;
  final List<double> points;
  /// Signed percentage shown next to the stat (positive = recovery color,
  /// negative = stress color). Null hides the delta chip.
  final double? deltaPct;
  /// One-word qualifier after the % (e.g. "improving", "stable", "drop").
  final String deltaLabel;
  /// Optional date labels under the chart. Empty = no x-axis ticks.
  /// 3-5 labels recommended; first is left-anchored, last right-anchored,
  /// rest centered.
  final List<String> xLabels;
  final String scopeLabel;
  final VoidCallback? onScopeTap;
  /// Total card height (includes chart + header + labels).
  final double height;
  /// Defaults to [ZveltTokens.brand].
  final Color? color;

  Color get _deltaColor {
    if (deltaPct == null) return ZveltTokens.text3;
    return deltaPct! >= 0 ? ZveltTokens.success : ZveltTokens.error;
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? ZveltTokens.brand;
    return ZCard(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ZEyebrow(eyebrow),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          value,
                          style: ZType.stat.copyWith(
                            fontSize: 28,
                            color: ZveltTokens.text,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          unit,
                          style: TextStyle(
                            fontFamily: ZveltTokens.fontPrimary,
                            fontSize: 12,
                            color: ZveltTokens.text3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (deltaPct != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            deltaPct! >= 0
                                ? AppIcons.arrow_trend_up
                                : AppIcons.arrow_trend_down,
                            size: 13,
                            color: _deltaColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${deltaPct! >= 0 ? '+' : ''}${deltaPct!.toStringAsFixed(0)}% · $deltaLabel',
                            style: TextStyle(
                              fontFamily: ZveltTokens.fontPrimary,
                              fontSize: 12,
                              color: _deltaColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                onTap: onScopeTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: ZveltTokens.surface2,
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        scopeLabel,
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: ZveltTokens.text,
                        ),
                      ),
                      if (onScopeTap != null) ...[
                        const SizedBox(width: 4),
                        Icon(
                          AppIcons.angle_small_down,
                          size: 14,
                          color: ZveltTokens.text2,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: height - 100,
            child: Semantics(
              label: deltaPct != null
                  ? '$eyebrow, $value $unit, ${deltaPct!.toStringAsFixed(0)}% $deltaLabel'
                  : '$eyebrow, $value $unit',
              child: LayoutBuilder(
                builder: (context, c2) => CustomPaint(
                  size: Size(c2.maxWidth, c2.maxHeight),
                  painter: _TrendPainter(
                    points: points,
                    color: c,
                    xLabels: xLabels,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.points, required this.color, required this.xLabels});

  final List<double> points;
  final Color color;
  final List<String> xLabels;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    const padTop = 10.0;
    const padBottom = 22.0;
    const padX = 8.0;
    final innerW = size.width - padX * 2;
    final innerH = size.height - padTop - padBottom;

    final maxV = points.reduce((a, b) => a > b ? a : b);
    final minV = points.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs() < 0.0001 ? 1.0 : (maxV - minV);

    final coords = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = padX + (i / (points.length - 1)) * innerW;
      final norm = (points[i] - minV) / range;
      final y = padTop + (1 - norm) * innerH;
      coords.add(Offset(x, y));
    }

    // Smooth curve via Catmull-Rom cubic Bezier control points.
    final path = Path()..moveTo(coords.first.dx, coords.first.dy);
    for (var i = 1; i < coords.length; i++) {
      final p0 = i > 1 ? coords[i - 2] : coords[i - 1];
      final p1 = coords[i - 1];
      final p2 = coords[i];
      final p3 = i < coords.length - 1 ? coords[i + 1] : coords[i];
      final cp1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final cp2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }

    // Area fill with gradient (brand 22% → 0%).
    final areaPath = Path.from(path)
      ..lineTo(coords.last.dx, padTop + innerH)
      ..lineTo(coords.first.dx, padTop + innerH)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
      ).createShader(Rect.fromLTWH(0, padTop, size.width, innerH));
    canvas.drawPath(areaPath, fillPaint);

    // Line itself.
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Endpoint marker — white-stroked brand circle.
    final last = coords.last;
    canvas.drawCircle(last, 4.5, Paint()..color = color);
    canvas.drawCircle(
      last,
      4.5,
      Paint()
        ..color = ZveltTokens.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // X-axis labels — first left-anchored, last right-anchored + bold,
    // rest centered.
    if (xLabels.isNotEmpty) {
      for (var i = 0; i < xLabels.length; i++) {
        final isLast = i == xLabels.length - 1;
        final isFirst = i == 0;
        final x = padX + (i / (xLabels.length - 1)) * innerW;
        final tp = TextPainter(
          text: TextSpan(
            text: xLabels[i],
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontSize: 11,
              fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
              color: isLast ? ZveltTokens.text : ZveltTokens.text3,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        double dx;
        if (isFirst) {
          dx = x;
        } else if (isLast) {
          dx = x - tp.width;
        } else {
          dx = x - tp.width / 2;
        }
        tp.paint(canvas, Offset(dx, size.height - tp.height - 4));
      }
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.color != color || old.xLabels != xLabels;
}
