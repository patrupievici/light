import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/settings_store.dart';
import 'package:zvelt_app/utils/formatters.dart';

// Pure-helper coverage for the locale/unit formatting layer. Conversions are
// asserted in BOTH directions (canonical metric <-> imperial display) to lock
// the "storage stays metric, formatting is display-only" invariant.
void main() {
  // Keep the app-wide notifier metric for tests that rely on the default;
  // explicit `imperial:` overrides exercise the imperial path deterministically
  // without mutating global state.
  setUp(() => UnitsNotifier.system.value = 'metric');
  tearDown(() => UnitsNotifier.system.value = 'metric');

  group('formatNumber', () {
    test('drops trailing .0', () {
      expect(formatNumber(80.0), '80');
      expect(formatNumber(1234.0, locale: 'en_US'), '1,234');
    });

    test('keeps significant decimals up to the cap', () {
      expect(formatNumber(72.5), '72.5');
      expect(formatNumber(2.345, maxFractionDigits: 2), '2.35'); // rounds
    });

    test('groups thousands per locale', () {
      expect(formatNumber(12345.6, locale: 'en_US'), '12,345.6');
      // German uses '.' grouping and ',' decimal.
      expect(formatNumber(1234.0, locale: 'de_DE'), '1.234');
    });
  });

  group('formatCompact', () {
    test('compacts large numbers', () {
      expect(formatCompact(950, locale: 'en_US'), '950');
      expect(formatCompact(1500, locale: 'en_US'), '1.5K');
      expect(formatCompact(2000000, locale: 'en_US'), '2M');
    });
  });

  group('formatDate', () {
    test('formats with an intl skeleton (en)', () {
      final d = DateTime(2026, 3, 14);
      expect(formatDate(d, pattern: 'MMM d', locale: 'en_US'), 'Mar 14');
      expect(formatDate(d, pattern: 'yMMMd', locale: 'en_US'), 'Mar 14, 2026');
    });
  });

  group('weight conversion + display', () {
    test('kg <-> lb round-trips losslessly', () {
      expect(kgToLb(100), closeTo(220.462, 0.01));
      expect(lbToKg(kgToLb(100)), closeTo(100, 1e-9));
      expect(kgToLb(lbToKg(225)), closeTo(225, 1e-9));
    });

    test('metric vs imperial display', () {
      expect(formatWeight(80, imperial: false, locale: 'en_US'), '80 kg');
      expect(formatWeight(100, imperial: true, locale: 'en_US'), '220 lb');
      expect(formatWeight(102.5, imperial: false, decimals: 1, locale: 'en_US'),
          '102.5 kg');
    });

    test('reads live UnitsNotifier when imperial flag omitted', () {
      UnitsNotifier.system.value = 'imperial';
      expect(formatWeight(100, locale: 'en_US'), '220 lb');
      UnitsNotifier.system.value = 'metric';
      expect(formatWeight(100, locale: 'en_US'), '100 kg');
    });
  });

  group('height conversion + display', () {
    test('cm <-> inch round-trips', () {
      expect(cmToInch(180), closeTo(70.866, 0.01));
      expect(inchToCm(cmToInch(180)), closeTo(180, 1e-9));
    });

    test('metric cm vs imperial feet+inches', () {
      expect(formatHeight(180, imperial: false, locale: 'en_US'), '180 cm');
      expect(formatHeight(180, imperial: true), '5\'11"');
      // 182.9 cm ~= 72.0 in -> 6'0"
      expect(formatHeight(182.9, imperial: true), '6\'0"');
    });

    test('carries 12 inches up to the next foot', () {
      // 181.5 cm ~= 71.46 in -> 5'11.46" rounds inches to 11 (not a carry)
      expect(formatHeight(181.5, imperial: true), '5\'11"');
      // 182.5 cm ~= 71.85 in -> inches round to 12 -> carry to 6'0"
      expect(formatHeight(182.5, imperial: true), '6\'0"');
    });
  });

  group('distance conversion + display', () {
    test('meters <-> miles round-trips', () {
      expect(metersToMiles(1609.344), closeTo(1.0, 1e-9));
      expect(milesToMeters(metersToMiles(5000)), closeTo(5000, 1e-6));
    });

    test('metric chooses m below 1km and km above', () {
      expect(formatDistance(850, imperial: false, locale: 'en_US'), '850 m');
      expect(formatDistance(5200, imperial: false, locale: 'en_US'), '5.2 km');
    });

    test('imperial always miles', () {
      expect(formatDistance(5000, imperial: true, locale: 'en_US'), '3.1 mi');
    });
  });
}
