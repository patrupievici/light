import 'package:flutter/material.dart';

import 'zvelt_theme_notifier.dart';
import 'zvelt_tokens.dart';

/// Rebuilds token-driven UI when the selected appearance changes.
///
/// Zvelt's neutral colors are runtime getters rather than ThemeExtensions, so
/// screens using them need an explicit listener while keeping their State.
class ZveltThemeRebuilder extends StatelessWidget {
  const ZveltThemeRebuilder({
    super.key,
    required this.builder,
  });

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ZveltThemeNotifier.mode,
      builder: (context, mode, _) {
        final platformDark = (MediaQuery.maybeOf(context)?.platformBrightness ??
                WidgetsBinding
                    .instance.platformDispatcher.platformBrightness) ==
            Brightness.dark;
        ZveltTokens.isDark = switch (mode) {
          ThemeMode.dark => true,
          ThemeMode.light => false,
          ThemeMode.system => platformDark,
        };
        return builder(context);
      },
    );
  }
}
