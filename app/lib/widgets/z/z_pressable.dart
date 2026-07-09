import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';

/// Small tactile wrapper for product UI press feedback.
///
/// It intentionally uses transform-only motion so it does not resize siblings
/// or disturb dense workout rows.
class ZPressable extends StatefulWidget {
  const ZPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.semanticLabel,
    this.selected,
    this.pressedScale = 0.985,
    this.borderRadius,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final String? semanticLabel;
  final bool? selected;
  final double pressedScale;
  final BorderRadius? borderRadius;
  final HitTestBehavior behavior;

  @override
  State<ZPressable> createState() => _ZPressableState();
}

class _ZPressableState extends State<ZPressable> {
  bool _pressed = false;

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _setPressed(bool value) {
    if (!_interactive || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Widget result = GestureDetector(
      behavior: widget.behavior,
      onTap: _interactive ? widget.onTap : null,
      onLongPress: _interactive ? widget.onLongPress : null,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed && !reduceMotion ? widget.pressedScale : 1,
        duration: reduceMotion ? Duration.zero : ZMotion.quick,
        curve: ZMotion.emphasized,
        child: widget.child,
      ),
    );

    if (widget.semanticLabel != null || widget.selected != null) {
      result = Semantics(
        button: _interactive,
        enabled: _interactive,
        selected: widget.selected,
        label: widget.semanticLabel,
        child: result,
      );
    }

    return result;
  }
}
