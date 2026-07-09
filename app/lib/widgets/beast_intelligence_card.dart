import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import '../theme/zvelt_tokens.dart';

class BeastIntelligenceCard extends StatefulWidget {
  final String insight;
  final List<String> tags;
  final bool loading;

  const BeastIntelligenceCard({
    super.key,
    required this.insight,
    this.tags = const [],
    this.loading = false,
  });

  @override
  State<BeastIntelligenceCard> createState() => _BeastIntelligenceCardState();
}

class _BeastIntelligenceCardState extends State<BeastIntelligenceCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ZveltTokens.brandTint,
            ZveltTokens.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        border: Border.all(
          color: ZveltTokens.brand.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: ZveltTokens.brand.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(AppIcons.bolt, size: 16, color: ZveltTokens.brand),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Beast Intelligence',
                      style: ZType.bodyS.copyWith(
                        color: ZveltTokens.brand,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (widget.loading) ...[
                      const Spacer(),
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: ZveltTokens.brand.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if (widget.loading)
                  _ShimmerLines()
                else
                  _InsightText(
                    text: widget.insight,
                    expanded: _expanded,
                    fadeAnim: _fadeAnim,
                  ),
                if (!widget.loading && widget.insight.length > 120) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _toggle,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _expanded ? 'Show less' : 'Say more',
                          style: ZType.bodyS.copyWith(
                            color: ZveltTokens.brand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 250),
                          child: const Icon(
                            AppIcons.angle_small_down,
                            color: ZveltTokens.brand,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.tags.isNotEmpty) ...[
            Container(
              height: 1,
              color: ZveltTokens.brand.withValues(alpha: 0.1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: widget.tags
                    .map((tag) => _TagChip(label: tag))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightText extends StatelessWidget {
  final String text;
  final bool expanded;
  final Animation<double> fadeAnim;

  const _InsightText({
    required this.text,
    required this.expanded,
    required this.fadeAnim,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Text(
        text,
        maxLines: expanded ? null : 3,
        overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        style: ZType.bodyM.copyWith(
          color: ZveltTokens.text.withValues(alpha: 0.9),
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;

  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ZveltTokens.brand.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: ZveltTokens.brand.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: ZType.bodyS.copyWith(
          fontSize: 12,
          color: ZveltTokens.brand,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ShimmerLines extends StatefulWidget {
  @override
  State<_ShimmerLines> createState() => _ShimmerLinesState();
}

class _ShimmerLinesState extends State<_ShimmerLines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final shimmerColor = Color.lerp(
          ZveltTokens.surface2,
          ZveltTokens.surface3,
          _anim.value,
        )!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _line(shimmerColor, double.infinity),
            const SizedBox(height: 6),
            _line(shimmerColor, double.infinity),
            const SizedBox(height: 6),
            _line(shimmerColor, 180),
          ],
        );
      },
    );
  }

  Widget _line(Color color, double width) => Container(
        height: 13,
        width: width,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
        ),
      );
}
