import 'dart:async';

import 'package:flutter/material.dart';

import '../services/settings_store.dart';

/// Reveal [text] left-to-right, **one new character per tick**, over [duration] (default 2s).
///
/// First character shows immediately; the last character appears at the end of [duration].
class TypewriterRevealText extends StatefulWidget {
  const TypewriterRevealText({
    super.key,
    required this.text,
    this.style,
    this.duration = const Duration(seconds: 2),
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.strutStyle,
  });

  final String text;
  final TextStyle? style;
  final Duration duration;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final StrutStyle? strutStyle;

  @override
  State<TypewriterRevealText> createState() => _TypewriterRevealTextState();
}

class _TypewriterRevealTextState extends State<TypewriterRevealText> {
  Timer? _timer;

  /// How many prefix characters from [widget.text] to show [0 … length].
  int _visible = 0;

  @override
  void initState() {
    super.initState();
    _startReveal();
  }

  @override
  void didUpdateWidget(covariant TypewriterRevealText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.duration != widget.duration) {
      _startReveal();
    }
  }

  void _startReveal() {
    _timer?.cancel();
    final t = widget.text;
    final n = t.length;
    if (n == 0) {
      setState(() => _visible = 0);
      return;
    }
    // Reduce motion: show the whole line at once, no typewriter.
    if (AppPreferencesNotifier.reduceMotion.value) {
      setState(() => _visible = n);
      return;
    }

    if (n == 1) {
      setState(() => _visible = 1);
      return;
    }

    final totalMicros = widget.duration.inMicroseconds.clamp(1, 864000000000);
    final between =
        Duration(microseconds: (totalMicros / (n - 1)).ceil().clamp(1, 864000000000));

    setState(() => _visible = 1);

    var revealed = 1;
    _timer = Timer.periodic(between, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      revealed++;
      setState(() {
        _visible = revealed >= n ? n : revealed;
      });
      if (revealed >= n) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.text;
    final k = _visible.clamp(0, t.length);
    final shown = k <= 0 ? '' : (k >= t.length ? t : t.substring(0, k));

    return Semantics(
      label: t,
      child: Text(
        shown,
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        strutStyle: widget.strutStyle,
      ),
    );
  }
}
