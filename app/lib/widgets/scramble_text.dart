import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/settings_store.dart';

/// Decodare tip „matrix / hacker”: caractere aleatoare până se „blochează” textul final.
/// Inspirat din `scrambleText()` din anime.js — poate rula o dată sau în buclă.
class ScrambleText extends StatefulWidget {
  const ScrambleText({
    super.key,
    required this.text,
    this.style,
    this.loop = false,
    this.loopDelay = const Duration(seconds: 1),
    this.tick = const Duration(milliseconds: 36),
    this.charset = _kDefaultCharset,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.strutStyle,
  });

  final String text;
  final TextStyle? style;
  final bool loop;
  final Duration loopDelay;
  final Duration tick;

  /// Pool pentru caracterele „încă nedezvăluite”.
  final String charset;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final StrutStyle? strutStyle;

  static const String _kDefaultCharset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@#\$%&*';

  @override
  State<ScrambleText> createState() => _ScrambleTextState();
}

class _ScrambleTextState extends State<ScrambleText> {
  final Random _random = Random();
  Timer? _timer;
  int _reveal = 0;
  bool _holdingAfterComplete = false;

  @override
  void initState() {
    super.initState();
    if (AppPreferencesNotifier.reduceMotion.value) {
      _reveal = widget.text.length; // reduce motion: final text, no scramble
      return;
    }
    _startTicker(immediate: true);
  }

  @override
  void didUpdateWidget(covariant ScrambleText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.loop != widget.loop ||
        oldWidget.loopDelay != widget.loopDelay ||
        oldWidget.tick != widget.tick) {
      _timer?.cancel();
      _holdingAfterComplete = false;
      if (AppPreferencesNotifier.reduceMotion.value) {
        _reveal = widget.text.length; // reduce motion: jump to final text
        return;
      }
      _reveal = 0;
      _startTicker(immediate: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTicker({required bool immediate}) {
    _timer?.cancel();
    void schedule() {
      _timer = Timer.periodic(widget.tick, (_) => _onTick());
    }

    if (immediate) {
      schedule();
    } else {
      _timer = Timer(widget.loopDelay, schedule);
    }
  }

  void _onTick() {
    if (!mounted) return;

    final t = widget.text;
    final len = t.length;

    if (len == 0) {
      // Empty text = nothing to scramble. The old `setState(() {})` here
      // kept the 36ms timer ticking no-op rebuilds forever, burning
      // CPU/battery whenever a caller passed a not-yet-loaded string.
      _timer?.cancel();
      return;
    }

    if (_holdingAfterComplete) {
      return;
    }

    if (_reveal >= len) {
      if (!widget.loop) {
        _timer?.cancel();
        return;
      }
      _holdingAfterComplete = true;
      _timer?.cancel();
      _timer = Timer(widget.loopDelay, () {
        if (!mounted) return;
        setState(() {
          _reveal = 0;
          _holdingAfterComplete = false;
        });
        _startTicker(immediate: true);
      });
      return;
    }

    // Texte lungi: avans mai rapid ca să nu dureze minute.
    final remaining = len - _reveal;
    final step = remaining > 400
        ? 5
        : remaining > 160
            ? 3
            : remaining > 50
                ? 2
                : 1;

    setState(() {
      _reveal = (_reveal + step).clamp(0, len);
    });
  }

  String _visible() {
    final t = widget.text;
    final buf = StringBuffer();
    final charset = widget.charset;
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      final isWs = c == ' ' || c == '\n' || c == '\r' || c == '\t';
      if (isWs) {
        buf.write(c);
        continue;
      }
      if (i < _reveal) {
        buf.write(c);
      } else if (charset.isEmpty) {
        buf.write(c);
      } else {
        buf.write(charset[_random.nextInt(charset.length)]);
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _visible(),
      style: widget.style,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      strutStyle: widget.strutStyle,
      semanticsLabel: widget.text,
    );
  }
}
