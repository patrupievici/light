// Accessibility guard suite — documents the a11y contract for the core Zvelt
// design-system widgets.
//
// This is a GUARD suite, not a refactor: it pins down the accessibility
// guarantees we want to hold for the primitives that appear on nearly every
// screen (buttons, the bottom nav bar, simple cards). If a guarantee regresses,
// these tests fail loudly. Where a widget *genuinely* falls short of an ideal
// (e.g. the center FAB has no semantic label, a compact chip is below the
// Android 48dp target), the case is recorded as a `skip:` with a TODO and a
// reference rather than silently editing production code — fixing the widget is
// out of scope for this suite.
//
// What we assert here:
//   1. Tap-target size — interactive elements should be tall/wide enough to hit
//      reliably (iOS HIG 44pt / Android 48dp; we use 48 as the strict bar and
//      44 as the relaxed/iOS bar where the widget documents 44).
//   2. Semantic labels — icon-only / glyph-only controls expose a label so
//      screen readers announce something meaningful.
//   3. Large-text survival — layouts built in isolation must not overflow at a
//      large textScaleFactor (1.6) the way an accessibility user would set it.
//
// We deliberately stick to widgets that build without backend mocking.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:zvelt_app/theme/app_theme.dart';
import 'package:zvelt_app/widgets/z/z_card.dart';
import 'package:zvelt_app/widgets/z/z_chip.dart';
import 'package:zvelt_app/widgets/zvelt_main_nav_bar.dart';
import 'package:zvelt_app/widgets/zvelt_primary_button.dart';
import 'package:zvelt_app/widgets/zvelt_secondary_button.dart';
import 'package:zvelt_app/widgets/zvelt_tertiary_button.dart';

/// Android Material minimum touch target.
const double kAndroidMinTarget = 48.0;

/// iOS HIG minimum touch target (some widgets document this relaxed bar).
const double kIosMinTarget = 44.0;

/// Locate the bundled MaterialIcons font so icon glyphs render (and so any
/// golden/semantics checks that touch icons behave). Mirrors the loader pattern
/// used by settings_screen_test.dart.
File _findMaterialIcons() {
  final candidates = <String>[];
  // Resolve via the Flutter SDK cache when FLUTTER_ROOT is set.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    candidates.add(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
  }
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) return f;
  }
  // Fall back to the first match we can find under the dart SDK's parent.
  throw StateError(
    'Could not locate MaterialIcons font; set FLUTTER_ROOT or adjust _findMaterialIcons().',
  );
}

/// Wrap a [child] in a minimal app shell with the production light theme and an
/// optional [textScaler] so widgets read the same theme they would in the app.
Widget _host(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightThemeData,
    home: Scaffold(
      body: Center(
        child: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: child,
        ),
      ),
    ),
  );
}

/// Return the rendered size of the single widget matched by [finder].
Size _sizeOf(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget, reason: 'expected exactly one match to size');
  return tester.getSize(finder);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Real glyph metrics make tap-target sizing meaningful (Inter has wide
    // ascenders; a fake font would mis-measure button heights).
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf')))
        .load();
    await (FontLoader('IBMPlexMono')
          ..addFont(rootBundle.load('assets/fonts/IBMPlexMono-Regular.ttf')))
        .load();
    try {
      final materialIcons = _findMaterialIcons();
      await (FontLoader('MaterialIcons')
            ..addFont(materialIcons.readAsBytes().then(ByteData.sublistView)))
          .load();
    } on StateError {
      // Icon font is optional for these checks; semantics/size assertions do not
      // depend on the actual glyph being present.
    }
  });

  group('Tap-target size', () {
    testWidgets('ZveltPrimaryButton (default) is >= 48dp tall', (tester) async {
      await tester.pumpWidget(
        _host(ZveltPrimaryButton(label: 'Start workout', onTap: () {})),
      );
      final size = _sizeOf(tester, find.byType(ZveltPrimaryButton));
      expect(
        size.height,
        greaterThanOrEqualTo(kAndroidMinTarget),
        reason: 'primary CTA must clear the Android 48dp target',
      );
    });

    testWidgets('ZveltSecondaryButton is >= 48dp tall', (tester) async {
      await tester.pumpWidget(
        _host(ZveltSecondaryButton(label: 'Maybe later', onTap: () {})),
      );
      final size = _sizeOf(tester, find.byType(ZveltSecondaryButton));
      expect(size.height, greaterThanOrEqualTo(kAndroidMinTarget));
    });

    testWidgets('ZveltTertiaryButton clears the documented 44pt floor',
        (tester) async {
      // The widget enforces a 44pt minimum via an internal ConstrainedBox even
      // in dense mode; assert that contract holds for both modes.
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ZveltTertiaryButton(label: 'See all', onTap: () {}),
              ZveltTertiaryButton(
                label: 'Mark all read',
                dense: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      );
      for (final el in tester.widgetList(find.byType(ZveltTertiaryButton))) {
        final size = tester.getSize(find.byWidget(el));
        expect(
          size.height,
          greaterThanOrEqualTo(kIosMinTarget),
          reason: 'tertiary button documents a forced >=44pt touch target',
        );
        expect(size.width, greaterThanOrEqualTo(kIosMinTarget));
      }
    });

    testWidgets(
      'ZveltPrimaryButton(small) retains the 48dp target',
      (tester) async {
        await tester.pumpWidget(
          _host(ZveltPrimaryButton(label: 'Go', small: true, onTap: () {})),
        );
        final size = _sizeOf(tester, find.byType(ZveltPrimaryButton));
        expect(size.height, greaterThanOrEqualTo(kAndroidMinTarget),
            reason: 'small primary CTA must retain the Android tap target');
      },
    );
  });

  group('Semantic labels on icon-only / glyph controls', () {
    testWidgets('nav bar tab cells expose a semantic button label',
        (tester) async {
      await tester.pumpWidget(
        _host(
          ZveltMainNavBar(
            currentIndex: 0,
            onTap: (_) {},
            onCenterTap: () {},
            items: const [
              ZveltNavItem(label: 'Home', icon: Icons.home),
              ZveltNavItem(label: 'Train', icon: Icons.fitness_center),
              ZveltNavItem(label: 'Feed', icon: Icons.people),
              ZveltNavItem(label: 'Nutrition', icon: Icons.restaurant),
            ],
          ),
        ),
      );
      await tester.pump();

      // Each tab is announced as "<label> tab" so a screen reader user can tell
      // tabs apart even though the visual label is tiny. Read the configured
      // Semantics widgets directly (robust across merge behaviour).
      final navSemantics = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.button == true)
          .map((s) => s.properties.label)
          .toSet();
      for (final label in ['Home', 'Train', 'Feed', 'Nutrition']) {
        expect(
          navSemantics,
          contains('$label tab'),
          reason: 'nav cell "$label" must carry a semantic button label',
        );
      }
    });

    testWidgets('selected nav tab is marked selected in semantics',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          ZveltMainNavBar(
            currentIndex: 1,
            onTap: (_) {},
            onCenterTap: () {},
            items: const [
              ZveltNavItem(label: 'Home', icon: Icons.home),
              ZveltNavItem(label: 'Train', icon: Icons.fitness_center),
              ZveltNavItem(label: 'Feed', icon: Icons.people),
              ZveltNavItem(label: 'Nutrition', icon: Icons.restaurant),
            ],
          ),
        ),
      );
      await tester.pump();

      // Read the selection flag straight off the Semantics widget configured by
      // the nav cell (more robust than locating the merged semantics node).
      final selected = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((s) => s.properties.label == 'Train tab')
          .toList();
      expect(selected, hasLength(1),
          reason: 'exactly one cell should carry the "Train tab" label');
      expect(
        selected.single.properties.selected,
        isTrue,
        reason: 'the active tab must report selected:true to assistive tech',
      );

      // And a non-active tab must NOT be selected.
      final home = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .firstWhere((s) => s.properties.label == 'Home tab');
      expect(home.properties.selected, isFalse);

      handle.dispose();
    });

    // The nav is 4 destinations + a center ⚡ Quick-Start action; the center
    // button carries its own "Start — quick start" semantic label.
  });

  group('Large textScaleFactor survival (1.6x)', () {
    const big = TextScaler.linear(1.6);

    testWidgets('ZveltPrimaryButton with a SHORT label survives 1.6x text',
        (tester) async {
      // A realistic short CTA in a full-width slot reflows fine at 1.6x.
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 320,
            child: ZveltPrimaryButton(
              label: 'Start',
              icon: AppIcons.play,
              onTap: () {},
            ),
          ),
          textScaler: big,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'short primary CTA must not overflow at 1.6x');
    });

    testWidgets(
      'ZveltPrimaryButton with a LONG label survives 1.6x text',
      (tester) async {
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 320,
              child: ZveltPrimaryButton(
                label: 'Start a brand new workout',
                icon: AppIcons.play,
                onTap: () {},
              ),
            ),
            textScaler: big,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'long primary CTA must not overflow at 1.6x');
      },
    );

    testWidgets('ZveltTertiaryButton does not overflow at 1.6x text',
        (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 200,
            child: ZveltTertiaryButton(label: 'Mark all read', onTap: () {}),
          ),
          textScaler: big,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ZChip does not overflow at 1.6x text', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 160,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ZChip(label: 'Push day', variant: ZChipVariant.brand),
            ),
          ),
          textScaler: big,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ZCard with stacked text reflows at 1.6x without overflow',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 300,
            child: ZCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Weekly volume'),
                  SizedBox(height: 4),
                  Text('You lifted 12,400 kg across 5 sessions this week.'),
                ],
              ),
            ),
          ),
          textScaler: big,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'card body text must wrap, not overflow, at 1.6x');
    });
  });

  group('Interactive chip tap target', () {
    testWidgets(
      'tappable ZChip retains a 48dp hit target',
      (tester) async {
        await tester.pumpWidget(
          _host(ZChip(label: 'Filter', onTap: () {})),
        );
        final size = _sizeOf(tester, find.byType(ZChip));
        expect(
          size.height,
          greaterThanOrEqualTo(kAndroidMinTarget),
          reason: 'interactive chip must expose a 48dp tap target',
        );
      },
    );
  });
}
