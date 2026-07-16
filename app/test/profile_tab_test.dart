import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zvelt_app/screens/profile/profile_tab.dart';
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

  Future<void> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightThemeData,
        home: ProfileTab(
          preview: true,
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('profile owns legal and diagnostics without a settings entry',
      (tester) async {
    await pumpProfile(tester);

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Preferences'), findsNothing);

    final list = find.byType(Scrollable).first;
    for (var attempt = 0;
        attempt < 16 && find.text('Enable diagnostics').evaluate().isEmpty;
        attempt++) {
      await tester.drag(list, const Offset(0, -420));
      await tester.pumpAndSettle();
    }

    expect(find.text('Legal'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Clear cache & reload all data'), findsOneWidget);
    expect(find.text('Send logs to developer'), findsOneWidget);
    expect(find.text('Enable diagnostics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account keeps delete directly below sign out', (tester) async {
    await pumpProfile(tester);
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    final signOut = find.text('Sign out');
    final deleteAccount = find.text('Delete account');
    expect(signOut, findsOneWidget);
    expect(deleteAccount, findsOneWidget);
    expect(
      tester.getTopLeft(signOut).dy,
      lessThan(tester.getTopLeft(deleteAccount).dy),
    );
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
