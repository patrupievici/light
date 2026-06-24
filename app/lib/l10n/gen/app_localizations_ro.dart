// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Romanian Moldavian Moldovan (`ro`).
class AppLocalizationsRo extends AppLocalizations {
  AppLocalizationsRo([String locale = 'ro']) : super(locale);

  @override
  String get languageScreenTitle => 'Limbă';

  @override
  String get languageScreenEyebrow => 'GENERAL';

  @override
  String get languageScreenNote =>
      'Alegerea limbii de afișare este salvată pe acest dispozitiv. Ecranele traduse o folosesc automat.';

  @override
  String get languagePreferenceSaved => 'Preferința de limbă a fost salvată.';

  @override
  String get save => 'Salvează';

  @override
  String get done => 'Gata';

  @override
  String workoutsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count antrenamente',
      one: '1 antrenament',
      zero: 'Niciun antrenament încă',
    );
    return '$_temp0';
  }
}
