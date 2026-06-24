import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';

/// Subtle 30/60-day trend sparkline. Two modes:
///   - line (default): smooth area-fill polyline (ideal for cumulative metrics)
///   - bar: vertical bars (ideal for daily quantities like volume/calories)
///
/// Used by [ZCleanStatCard] and standalone in card footers. Stays low-noise
/// per design-system §6 ("thin strokes, soft gradient fills, no glow").
class ZSparkline extends StatelessWidget {
  const ZSparkline({
    super.key,
    required this.values,
    this.color,
    this.width = 140,
    this.height = 28,
    this.bars = false,
    this.fill = true,
    this.strokeWidth = 2.0,
  });

  final List<double> values;
  /// Defaults to [ZveltTokens.brand].
  final Color? color;
  final double width;
  final double height;
  /// True draws vertical bars; false draws a smooth line.
  final bool bars;
  /// For line mode only — soft gradient area-fill under the curve.
  final bool fill;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(width: width, height: height);
    }
    final c = color ?? ZveltTokens.brand;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: bars
            ? _BarSparklinePainter(values: values, color: c)
            : _LineSparklinePainter(
                values: values,
                color: c,
                fill: fill,
                strokeWidth: strokeWidth,
              ),
      ),
    );
  }
}

class _LineSparklinePainter extends CustomPainter {
  _LineSparklinePainter({
    required this.values,
    required this.color,
    required this.fill,
    required this.strokeWidth,
  });

  final List<double> values;
  final Color color;
  final bool fill;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV).abs() < 0.0001 ? 1.0 : (maxV - minV);

    final w = size.width;
    final h = size.height;
    final n = values.length;
    final stepX = w / (n - 1);

    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final x = i * stepX;
      // Map value to vertical position — top = high value, bottom = low.
      // Padding: 2px top/bottom to keep stroke visible at extremes.
      final norm = (values[i] - minV) / range;
      final y = h - 2 - norm * (h - 4);
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      // Catmull-Rom-ish smoothing via control points for a calm curve.
      final p0 = i > 1 ? points[i - 2] : points[i - 1];
      final p1 = points[i - 1];
      final p2 = points[i];
      final p3 = i < points.length - 1 ? points[i + 1] : points[i];
      final cp1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final cp2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }

    if (fill) {
      final areaPath = Path.from(path)
        ..lineTo(points.last.dx, h)
        ..lineTo(points.first.dx, h)
        ..close();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size);
      canvas.drawPath(areaPath, fillPaint);
    }

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_LineSparklinePainter old) =>
      old.values != values || old.color != color || old.fill != fill || old.strokeWidth != strokeWidth;
}

class _BarSparklinePainter extends CustomPainter {
  _BarSparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return;

    final w = size.width;
    final h = size.height;
    final n = values.length;
    // 1px gap between bars, evenly distribute the rest.
    const gap = 1.0;
    final totalGap = gap * (n - 1);
    final barW = ((w - totalGap) / n).clamp(1.0, 12.0);

    final paint = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      final x = i * (barW + gap);
      final v = values[i];
      final barH = (v / maxV) * (h - 1); // 1px headroom
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, h - barH, barW, barH),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_BarSparklinePainter old) =>
      old.values != values || old.color != color;
}
