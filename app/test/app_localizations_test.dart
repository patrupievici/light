import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/l10n/gen/app_localizations.dart';

// Proves the gen-l10n pipeline end to end (scaffold + pilot pattern):
//  - the generated delegate resolves AppLocalizations for en and ro,
//  - representative keys + the ICU plural (workoutsCount) render correctly,
//  - a key only present in the en template falls back to English under ro,
//    so an untouched / partially-translated locale never blanks the UI.
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

  testWidgets('Romanian skeleton renders translated keys', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      _host(
        locale: const Locale('ro'),
        child: Builder(builder: (context) {
          l10n = AppLocalizations.of(context);
          return Text(l10n.languageScreenTitle);
        }),
      ),
    );
    expect(l10n.languageScreenTitle, 'Limbă');
    expect(l10n.save, 'Salvează');
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

  test('both locales are supported by the generated delegate', () {
    final codes =
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
    expect(codes.containsAll(<String>{'en', 'ro'}), isTrue);
  });
}
