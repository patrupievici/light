import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zvelt_app/screens/analytics/progress_hub_screen.dart';

// Guards the lazy-build tab contract added for the Progress-hub lag fix. The
// tab host is a keyed Stack whose children are Offstage(...) for BUILT tabs and
// const SizedBox.shrink() for not-yet-visited tabs, with exactly one Offstage
// onstage at a time. Asserting those child types makes the test fail if a
// future edit eager-builds all tabs or drops the Offstage/lazy wrapper —
// not just on a crash. Uses fixed pump() (never pumpAndSettle) because the
// coach-read shimmer repeats forever; offline initState calls fail fast.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('only visited sub-tabs are built; exactly one is onstage',
      (tester) async {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: ProgressHubScreen()));
    await tester.pump(const Duration(milliseconds: 200));

    Stack hubStack() => tester
        .widget<Stack>(find.byKey(const ValueKey('progress_tab_stack')));
    int built() => hubStack().children.whereType<Offstage>().length;
    int lazy() => hubStack().children.whereType<SizedBox>().length;
    int onstage() => hubStack()
        .children
        .whereType<Offstage>()
        .where((o) => !o.offstage)
        .length;

    // Light redesign: 3 tabs (Workouts/Nutrition/Body) — Health/Biology stripped.
    // Up front: only Workouts (index 0) is built; the other 2 are lazy.
    expect(built(), 1, reason: 'only the first tab should be built on open');
    expect(lazy(), 2, reason: 'the other 2 tabs must be SizedBox.shrink()');
    expect(onstage(), 1, reason: 'exactly one tab is visible');

    // Visiting each remaining tab builds it (and earlier-built tabs stay built).
    for (final label in const ['Nutrition', 'Body']) {
      await tester.tap(find.text(label).first);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull,
          reason: 'switching to $label threw');
    }
    expect(built(), 3, reason: 'all visited tabs stay mounted (kept alive)');
    expect(lazy(), 0);
    expect(onstage(), 1, reason: 'still exactly one visible after switching');
  });
}
