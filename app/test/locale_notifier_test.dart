import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/theme/locale_notifier.dart';

// Guards the pure locale-resolution helpers that back the UI-language picker.
// These are deterministic (no SharedPreferences / no notifiers touched) so we
// can assert the fallback contract: any not-yet-translated code, the system
// sentinel, and unknown device locales all resolve down to a renderable locale
// (English) — the picker never breaks the app.
void main() {
  group('LocaleNotifier.resolve', () {
    test('null / empty / system sentinel follow the system (null locale)', () {
      expect(LocaleNotifier.resolve(null), isNull);
      expect(LocaleNotifier.resolve(''), isNull);
      expect(LocaleNotifier.resolve(LocaleNotifier.systemCode), isNull);
    });

    test('a supported language code resolves to that locale', () {
      expect(LocaleNotifier.resolve('en'), const Locale('en'));
    });

    test('region/script suffixes are stripped to the language code', () {
      expect(LocaleNotifier.resolve('en-US'), const Locale('en'));
      expect(LocaleNotifier.resolve('EN_us'), const Locale('en'));
    });

    test('a not-yet-translated code falls back to English', () {
      // 'ro' is offered in the picker but has no framework translation yet.
      expect(LocaleNotifier.resolve('ro'), const Locale('en'));
      expect(LocaleNotifier.resolve('zz'), const Locale('en'));
    });
  });

  group('LocaleNotifier.localeResolution', () {
    const supported = LocaleNotifier.supportedLocales;

    test('honours a pinned locale regardless of device locale', () {
      LocaleNotifier.locale.value = const Locale('en');
      expect(
        LocaleNotifier.localeResolution(const Locale('fr'), supported),
        const Locale('en'),
      );
      LocaleNotifier.locale.value = null; // reset for other suites
    });

    test('matches the device language when not pinned', () {
      LocaleNotifier.locale.value = null;
      expect(
        LocaleNotifier.localeResolution(const Locale('en', 'GB'), supported),
        const Locale('en'),
      );
    });

    test('falls back to English for an unsupported / null device locale', () {
      LocaleNotifier.locale.value = null;
      expect(
        LocaleNotifier.localeResolution(const Locale('de'), supported),
        const Locale('en'),
      );
      expect(
        LocaleNotifier.localeResolution(null, supported),
        const Locale('en'),
      );
    });
  });
}
