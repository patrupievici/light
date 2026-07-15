import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/theme/zvelt_theme_notifier.dart';
import 'package:zvelt_app/theme/zvelt_theme_rebuilder.dart';
import 'package:zvelt_app/theme/zvelt_tokens.dart';
import 'package:zvelt_app/widgets/zvelt_lazy_indexed_stack.dart';

void main() {
  testWidgets('theme changes rebuild mounted tabs without losing their state',
      (tester) async {
    final previousMode = ZveltThemeNotifier.mode.value;
    ZveltThemeNotifier.mode.value = ThemeMode.dark;
    addTearDown(() {
      ZveltThemeNotifier.mode.value = previousMode;
      ZveltTokens.isDark = true;
    });

    var lazyPageBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ZveltThemeRebuilder(
          builder: (context) {
            return ZveltLazyIndexedStack(
              index: 0,
              built: const [true, false],
              itemBuilder: (context, index) {
                if (index == 0) return _ThemeProbe();
                lazyPageBuilds++;
                return const Text('Lazy page');
              },
            );
          },
        ),
      ),
    );

    expect(find.text('0 / dark'), findsOneWidget);
    expect(find.text('Lazy page'), findsNothing);
    expect(lazyPageBuilds, 0);

    await tester.tap(find.byKey(const ValueKey('theme_probe_button')));
    await tester.pump();
    expect(find.text('1 / dark'), findsOneWidget);

    ZveltThemeNotifier.mode.value = ThemeMode.light;
    await tester.pump();

    expect(find.text('1 / light'), findsOneWidget);
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const ValueKey('theme_probe_surface')))
          .color,
      const Color(0xFFF6F1E9),
    );
    expect(lazyPageBuilds, 0);
  });
}

class _ThemeProbe extends StatefulWidget {
  @override
  State<_ThemeProbe> createState() => _ThemeProbeState();
}

class _ThemeProbeState extends State<_ThemeProbe> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('theme_probe_surface'),
      color: ZveltTokens.bg,
      child: Center(
        child: TextButton(
          key: const ValueKey('theme_probe_button'),
          onPressed: () => setState(() => _taps++),
          child: Text('$_taps / ${ZveltTokens.isDark ? 'dark' : 'light'}'),
        ),
      ),
    );
  }
}
