import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Persistență locală per-user pentru date reutilizabile (cache read-through).
/// Social / feed rămân online; GIF-urile exercițiilor se încarcă la nevoie din rețea.
class AppDataCache {
  AppDataCache._([AuthService? auth]) : _auth = auth ?? AuthService();

  static final AppDataCache instance = AppDataCache._();

  final AuthService _auth;

  static const _prefix = 'zvelt_cache_v1';

  Future<String> _scopedKey(String suffix) async {
    final id = await _auth.getCurrentUserId();
    return '${_prefix}_${id ?? 'anonymous'}_$suffix';
  }

  static String localDayYmd([DateTime? d]) {
    final x = d ?? DateTime.now();
    return '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  }

  /// Luni săptămânii curente (local).
  static String localWeekStartYmd([DateTime? d]) {
    final now = d ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final monday = day.subtract(Duration(days: day.weekday - 1));
    return localDayYmd(monday);
  }

  static String monthYyyyMm(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Future<void> putString(String suffix, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await _scopedKey(suffix), value);
  }

  Future<String?> getString(String suffix) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(await _scopedKey(suffix));
  }

  Future<void> remove(String suffix) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _scopedKey(suffix));
  }

  Future<void> putJson(String suffix, Object value) async {
    await putString(suffix, jsonEncode(value));
  }

  // ── Timestamped (TTL) cache — for read-mostly "numbers" (stats, training
  // load, profile) so the app serves them instantly and stops re-requesting
  // on every tab switch / resume. Stored as {t: epochMs, v: payload}.
  Future<void> putTimedJson(String suffix, Object value) =>
      putJson(suffix, {'t': DateTime.now().millisecondsSinceEpoch, 'v': value});

  /// Returns the cached payload + its age, or null if absent/corrupt.
  Future<({Object? value, Duration age})?> getTimed(String suffix) async {
    final m = await getJsonObject(suffix);
    if (m == null) return null;
    final t = (m['t'] as num?)?.toInt();
    if (t == null) return null;
    final age =
        Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - t);
    return (value: m['v'], age: age);
  }

  Future<Map<String, dynamic>?> getJsonObject(String suffix) async {
    final raw = await getString(suffix);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  Future<List<dynamic>?> getJsonList(String suffix) async {
    final raw = await getString(suffix);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    } catch (_) {}
    return null;
  }

  // ── /v1/me ─────────────────────────────────────────────────────────────────

  static const _me = 'me_profile_v1';

  Future<void> saveMe(Map<String, dynamic> body) => putJson(_me, body);

  Future<Map<String, dynamic>?> loadMe() => getJsonObject(_me);

  Future<void> clearMe() => remove(_me);

  // ── Training profile ───────────────────────────────────────────────────────

  static const _trainingProfile = 'training_profile_v1';

  Future<void> saveTrainingProfile(Map<String, dynamic> tp) =>
      putJson(_trainingProfile, tp);

  Future<Map<String, dynamic>?> loadTrainingProfile() => getJsonObject(_trainingProfile);

  Future<void> clearTrainingProfile() => remove(_trainingProfile);

  // ── Onboarding AI (plan + goal advice + interpretation) ──────────────────

  static const _onboardingAi = 'onboarding_ai_v1';

  Future<void> saveOnboardingAi(Map<String, dynamic> bundle) =>
      putJson(_onboardingAi, bundle);

  Future<Map<String, dynamic>?> loadOnboardingAi() => getJsonObject(_onboardingAi);

  Future<void> mergeOnboardingAi(Map<String, dynamic> partial) async {
    final existing = await loadOnboardingAi() ?? <String, dynamic>{};
    await saveOnboardingAi({...existing, ...partial});
  }

  // ── Workout suggestion (per calendar day) ────────────────────────────────────

  String _suggestionKey([DateTime? d]) => 'workout_suggestion_${localDayYmd(d)}';

  Future<void> saveWorkoutSuggestion(Map<String, dynamic> suggestion, [DateTime? d]) =>
      putJson(_suggestionKey(d), suggestion);

  Future<Map<String, dynamic>?> loadWorkoutSuggestion([DateTime? d]) =>
      getJsonObject(_suggestionKey(d));

  // ── Nutrition weekly plan ────────────────────────────────────────────────────

  String _nutritionWeekKey(String weekStart) => 'nutrition_week_$weekStart';

  Future<void> saveNutritionWeek(String weekStart, List<Map<String, dynamic>> plan) =>
      putJson(_nutritionWeekKey(weekStart), plan);

  Future<List<Map<String, dynamic>>?> loadNutritionWeek(String weekStart) async {
    final list = await getJsonList(_nutritionWeekKey(weekStart));
    if (list == null) return null;
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ── Muscle recovery map ────────────────────────────────────────────────────

  static const _muscleRecovery = 'muscle_recovery_v1';

  Future<void> saveMuscleRecovery(Map<String, dynamic> payload) =>
      putJson(_muscleRecovery, payload);

  Future<Map<String, dynamic>?> loadMuscleRecovery() => getJsonObject(_muscleRecovery);

  Future<void> clearMuscleRecovery() => remove(_muscleRecovery);

  // ── Activity calendar month ─────────────────────────────────────────────────

  String _calendarMonthKey(String yyyyMm) => 'calendar_month_$yyyyMm';

  Future<void> saveCalendarMonth(String yyyyMm, Map<String, dynamic> days) =>
      putJson(_calendarMonthKey(yyyyMm), days);

  Future<Map<String, dynamic>?> loadCalendarMonth(String yyyyMm) async {
    final raw = await getJsonObject(_calendarMonthKey(yyyyMm));
    return raw;
  }

  // ── Daily quote ─────────────────────────────────────────────────────────────

  String _dailyQuoteKey([DateTime? d]) => 'daily_quote_${localDayYmd(d)}';

  Future<void> saveDailyQuote(Map<String, dynamic> quote, [DateTime? d]) =>
      putJson(_dailyQuoteKey(d), quote);

  Future<Map<String, dynamic>?> loadDailyQuote([DateTime? d]) =>
      getJsonObject(_dailyQuoteKey(d));

  // ── Character stats (/me/stats) + training load (/me/stats/daily-training) ──
  // Read-mostly "numbers"; cached with a TTL so Train renders instantly and
  // doesn't refetch on every visit. Force-refreshed after a workout / pull.

  static const characterStatsKey = 'character_stats_v2';

  static String dailyTrainingKey(int days) => 'daily_training_${days}d_v2';

  Future<void> clearCharacterStats() => remove(characterStatsKey);

  Future<void> clearDailyTraining(int days) => remove(dailyTrainingKey(days));

  /// La logout — șterge cache-ul userului curent (chei scoped rămân pe device dar alt prefix user).
  Future<void> clearSessionCaches() async {
    await Future.wait([
      clearMe(),
      clearTrainingProfile(),
      clearMuscleRecovery(),
      clearCharacterStats(),
    ]);
  }

  static const _programBuilderPlan = 'program_builder_plan_v1';

  Future<void> saveProgramBuilderPlan(Map<String, dynamic> plan) =>
      putJson(_programBuilderPlan, plan);

  Future<Map<String, dynamic>?> loadProgramBuilderPlan() =>
      getJsonObject(_programBuilderPlan);
}
