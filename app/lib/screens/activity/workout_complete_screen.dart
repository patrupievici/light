import 'dart:math' as math;
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import '../../models/workout_result.dart';
import '../../theme/zvelt_tokens.dart';
import 'activity_summary_screen.dart';

class WorkoutCompleteScreen extends StatefulWidget {
  final WorkoutResult result;

  const WorkoutCompleteScreen({super.key, required this.result});

  @override
  State<WorkoutCompleteScreen> createState() => _WorkoutCompleteScreenState();
}

class _WorkoutCompleteScreenState extends State<WorkoutCompleteScreen>
    with TickerProviderStateMixin {
  late final AnimationController _mainCtrl;
  late final AnimationController _confettiCtrl;
  late final AnimationController _progressCtrl;

  // Sub-animations
  late final Animation<double> _checkScale;
  late final Animation<double> _checkOpacity;
  late final Animation<double> _distanceCount;
  late final Animation<double> _xpSlide;
  late final Animation<double> _xpOpacity;
  late final Animation<double> _labelFade;

  static const _autoDuration = Duration(milliseconds: 3800);

  @override
  void initState() {
    super.initState();

    _mainCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _confettiCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _progressCtrl = AnimationController(vsync: this, duration: _autoDuration);

    _checkScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.0, 0.35, curve: Curves.elasticOut)),
    );
    _checkOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.0, 0.2, curve: Curves.easeIn)),
    );
    _distanceCount = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.25, 0.65, curve: Curves.easeOut)),
    );
    _xpSlide = Tween<double>(begin: 48.0, end: 0.0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.55, 0.85, curve: Curves.easeOutBack)),
    );
    _xpOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.55, 0.75, curve: Curves.easeIn)),
    );
    _labelFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.3, 0.55, curve: Curves.easeIn)),
    );

    _mainCtrl.forward();
    _progressCtrl.forward().then((_) {
      if (mounted) _navigateToSummary();
    });
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _confettiCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  void _navigateToSummary() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ActivitySummaryScreen(result: widget.result)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: GestureDetector(
        onTap: _navigateToSummary,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Confetti
            AnimatedBuilder(
              animation: _confettiCtrl,
              builder: (_, __) => CustomPaint(
                painter: _ConfettiPainter(progress: _confettiCtrl.value),
              ),
            ),

            // Main content
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CheckmarkCircle(scaleAnim: _checkScale, opacityAnim: _checkOpacity),
                  const SizedBox(height: ZveltTokens.s8),
                  FadeTransition(
                    opacity: _labelFade,
                    child: Text(
                      _completionLabel(),
                      style: ZType.h1,
                    ),
                  ),
                  const SizedBox(height: ZveltTokens.s2),
                  FadeTransition(
                    opacity: _labelFade,
                    child: Text(
                      widget.result.activityType.label,
                      style: ZType.bodyM.copyWith(color: ZveltTokens.text2),
                    ),
                  ),
                  const SizedBox(height: ZveltTokens.s10),

                  // Distance count-up (GPS only)
                  if (widget.result.activityType.isGps)
                    AnimatedBuilder(
                      animation: _distanceCount,
                      builder: (_, __) {
                        final km = (widget.result.distanceM / 1000) * _distanceCount.value;
                        return _BigStat(
                          value: km.toStringAsFixed(2),
                          unit: 'km',
                        );
                      },
                    )
                  else
                    AnimatedBuilder(
                      animation: _distanceCount,
                      builder: (_, __) {
                        final mins = widget.result.elapsed.inSeconds / 60 * _distanceCount.value;
                        return _BigStat(
                          value: mins.toStringAsFixed(0),
                          unit: 'min',
                        );
                      },
                    ),

                  const SizedBox(height: ZveltTokens.s8),

                  // XP badge
                  AnimatedBuilder(
                    animation: Listenable.merge([_xpSlide, _xpOpacity]),
                    builder: (_, __) => Transform.translate(
                      offset: Offset(0, _xpSlide.value),
                      child: Opacity(
                        opacity: _xpOpacity.value,
                        child: _XpBadge(xp: widget.result.xpEarned),
                      ),
                    ),
                  ),

                  if (widget.result.rankTierUnlocked != null) ...[
                    const SizedBox(height: ZveltTokens.s4),
                    AnimatedBuilder(
                      animation: _xpOpacity,
                      builder: (_, __) => Opacity(
                        opacity: _xpOpacity.value,
                        child: _RankUnlockedBanner(tier: widget.result.rankTierUnlocked!),
                      ),
                    ),
                  ],

                  const SizedBox(height: 60),
                ],
              ),
            ),

            // Bottom progress bar + tap-to-skip
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s6),
                    child: Text(
                      'Tap anywhere to continue',
                      style: ZType.bodyS.copyWith(
                        color: ZveltTokens.text2.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: ZveltTokens.s3),
                  AnimatedBuilder(
                    animation: _progressCtrl,
                    builder: (_, __) => LinearProgressIndicator(
                      value: _progressCtrl.value,
                      minHeight: 3,
                      backgroundColor: ZveltTokens.border,
                      valueColor: const AlwaysStoppedAnimation(ZveltTokens.brand),
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _completionLabel() {
    return switch (widget.result.activityType) {
      ActivityType.run => 'Run Complete!',
      ActivityType.walk => 'Walk Complete!',
      ActivityType.cycle => 'Ride Complete!',
      ActivityType.swim => 'Swim Complete!',
      ActivityType.hike => 'Hike Complete!',
      ActivityType.workout => 'Workout Done!',
    };
  }
}

class _CheckmarkCircle extends StatelessWidget {
  final Animation<double> scaleAnim;
  final Animation<double> opacityAnim;

  const _CheckmarkCircle({
    required this.scaleAnim,
    required this.opacityAnim,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([scaleAnim, opacityAnim]),
      builder: (_, __) => Opacity(
        opacity: opacityAnim.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: scaleAnim.value,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ZveltTokens.brand.withValues(alpha: 0.12),
              border: Border.all(color: ZveltTokens.brand.withValues(alpha: 0.4), width: 2),
            ),
            child: const Icon(
              AppIcons.check,
              color: ZveltTokens.brand,
              size: 52,
            ),
          ),
        ),
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  final String value;
  final String unit;

  const _BigStat({required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: ZType.num_.copyWith(
            fontSize: 64,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: ZveltTokens.s2),
        Padding(
          padding: const EdgeInsets.only(bottom: ZveltTokens.s2),
          child: Text(
            unit,
            style: ZType.h2.copyWith(
              fontWeight: FontWeight.w400,
              color: ZveltTokens.text2,
            ),
          ),
        ),
      ],
    );
  }
}

class _XpBadge extends StatelessWidget {
  final int xp;

  const _XpBadge({required this.xp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5, vertical: ZveltTokens.s2 + 2),
      decoration: BoxDecoration(
        color: ZveltTokens.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: ZveltTokens.brand.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.bolt, color: ZveltTokens.brand, size: 20),
          const SizedBox(width: ZveltTokens.s1 + 2),
          Text(
            '+$xp XP earned',
            style: ZType.h4.copyWith(
              fontWeight: FontWeight.w700,
              color: ZveltTokens.brand,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankUnlockedBanner extends StatelessWidget {
  final String tier;

  const _RankUnlockedBanner({required this.tier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s2),
      decoration: BoxDecoration(
        color: ZveltTokens.warn.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: ZveltTokens.warn.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.trophy, color: ZveltTokens.warn, size: 16),
          const SizedBox(width: ZveltTokens.s1 + 2),
          Text(
            'New rank: $tier',
            style: ZType.bodyM.copyWith(
              fontWeight: FontWeight.w600,
              color: ZveltTokens.warn,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Confetti Painter ────────────────────────────────────────────────────────

class _ConfettiPainter extends CustomPainter {
  final double progress;

  _ConfettiPainter({required this.progress});

  static final _rng = math.Random(42);
  static final _particles = List.generate(60, (i) => _Particle(_rng));

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      final t = (progress + p.offset) % 1.0;
      final x = p.startX * size.width;
      final y = t * size.height * 1.3 - size.height * 0.15;
      final opacity = t < 0.1 ? t / 0.1 : (t > 0.85 ? (1.0 - t) / 0.15 : 1.0);

      canvas.save();
      canvas.translate(x + math.sin(t * math.pi * 4 + p.phase) * 30, y);
      canvas.rotate(t * math.pi * 2 * p.spinDir);
      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity * 0.85)
        ..style = PaintingStyle.fill;

      if (p.isRect) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
            const Radius.circular(2),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

class _Particle {
  final double startX;
  final double offset;
  final double phase;
  final double size;
  final double spinDir;
  final Color color;
  final bool isRect;

  _Particle(math.Random rng)
      : startX = rng.nextDouble(),
        offset = rng.nextDouble(),
        phase = rng.nextDouble() * math.pi * 2,
        size = 6 + rng.nextDouble() * 8,
        spinDir = rng.nextBool() ? 1.0 : -1.0,
        isRect = rng.nextBool(),
        color = _kColors[rng.nextInt(_kColors.length)];

  static const _kColors = [
    ZveltTokens.brand,
    ZveltTokens.warn,
    ZveltTokens.success,
    ZveltTokens.info,
    Color(0xFFFFFFFF),
  ];
}
