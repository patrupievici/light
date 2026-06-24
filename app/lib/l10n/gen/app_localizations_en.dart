// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageScreenTitle => 'Language';

  @override
  String get languageScreenEyebrow => 'GENERAL';

  @override
  String get languageScreenNote =>
      'Your display-language choice is stored on this device. Screens that have translations use it automatically.';

  @override
  String get languagePreferenceSaved => 'Language preference saved.';

  @override
  String get save => 'Save';

  @override
  String get done => 'Done';

  @override
  String workoutsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count workouts',
      one: '1 workout',
      zero: 'No workouts yet',
    );
    return '$_temp0';
  }
}
