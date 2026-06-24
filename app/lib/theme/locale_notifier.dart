import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/settings_store.dart';

/// Global UI-language notifier. Mirrors the [ZveltThemeNotifier] pattern:
/// a single app-wide [ValueNotifier] that [main]'s [MaterialApp] listens to so
/// changing the language re-renders the tree immediately. Call [init] once at
/// app startup (before the first `MaterialApp` builds), then [set]/[clear] from
/// the language picker.
///
/// Persistence reuses the existing device-local key [SettingsKeys.language] so a
/// choice made before this notifier existed is honoured on next launch. The
/// stored value is the user's *preference* (any code the picker offers); the
/// locale handed to Flutter is always resolved down to a locale the app can
/// actually render via [resolve] / [supportedLocales], with English as the
/// guaranteed fallback. This keeps the picker fully usable even while English is
/// the only fully-translated locale — nothing breaks, en stays selectable, and
/// adding a real translation later only requires extending [supportedLocales].
class LocaleNotifier {
  LocaleNotifier._();

  /// Locales the app can actually render today. English is always present and is
  /// the fallback for anything else. Extend this list (and ship the matching
  /// `flutter_localizations` delegates) when a new translation lands.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
  ];

  /// Sentinel meaning "follow the system locale". The picker can persist this so
  /// the app tracks the OS language instead of a fixed choice.
  static const String systemCode = 'system';

  /// The user's chosen UI-language code (e.g. `en`, `ro`) or [systemCode] /
  /// `null` to follow the system. This is the *preference* as picked — not
  /// necessarily a fully-translated locale. Drive the picker's selection from
  /// this and the effective render locale from [locale].
  static final ValueNotifier<String?> preference = ValueNotifier<String?>(null);

  /// The [Locale] to hand to `MaterialApp.locale`. `null` lets Flutter resolve
  /// against [supportedLocales] using the system locale (then en). A non-null
  /// value is always one of [supportedLocales].
  static final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  /// Load the persisted preference. Best-effort: any failure leaves the
  /// defaults (follow system, render en) so startup never blocks on prefs.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(SettingsKeys.language);
      _apply(stored);
    } catch (e) {
      debugPrint('[LocaleNotifier.init] prefs load best-effort skip: $e');
    }
  }

  /// Pick a UI language by code (e.g. `en`). Persists the preference and updates
  /// the effective [locale] (resolved to a supported locale). Pass [systemCode]
  /// or call [clear] to follow the system language.
  static Future<void> set(String code) async {
    _apply(code);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SettingsKeys.language, code);
    } catch (e) {
      debugPrint('[LocaleNotifier.set] prefs save best-effort skip: $e');
    }
  }

  /// Revert to following the system language.
  static Future<void> clear() => set(systemCode);

  static void _apply(String? code) {
    final normalized = (code == null || code.isEmpty) ? null : code;
    preference.value = normalized;
    locale.value = resolve(normalized);
  }

  /// Map a stored preference code to an effective [Locale], or `null` to follow
  /// the system. Pure (no prefs / no notifiers) so it is unit-testable:
  ///  - `null` / empty / [systemCode] → `null` (Flutter resolves system → en).
  ///  - a code matching a [supportedLocales] language → that locale.
  ///  - anything else (a not-yet-translated language) → English, so the app
  ///    stays fully rendered instead of showing a half-translated/garbled UI.
  static Locale? resolve(String? code) {
    if (code == null || code.isEmpty || code == systemCode) return null;
    final lang = code.split(RegExp('[-_]')).first.toLowerCase();
    for (final l in supportedLocales) {
      if (l.languageCode == lang) return l;
    }
    return const Locale('en');
  }

  /// `MaterialApp.localeResolutionCallback`. Honours [locale] when set; on
  /// `null` (follow system) it matches the device locale against
  /// [supportedLocales] by language code, falling back to English. Never returns
  /// a locale the app can't render.
  static Locale localeResolution(Locale? deviceLocale, Iterable<Locale> supported) {
    final pinned = locale.value;
    if (pinned != null) return pinned;
    if (deviceLocale != null) {
      for (final l in supported) {
        if (l.languageCode == deviceLocale.languageCode) return l;
      }
    }
    return const Locale('en');
  }
}
