import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';
import 'z_pressable.dart';

/// V2 card primitive — white surface, soft shadow, no border, 24px radius.
/// Mirrors the `.z-card` CSS class from the design bundle (tokens.css).
///
/// Use this everywhere instead of ad-hoc `Container(decoration: ...)` so the
/// look stays uniform across the app. Tap-aware variant via [onTap].
class ZCard extends StatelessWidget {
  const ZCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ZveltTokens.s4),
    this.margin,
    this.radius = ZveltTokens.rLg,
    this.color,
    this.shadow,
    this.onTap,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;

  /// Defaults to [ZveltTokens.surface] (white). Override only for special cases
  /// like tinted hero cards (see [ZveltTokens.surfaceTinted]).
  final Color? color;

  /// Defaults to [ZveltTokens.shadowCard]. Use [ZveltTokens.shadowHero] for
  /// the primary card on a screen.
  final List<BoxShadow>? shadow;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final decoration = BoxDecoration(
      color: color ?? ZveltTokens.surface,
      borderRadius: borderRadius,
      boxShadow: shadow ?? ZveltTokens.shadowCard,
    );

    Widget inner = Container(
      padding: padding,
      decoration: decoration,
      clipBehavior: clipBehavior,
      child: child,
    );

    if (onTap != null) {
      inner = ZPressable(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          child: inner,
        ),
      );
    }

    if (margin != null) {
      return Padding(padding: margin!, child: inner);
    }
    return inner;
  }
}
