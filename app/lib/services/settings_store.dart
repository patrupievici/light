// Central registry of device-local Settings keys + a small global notifier so
// screens react to live changes (units in particular). Device-local prefs
// (units, notification categories, customization, shortcuts,
// language, getting-started, diagnostics, cloud prefs, starting 1RMs) live in
// SharedPreferences — NOT the /me/settings endpoint, per ProfileService's doc.
//
// Theme lives in ZveltThemeNotifier (key 'zvelt_theme_mode'); unit *system* is
// ALSO a real backend field (profile.unitSystem) — we mirror it locally for
// instant cold-start render and cross-screen reactivity.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key constants for the redesigned Settings.
class SettingsKeys {
  SettingsKeys._();

  // Units
  static const unitSystem = 'zvelt_unit_system'; // 'metric' | 'imperial'

  // Notifications (per-category, local)
  static const notifMaster = 'zvelt_notif_master';
  static const notifWorkout = 'zvelt_notif_workout';
  static const notifSocial = 'zvelt_notif_social';
  static const notifChallenges = 'zvelt_notif_challenges';
  static const notifRecovery = 'zvelt_notif_recovery';
  static const notifNutrition = 'zvelt_notif_nutrition';
  static const notifCoach = 'zvelt_notif_coach';

  // Customization
  static const accent = 'zvelt_accent'; // stored ARGB int
  static const startScreen =
      'zvelt_start_screen'; // 'home'|'train'|'food'|'feed'
  static const reduceMotion = 'zvelt_reduce_motion';

  // Shortcuts (quick-launch)
  static const scEmpty = 'zvelt_sc_empty';
  static const scAi = 'zvelt_sc_ai';
  static const scRun = 'zvelt_sc_run';
  static const scMeal = 'zvelt_sc_meal';
  static const scRace = 'zvelt_sc_race';
  static const scPhoto = 'zvelt_sc_photo';

  // Language
  static const language = 'zvelt_language'; // locale code, e.g. 'en'

  // Profile-visibility detail toggle (local-only extra)
  static const showStats = 'zvelt_show_stats';
  static const showActivity = 'zvelt_show_activity';
  static const discoverable = 'zvelt_discoverable';

  // Cloud sync prefs
  static const cloudAuto = 'zvelt_cloud_auto';
  static const cloudCellular = 'zvelt_cloud_cellular';
  static const cloudLastSync = 'zvelt_cloud_last_sync'; // ISO8601

  // Getting started checklist
  static const gsProfile = 'zvelt_gs_profile';
  static const gsData = 'zvelt_gs_data';
  static const gsDevice = 'zvelt_gs_device';
  static const gsWorkout = 'zvelt_gs_workout';
  static const gsFriends = 'zvelt_gs_friends';

  // Starting 1RM (local; canonical strength is workout-derived)
  static const rmSquat = 'zvelt_rm_squat';
  static const rmBench = 'zvelt_rm_bench';
  static const rmDeadlift = 'zvelt_rm_deadlift';
  static const rmPress = 'zvelt_rm_press';

  // Diagnostics
  static const diagnostics = 'zvelt_diagnostics_enabled';
}

/// Global, app-wide unit system. Mirrors ProfileService profile.unitSystem and
/// is the single source other screens can listen to for instant kg↔lb / km↔mi.
class UnitsNotifier {
  UnitsNotifier._();

  static final ValueNotifier<String> system = ValueNotifier<String>('metric');

  static bool get isImperial => system.value == 'imperial';

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(SettingsKeys.unitSystem);
      if (v == 'metric' || v == 'imperial') system.value = v!;
    } catch (e) {
      debugPrint('[UnitsNotifier.init] best-effort skip: $e');
    }
  }

  /// Update + persist locally. (Backend sync is the caller's responsibility.)
  static Future<void> set(String value) async {
    if (value != 'metric' && value != 'imperial') return;
    system.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SettingsKeys.unitSystem, value);
    } catch (e) {
      debugPrint('[UnitsNotifier.set] best-effort skip: $e');
    }
  }

  // Display helpers (canonical storage is always metric).
  static String weight(double kg) =>
      isImperial ? '${(kg * 2.20462).round()} lb' : '${kg.round()} kg';
  static double kgToDisplay(double kg) => isImperial ? kg * 2.20462 : kg;
  static double displayToKg(double v) => isImperial ? v / 2.20462 : v;
}

/// Device-wide visual preferences used by the app shell and Settings widgets.
class AppPreferencesNotifier {
  AppPreferencesNotifier._();

  static final ValueNotifier<int> accent = ValueNotifier<int>(0xFFFF7A2F);
  static final ValueNotifier<bool> reduceMotion = ValueNotifier<bool>(false);

  static Color get accentColor => Color(accent.value);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      accent.value = prefs.getInt(SettingsKeys.accent) ?? accent.value;
      reduceMotion.value = prefs.getBool(SettingsKeys.reduceMotion) ?? false;
    } catch (e) {
      debugPrint('[AppPreferencesNotifier.init] best-effort skip: $e');
    }
  }

  static Future<void> setAccent(int value) async {
    accent.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SettingsKeys.accent, value);
  }

  static Future<void> setReduceMotion(bool value) async {
    reduceMotion.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.reduceMotion, value);
  }
}

/// Reads the user's preferred launch tab (used by MainScreen at startup).
Future<String> readStartScreen() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(SettingsKeys.startScreen) ?? 'home';
  } catch (_) {
    return 'home';
  }
}
