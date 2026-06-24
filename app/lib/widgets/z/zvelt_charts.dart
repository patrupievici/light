import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';

// Shared animated chart widgets (area / bar / ring / mini-line), extracted
// from progress_hub_screen.dart so detail screens can reuse them without a
// circular import.

// ─── Animated Area Chart ────────────────────────────────────────────────────

class ZveltAreaChart extends StatefulWidget {
  const ZveltAreaChart({
    super.key,
    required this.points,
    this.color = ZveltTokens.brand,
    this.height = 110.0,
    this.xLabels = const [],
    this.delay = Duration.zero,
  });

  final List<double> points;
  final Color color;
  final double height;
  final List<String> xLabels;
  final Duration delay;

  @override
  State<ZveltAreaChart> createState() => _ZveltAreaChartState();
}

class _ZveltAreaChartState extends State<ZveltAreaChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => CustomPaint(
            size: Size(double.infinity, widget.height),
            painter: _AreaPainter(
              points: widget.points,
              color: widget.color,
              progress: _anim.value,
            ),
          ),
        ),
        if (widget.xLabels.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: widget.xLabels
                .map((l) => Text(l,
                    style: TextStyle(
                        fontFamily: ZveltTokens.fontMono,
                        fontSize: 11, color: ZveltTokens.text3, fontWeight: FontWeight.w500)))
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({required this.points, required this.color, required this.progress});
  final List<double> points;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final double mx = points.reduce(math.max);
    final double mn = points.reduce(math.min);
    final double rng = mx == mn ? 1 : mx - mn;
    const double padX = 6, padY = 8;
    final int n = points.length;

    List<Offset> pts = List.generate(n, (i) {
      final x = padX + i / (n - 1) * (size.width - padX * 2);
      final y = padY + (1 - (points[i] - mn) / rng) * (size.height - padY * 2);
      return Offset(x, y);
    });

    // Grid lines — dark hairlines on light bg
    final gridPaint = Paint()
      ..color = ZveltTokens.hairline
      ..strokeWidth = 1;
    for (final frac in [0.25, 0.5, 0.75]) {
      final y = padY + frac * (size.height - padY * 2);
      canvas.drawLine(Offset(padX, y), Offset(size.width - padX, y), gridPaint);
    }

    // Build path clipped to progress
    final clipWidth = size.width * progress;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, clipWidth, size.height));

    // Fill
    final fillPath = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < n; i++) {
      fillPath.lineTo(pts[i].dx, pts[i].dy);
    }
    fillPath
      ..lineTo(pts[n - 1].dx, size.height - 2)
      ..lineTo(pts[0].dx, size.height - 2)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill,
    );

    // Stroke
    final linePath = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < n; i++) {
      linePath.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.restore();

    // End dot (fades in after progress > 0.9)
    if (progress > 0.9) {
      final last = pts[n - 1];
      final alpha = ((progress - 0.9) / 0.1).clamp(0.0, 1.0);
      canvas.drawCircle(last, 8, Paint()..color = color.withValues(alpha: 0.25 * alpha));
      canvas.drawCircle(last, 4, Paint()..color = color.withValues(alpha: alpha));
    }
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.progress != progress ||
      old.points != points ||
      old.color != color;
}

// ─── Animated Bar Chart ──────────────────────────────────────────────────────

class ZveltBarChart extends StatefulWidget {
  const ZveltBarChart({
    super.key,
    required this.data,
    this.height = 130.0,
    this.labels = const [],
    this.activeIdx = -1,
    this.delay = Duration.zero,
  });

  final List<double> data;
  final double height;
  final List<String> labels;
  final int activeIdx;
  final Duration delay;

  @override
  State<ZveltBarChart> createState() => _ZveltBarChartState();
}

class _ZveltBarChartState extends State<ZveltBarChart> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  // One staggered Animation<double> per bar, precomputed once (not rebuilt
  // every frame inside the AnimatedBuilder). Rebuilt only when the bar count
  // changes (didUpdateWidget).
  late List<Animation<double>> _barAnims;

  // Builds an elastic, staggered Interval animation for each bar. Mirrors the
  // previous per-frame CurvedAnimation math exactly, so visuals are unchanged.
  void _buildBarAnims() {
    final int n = widget.data.length;
    _barAnims = List.generate(n, (i) {
      final stagger = (i / n * 0.5).clamp(0.0, 0.5);
      return CurvedAnimation(
        parent: _ctrl,
        curve: Interval(stagger, (stagger + 0.5).clamp(0.0, 1.0),
            curve: Curves.elasticOut),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _buildBarAnims();
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void didUpdateWidget(ZveltBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.length != widget.data.length) {
      _buildBarAnims();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Bars scale to the SERIES MAX, not to a hardcoded 0–100 range. The old
    // `pct / 100` assumed percent inputs; callers pass raw values (kg volume,
    // kcal…), so a 8,700 kg day rendered an ~12,000px bar — the "endless
    // gray box" you could scroll forever under the Training tab.
    final maxV = widget.data.isEmpty
        ? 0.0
        : widget.data.reduce((a, b) => a > b ? a : b);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Column(
        children: [
          SizedBox(
            height: widget.height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(widget.data.length, (i) {
                final frac = maxV > 0
                    ? (widget.data[i] / maxV).clamp(0.0, 1.0)
                    : 0.0;
                final isActive = i == widget.activeIdx;
                final animVal = _barAnims[i].value;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3.5),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        height: widget.height * frac * animVal,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(3)),
                          color: isActive
                              ? ZveltTokens.brand
                              : ZveltTokens.brand.withValues(alpha: 0.22),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          if (widget.labels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: List.generate(widget.labels.length, (i) {
                final isActive = i == widget.activeIdx;
                return Expanded(
                  child: Text(
                    widget.labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontMono,
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive ? ZveltTokens.brand : ZveltTokens.text3,
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Animated Ring Chart ────────────────────────────────────────────────────

class ZveltRingChart extends StatefulWidget {
  const ZveltRingChart({
    super.key,
    required this.value,
    this.size = 80.0,
    this.strokeWidth = 7.0,
    this.color,
    this.delay = Duration.zero,
    this.label,
  });

  final double value; // 0–100
  final double size;
  final double strokeWidth;
  final Color? color;
  final Duration delay;
  final String? label;

  @override
  State<ZveltRingChart> createState() => _ZveltRingChartState();
}

class _ZveltRingChartState extends State<ZveltRingChart> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _RingPainter(
                value: widget.value * _anim.value.clamp(0.0, 1.0),
                strokeWidth: widget.strokeWidth,
                color: widget.color ?? ZveltTokens.brand,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(widget.value * _anim.value.clamp(0.0, 1.0)).round()}',
                  style: ZType.stat.copyWith(
                    fontSize: widget.size * 0.23,
                    color: ZveltTokens.text,
                  ),
                ),
                if (widget.label != null)
                  Text(
                    widget.label!,
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontMono,
                      fontSize: widget.size * 0.12,
                      color: ZveltTokens.text3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.strokeWidth, required this.color});
  final double value;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track — V2 muted surface3 (cream-on-cream)
    canvas.drawCircle(
      center, radius,
      Paint()
        ..color = ZveltTokens.surface3
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Fill arc — solid brand stroke (no gradient per V2 §7 "avoid aggressive gradients")
    final sweepAngle = 2 * math.pi * (value / 100);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

// ─── Mini Line Chart ─────────────────────────────────────────────────────────

class ZveltMiniLine extends StatefulWidget {
  const ZveltMiniLine({
    super.key,
    required this.points,
    this.width = 100.0,
    this.height = 28.0,
    this.color = ZveltTokens.brand,
  });

  final List<double> points;
  final double width;
  final double height;
  final Color color;

  @override
  State<ZveltMiniLine> createState() => _ZveltMiniLineState();
}

class _ZveltMiniLineState extends State<ZveltMiniLine> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => CustomPaint(
        size: Size(widget.width, widget.height),
        painter: _LinePainter(
          points: widget.points,
          color: widget.color,
          progress: _anim.value,
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.points, required this.color, required this.progress});
  final List<double> points;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final mx = points.reduce(math.max);
    final mn = points.reduce(math.min);
    final rng = mx == mn ? 1.0 : mx - mn;
    const pad = 3.0;
    final n = points.length;

    final pts = List.generate(n, (i) {
      final x = pad + i / (n - 1) * (size.width - pad * 2);
      final y = pad + (1 - (points[i] - mn) / rng) * (size.height - pad * 2);
      return Offset(x, y);
    });

    // Area fill
    final area = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < n; i++) {
      area.lineTo(pts[i].dx, pts[i].dy);
    }
    area..lineTo(pts[n - 1].dx, size.height)..lineTo(pts[0].dx, size.height)..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.4), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Clip to progress
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < n; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    if (progress > 0.85) {
      final last = pts[n - 1];
      canvas.drawCircle(last, 3.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.progress != progress ||
      old.points != points ||
      old.color != color;
}

