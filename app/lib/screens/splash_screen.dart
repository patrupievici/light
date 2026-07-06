import 'dart:async';

import 'package:flutter/material.dart';

/// Splash screen. Short by design: if [onDone] is given it fires after [hold]
/// so the flow can advance without making launch feel slow.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onDone, this.hold = const Duration(milliseconds: 1100)});

  final VoidCallback? onDone;
  final Duration hold;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  // Dark fallback behind the splash art.
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
    return const Scaffold(
      backgroundColor: _bg,
      body: SizedBox.expand(
        child: Image(
          image: AssetImage('assets/images/zvelt_splash.png'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
    );
  }
}
