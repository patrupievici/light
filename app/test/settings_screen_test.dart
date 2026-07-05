import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zvelt_app/screens/settings/settings_screen.dart';
import 'package:zvelt_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf')))
        .load();
    await (FontLoader('IBMPlexMono')
          ..addFont(rootBundle.load('assets/fonts/IBMPlexMono-Regular.ttf')))
        .load();
    final materialIcons = _findMaterialIcons();
    await (FontLoader('MaterialIcons')
          ..addFont(materialIcons.readAsBytes().then(ByteData.sublistView)))
        .load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    Size size = const Size(480, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightThemeData,
        home: SettingsScreen(
          preview: true,
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('settings root matches the approved first viewport',
      (tester) async {
    await pumpSettings(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_root.png'),
    );
  });

  testWidgets('all settings groups are reachable by scrolling', (tester) async {
    await pumpSettings(tester);
    final list = find.byType(Scrollable).first;
    for (final label in <String>[
      'Training',
      'Notifications',
      'Privacy & Social',
      'Subscription',
      'Support',
      'Log out'
    ]) {
      for (var attempt = 0;
          attempt < 12 && find.text(label).evaluate().isEmpty;
          attempt++) {
        await tester.drag(list, const Offset(0, -420));
        await tester.pumpAndSettle();
      }
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings bottom viewport matches the approved design',
      (tester) async {
    await pumpSettings(tester);
    final list = find.byType(Scrollable).first;
    for (var attempt = 0;
        attempt < 16 && find.text('Log out').evaluate().isEmpty;
        attempt++) {
      await tester.drag(list, const Offset(0, -440));
      await tester.pumpAndSettle();
    }
    expect(find.text('Log out'), findsOneWidget);
    await tester.fling(list, const Offset(0, -900), 1200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_bottom.png'),
    );
  });

  testWidgets('settings has no overflow on a narrow phone', (tester) async {
    await pumpSettings(tester, size: const Size(320, 700));
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 14; i++) {
      await tester.drag(list, const Offset(0, -380));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}

File _findMaterialIcons() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 10; i++) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts${Platform.pathSeparator}material_fonts${Platform.pathSeparator}materialicons-regular.otf',
    );
    if (candidate.existsSync()) return candidate;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError('Flutter Material Icons font not found.');
}
