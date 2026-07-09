import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/zvelt_tokens.dart';
import '../services/settings_store.dart';

/// Full-screen 3 · 2 · 1 start countdown — the same animation used before a
/// workout starts (elastic-scaling italic number with an accent glow). Fires
/// [onComplete] after the "1", or [onCancel] if the user backs out.
class StartCountdown extends StatefulWidget {
  const StartCountdown({
    super.key,
    required this.onComplete,
    this.onCancel,
    this.title,
    this.accent = ZveltTokens.brand,
  });

  final VoidCallback onComplete;
  final VoidCallback? onCancel;
  final String? title;
  final Color accent;

  @override
  State<StartCountdown> createState() => _StartCountdownState();
}

class _StartCountdownState extends State<StartCountdown> with SingleTickerProviderStateMixin {
  int _value = 3;
  Timer? _timer;
  bool _done = false;
  late final AnimationController _scale;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..forward(from: 0);
    // Reduce motion (Settings → Reduce motion): skip the 3·2·1 entirely and
    // start immediately, so the animation is never forced on the user.
    if (AppPreferencesNotifier.reduceMotion.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _done) return;
        _done = true;
        widget.onComplete();
      });
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_value > 1) {
        setState(() {
          _value--;
          _scale.forward(from: 0);
        });
      } else {
        t.cancel();
        if (!_done) {
          _done = true;
          widget.onComplete();
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce motion: render nothing for the single frame before onComplete fires
    // (no giant bouncing "3" flash).
    if (AppPreferencesNotifier.reduceMotion.value) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [widget.accent.withValues(alpha: 0.25), ZveltTokens.bg],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.title != null) ...[
                Text(
                  widget.title!,
                  style: ZType.monoS.copyWith(
                    color: ZveltTokens.text2,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: ZveltTokens.s2),
              ],
              Text(
                'Starting in',
                style: ZType.bodyS
                    .copyWith(color: ZveltTokens.text2.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: ZveltTokens.s10),
              ScaleTransition(
                scale: CurvedAnimation(parent: _scale, curve: Curves.elasticOut),
                child: Text(
                  '$_value',
                  style: ZType.display.copyWith(
                    fontStyle: FontStyle.italic,
                    fontSize: 200,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                    height: 0.9,
                    // Dark-theme leftover: white-on-#F6F7F5 was ~1.05:1 —
                    // the digit was legible only through its glow.
                    color: ZveltTokens.text,
                    shadows: [
                      Shadow(color: widget.accent.withValues(alpha: 0.7), blurRadius: 60),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 80),
              TextButton(
                onPressed: () {
                  _timer?.cancel();
                  if (widget.onCancel != null) {
                    widget.onCancel!();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
                child: Text(
                  'Cancel',
                  style: ZType.bodyM
                      .copyWith(color: ZveltTokens.text2.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
