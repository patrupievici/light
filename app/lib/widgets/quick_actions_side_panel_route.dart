import 'package:flutter/material.dart';

/// Modal route: centered Quick actions sheet (fade + slight slide up).
class QuickActionsSlideRoute extends PageRouteBuilder<void> {
  QuickActionsSlideRoute({
    required this.builder,
  }) : super(
          opaque: false,
          barrierDismissible: true,
          barrierColor: Colors.black.withValues(alpha: 0.42),
          barrierLabel: 'Dismiss',
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 340),
          pageBuilder: (context, animation, secondaryAnimation) {
            return builder(context);
          },
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved =
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
            return SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
              child: FadeTransition(
                opacity: curved,
                child: child,
              ),
            );
          },
        );

  final WidgetBuilder builder;
}
