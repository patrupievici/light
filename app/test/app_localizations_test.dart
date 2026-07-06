import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/l10n/gen/app_localizations.dart';

// Proves the English-only gen-l10n pipeline end to end:
//  - the generated delegate resolves AppLocalizations for en,
//  - representative keys + the ICU plural (workoutsCount) render correctly,
//  - no partially translated locale is exposed to the app shell.
Widget _host({required Locale locale, required Widget child}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (_) => child),
    );

void main() {
  testWidgets('English copy renders for the pilot keys', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      _host(
        locale: const Locale('en'),
        child: Builder(builder: (context) {
          l10n = AppLocalizations.of(context);
          return Text(l10n.languageScreenTitle);
        }),
      ),
    );
    expect(l10n.languageScreenTitle, 'Language');
    expect(l10n.languagePreferenceSaved, 'Language preference saved.');
  });

  testWidgets('ICU plural (workoutsCount) selects the right form', (tester) async {
    late AppLocalizations en;
    await tester.pumpWidget(
      _host(
        locale: const Locale('en'),
        child: Builder(builder: (context) {
          en = AppLocalizations.of(context);
          return const SizedBox.shrink();
        }),
      ),
    );
    expect(en.workoutsCount(0), 'No workouts yet');
    expect(en.workoutsCount(1), '1 workout');
    expect(en.workoutsCount(5), '5 workouts');
  });

  test('only English is supported by the generated delegate', () {
    final codes =
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
    expect(codes, <String>{'en'});
  });
}
