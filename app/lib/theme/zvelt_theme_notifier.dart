import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeKey = 'zvelt_theme_mode';

/// Global theme-mode notifier. Call [init] once at app startup.
class ZveltThemeNotifier {
  ZveltThemeNotifier._();

  // Dark-first (Claude Design handoff): dark is the default until the user
  // explicitly picks another mode (persisted).
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kThemeKey);
      mode.value = _fromString(raw);
    } catch (e) {
      debugPrint('[ZveltThemeNotifier.init] prefs load best-effort skip: $e');
    }
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeKey, _toString(m));
    } catch (e) {
      debugPrint('[ZveltThemeNotifier.set] prefs save best-effort skip: $e');
    }
  }

  static ThemeMode _fromString(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.dark;
    }
  }

  static String _toString(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
      default:
        return 'dark';
    }
  }
}
