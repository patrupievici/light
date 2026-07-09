import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';
import 'z_card.dart';

class ZSkeletonBox extends StatefulWidget {
  const ZSkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.radius = ZveltTokens.rMd,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  State<ZSkeletonBox> createState() => _ZSkeletonBoxState();
}

class _ZSkeletonBoxState extends State<ZSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final base = ZveltTokens.surface2;
    final highlight = ZveltTokens.surface3.withValues(alpha: 0.55);

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(decoration: BoxDecoration(color: base)),
            if (!reduceMotion)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final x = (_controller.value * 2.4) - 1.2;
                  return FractionalTranslation(
                    translation: Offset(x, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: 0.42,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                base.withValues(alpha: 0),
                                highlight,
                                base.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class ZPageSkeleton extends StatelessWidget {
  const ZPageSkeleton({
    super.key,
    this.padding,
    this.itemCount = 4,
    this.showHeader = true,
  });

  final EdgeInsetsGeometry? padding;
  final int itemCount;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding ??
          EdgeInsets.fromLTRB(
            ZveltTokens.screenPaddingH,
            MediaQuery.paddingOf(context).top + ZveltTokens.s4,
            ZveltTokens.screenPaddingH,
            ZveltTokens.s8,
          ),
      children: [
        if (showHeader) ...[
          const Row(
            children: [
              ZSkeletonBox(width: 132, height: 28, radius: 8),
              Spacer(),
              ZSkeletonBox(width: 44, height: 44, radius: ZveltTokens.rPill),
            ],
          ),
          const SizedBox(height: ZveltTokens.s5),
        ],
        for (var i = 0; i < itemCount; i++) ...[
          ZCard(
            padding: const EdgeInsets.all(ZveltTokens.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ZSkeletonBox(
                  height: 16,
                  width: i.isEven ? 156 : 112,
                  radius: 7,
                ),
                const SizedBox(height: ZveltTokens.s3),
                const ZSkeletonBox(height: 12, radius: 6),
                const SizedBox(height: ZveltTokens.s2),
                ZSkeletonBox(
                  height: 12,
                  width: MediaQuery.sizeOf(context).width * 0.48,
                  radius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(height: ZveltTokens.s3),
        ],
      ],
    );
  }
}
