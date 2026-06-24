// Locale- and unit-aware display formatting for Zvelt.
//
// Canonical storage stays metric everywhere (kg / cm / m); this layer is
// DISPLAY ONLY. The Wave 21 open-source audit (localization-accessibility, P1)
// found the same two patterns duplicated across many screens:
//   1. "drop the trailing .0" on a double (`toStringAsFixed(0)` vs `.round()`
//      vs ad-hoc string trimming), and
//   2. hardcoded unit suffixes ('kg', 'cm', 'km') that ignore the user's
//      metric/imperial preference (e.g. exercise_load_policy.dart).
// It also found every `DateFormat(...)` call site omitting a locale, forcing
// English month/weekday names regardless of device language.
//
// This module centralizes all three. Unit conversions read the single
// app-wide source of truth, [UnitsNotifier] (mirrors profile.unitSystem).
//
// Everything here is pure given its inputs (the unit system can be passed
// explicitly via [imperial], otherwise it defaults to the live notifier value),
// so the helpers are trivially unit-testable without a widget tree.
import 'package:intl/intl.dart';

import '../services/settings_store.dart';

/// Conversion factors (canonical metric -> imperial display units).
/// Kept exact enough for lossless round-tripping in tests.
const double _kgPerLb = 0.45359237;
const double _lbPerKg = 1 / _kgPerLb; // ~2.2046226218
const double _cmPerInch = 2.54;
const double _metersPerMile = 1609.344;

/// Resolves the active imperial flag: explicit override wins, otherwise the
/// live app-wide unit system.
bool _isImperial(bool? imperial) => imperial ?? UnitsNotifier.isImperial;

// ---------------------------------------------------------------------------
// Numbers
// ---------------------------------------------------------------------------

/// Formats [value] with up to [maxFractionDigits] decimals, dropping a trailing
/// `.0` (and trailing zeros generally) and applying locale-aware grouping +
/// decimal separators.
///
/// Replaces the scattered `toStringAsFixed(0)` / manual `.0`-trim idioms:
///   formatNumber(80.0)        -> "80"
///   formatNumber(72.5)        -> "72.5"
///   formatNumber(1234.0)      -> "1,234"   (en) / "1.234" (de)
///   formatNumber(2.345, 2)    -> "2.35"
String formatNumber(num value, {int maxFractionDigits = 1, String? locale}) {
  final pattern = StringBuffer('#,##0');
  if (maxFractionDigits > 0) {
    pattern.write('.');
    pattern.write('#' * maxFractionDigits);
  }
  return NumberFormat(pattern.toString(), locale).format(value);
}

/// Compact, human-friendly large-number formatting (e.g. follower counts,
/// total volume). Uses intl's locale-aware compact rules:
///   formatCompact(950)     -> "950"
///   formatCompact(1500)    -> "1.5K"
///   formatCompact(2000000) -> "2M"
String formatCompact(num value, {String? locale}) =>
    NumberFormat.compact(locale: locale).format(value);

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

/// Locale-aware date formatting. Pass an intl skeleton (e.g. 'MMM d',
/// 'yMMMd', 'EEE') as [pattern]; month/weekday names follow [locale] (defaults
/// to intl's current locale). Always pass a LOCAL [DateTime].
///
///   formatDate(d, pattern: 'MMM d')          -> "Mar 14" / "14 mars" (fr)
///   formatDate(d, pattern: 'yMMMd')          -> "Mar 14, 2026"
String formatDate(DateTime when, {String pattern = 'yMMMd', String? locale}) =>
    DateFormat(pattern, locale).format(when);

// ---------------------------------------------------------------------------
// Units (display-only; storage is always metric)
// ---------------------------------------------------------------------------

/// Display weight from canonical kilograms.
///   metric:   formatWeight(80)  -> "80 kg"
///   imperial: formatWeight(100) -> "220 lb"
/// [decimals] controls fractional precision of the converted value.
String formatWeight(double kg,
    {bool? imperial, int decimals = 0, String? locale}) {
  if (_isImperial(imperial)) {
    return '${formatNumber(kgToLb(kg), maxFractionDigits: decimals, locale: locale)} lb';
  }
  return '${formatNumber(kg, maxFractionDigits: decimals, locale: locale)} kg';
}

/// Display height from canonical centimeters.
///   metric:   formatHeight(180) -> "180 cm"
///   imperial: formatHeight(180) -> "5'11\"" (feet + inches)
String formatHeight(double cm, {bool? imperial, String? locale}) {
  if (_isImperial(imperial)) {
    final totalInches = cmToInch(cm);
    final feet = totalInches ~/ 12;
    final inches = (totalInches - feet * 12).round();
    // Carry 12" up to the next foot (e.g. 11.6" rounds to 12").
    if (inches == 12) return '${feet + 1}\'0"';
    return '$feet\'$inches"';
  }
  return '${formatNumber(cm, maxFractionDigits: 0, locale: locale)} cm';
}

/// Display distance from canonical meters. Chooses a sensible unit:
///   metric:   <1000 m -> "850 m", else km ("5.2 km")
///   imperial: always miles ("3.2 mi")
String formatDistance(double meters,
    {bool? imperial, int decimals = 1, String? locale}) {
  if (_isImperial(imperial)) {
    return '${formatNumber(metersToMiles(meters), maxFractionDigits: decimals, locale: locale)} mi';
  }
  if (meters < 1000) {
    return '${formatNumber(meters, maxFractionDigits: 0, locale: locale)} m';
  }
  return '${formatNumber(meters / 1000, maxFractionDigits: decimals, locale: locale)} km';
}

// ---------------------------------------------------------------------------
// Raw conversions (no formatting) — both directions, for inputs/round-trips.
// ---------------------------------------------------------------------------

double kgToLb(double kg) => kg * _lbPerKg;
double lbToKg(double lb) => lb * _kgPerLb;

double cmToInch(double cm) => cm / _cmPerInch;
double inchToCm(double inch) => inch * _cmPerInch;

double metersToMiles(double m) => m / _metersPerMile;
double milesToMeters(double mi) => mi * _metersPerMile;
