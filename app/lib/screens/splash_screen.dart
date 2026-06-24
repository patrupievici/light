import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/zvelt_tokens.dart';

/// Splash (brief §6.1, mockup 1): ZVELT wordmark on a dark field with the
/// "Train. Track. Compete." tagline. Short by design — if [onDone] is given it
/// fires after [hold] (≤ ~1.2s) so the flow can advance.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onDone, this.hold = const Duration(milliseconds: 1100)});

  final VoidCallback? onDone;
  final Duration hold;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  // Dark palette from the brief — the splash is always dark regardless of theme.
  static const Color _bg = Color(0xFF11100E);

  @override
  void initState() {
    super.initState();
    if (widget.onDone != null) {
      _timer = Timer(widget.hold, () {
        if (mounted) widget.onDone!();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Wordmark — "ZVELT" with the V tinted in the brand orange.
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 48,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
                children: [
                  TextSpan(text: 'Z'),
                  TextSpan(text: 'V', style: TextStyle(color: ZveltTokens.brand)),
                  TextSpan(text: 'ELT'),
                ],
              ),
            ),
            const SizedBox(height: ZveltTokens.s4),
            Text(
              'TRAIN. TRACK. COMPETE.',
              style: TextStyle(
                fontFamily: ZveltTokens.fontMono,
                fontWeight: FontWeight.w500,
                fontSize: 11,
                letterSpacing: 3,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
