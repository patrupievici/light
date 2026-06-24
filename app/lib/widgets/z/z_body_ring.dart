import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';

/// Circular progress ring with a value+unit in the center and a label
/// below. Mirrors `BodyRing` from screens-train.jsx — used in the Strain
/// / Recovery / Sleep hero row.
///
/// Visual: 60×60 ring (4px stroke) with a subtle track and a gradient
/// progress arc that starts at 12 o'clock and sweeps clockwise.
///
/// Domain-agnostic: pass any color pair + label. For the standard
/// biometric trio use the [strain] / [recovery] / [sleep] named ctors.
class ZBodyRing extends StatelessWidget {
  const ZBodyRing({
    super.key,
    required this.label,
    required this.value,
    this.unit = '%',
    this.valueText,
    required this.color,
    required this.trackColor,
    this.size = 60,
    this.stroke = 4,
    this.semanticsLabel,
  });

  /// 0..100 — clamped if out of range.
  final num value;
  final String label;
  final String unit;

  /// Optional display override for the center value (e.g. '–' for an
  /// honest no-data state). When null, `value.toInt()` renders.
  final String? valueText;
  /// Foreground gradient anchor color — e.g. [ZveltTokens.recovery].
  final Color color;
  /// Background-tint anchor color (subtler version of [color]) used both
  /// as the ring track and the gradient end-stop. Use the matching `*2`
  /// token (e.g. [ZveltTokens.recovery2]).
  final Color trackColor;
  final double size;
  final double stroke;

  /// Optional accessibility label announced by screen readers. When null,
  /// a label is derived from the value/unit and [label] already passed in.
  final String? semanticsLabel;

  /// Standard biometric ring presets — match the design's hero row.
  factory ZBodyRing.strain({Key? key, required num value}) => ZBodyRing(
        key: key,
        label: 'Strain',
        value: value,
        color: ZveltTokens.strain,
        trackColor: ZveltTokens.strain2,
      );

  factory ZBodyRing.recovery({Key? key, required num value}) => ZBodyRing(
        key: key,
        label: 'Recovery',
        value: value,
        color: ZveltTokens.recovery,
        trackColor: ZveltTokens.recovery2,
      );

  factory ZBodyRing.sleep({Key? key, required num value}) => ZBodyRing(
        key: key,
        label: 'Sleep',
        value: value,
        color: ZveltTokens.sleep,
        trackColor: ZveltTokens.sleep2,
      );

  @override
  Widget build(BuildContext context) {
    final pct = (value.toDouble() / 100).clamp(0.0, 1.0);
    final centerValue = valueText ?? '${value.toInt()}';
    final defaultSemantics = unit.isEmpty
        ? '$label $centerValue'
        : '$label $centerValue $unit';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Semantics(
                label: semanticsLabel ?? defaultSemantics,
                child: CustomPaint(
                  size: Size(size, size),
                  painter: _RingPainter(
                    progress: pct,
                    color: color,
                    trackColor: trackColor,
                    stroke: stroke,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    valueText ?? '${value.toInt()}',
                    style: ZType.stat.copyWith(
                      fontSize: 15,
                      color: ZveltTokens.text,
                    ),
                  ),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 1),
                    Text(
                      unit,
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
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: ZveltTokens.fontPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: ZveltTokens.text3,
            letterSpacing: 0.22,
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: r);

    // Track — full circle, subtle.
    final trackPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, r, trackPaint);

    if (progress <= 0) return;

    // Foreground — sweep gradient from color → trackColor along the arc,
    // 12 o'clock start, clockwise.
    final sweep = 2 * math.pi * progress;
    final foregroundPaint = Paint()
      ..shader = SweepGradient(
        colors: [color, trackColor],
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + 2 * math.pi,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, sweep, false, foregroundPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.stroke != stroke;
}

/// Convenience row showing the standard Strain / Recovery / Sleep triad,
/// laid out 3-up evenly spaced. Matches the BodyRings hero row in the
/// design's Train screen.
class ZBodyRingsRow extends StatelessWidget {
  const ZBodyRingsRow({
    super.key,
    required this.strainPct,
    required this.recoveryPct,
    required this.sleepPct,
  });

  final num strainPct;
  final num recoveryPct;
  final num sleepPct;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(child: Center(child: ZBodyRing.strain(value: strainPct))),
        Expanded(child: Center(child: ZBodyRing.recovery(value: recoveryPct))),
        Expanded(child: Center(child: ZBodyRing.sleep(value: sleepPct))),
      ],
    );
  }
}
