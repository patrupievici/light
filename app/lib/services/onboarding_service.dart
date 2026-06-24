import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart' show v1Base;
import '../models/onboarding_models.dart';
import '_crash_reporter.dart';
import 'ai_chat_service.dart';
import 'auth_service.dart';
import 'http_client.dart';
import 'nutrition_service.dart';
import 'profile_service.dart';
import 'training_profile_service.dart';
import 'workout_service.dart';

/// Flat payload pushed to the backend by [OnboardingService.completeOnboarding].
/// Built from `_OnbData.toPayload` in onboarding_v3.dart; keeping it as plain
/// nullable fields lets us tolerate optional questionnaire answers.
class OnboardingPayload {
  OnboardingPayload({
    this.name,
    this.signInMethod,
    this.source,
    this.permissions = const <String, bool>{},
    this.followed = const <String>[],
    this.archetype,
    this.goal,
    this.units = 'metric',
    this.sex,
    this.height,
    this.weight,
    this.age,
    this.experience,
    this.bench,
    this.squat,
    this.dead,
    this.runPace,
    this.bikeKm,
    this.cadence,
    this.proTrial = false,
    this.photoTaken = false,
    this.aiVision,
    this.dietary = const <String>[],
  });

  final String? name;
  final String? signInMethod;
  final String? source;
  final Map<String, bool> permissions;
  final List<String> followed;
  final String? archetype;
  final String? goal;
  final String units;
  final String? sex;
  final double? height;
  final double? weight;
  final double? age;
  final String? experience;
  final double? bench;
  final double? squat;
  final double? dead;
  final String? runPace;
  final String? bikeKm;
  final String? cadence;
  final bool proTrial;
  final bool photoTaken;
  final String? aiVision;
  final List<String> dietary;
}

/// Aggregate result of a completeOnboarding call. [profileSynced] / [settingsSynced]
/// flip false when the backend was unreachable so the UI can hint a later retry;
/// [plan] holds the AI-generated starter plan (best-effort, may be null).
class OnboardingResult {
  const OnboardingResult({
    required this.profileSynced,
    required this.settingsSynced,
    this.plan,
    this.errors = const <String>[],
  });

  final bool profileSynced;
  final bool settingsSynced;
  final Map<String, dynamic>? plan;
  final List<String> errors;

  bool get isSuccess => profileSynced && settingsSynced;
}

/// Phases reported by [OnboardingService.completeOnboarding] via the optional
/// progress callback. Lets _Step18 tie its 0-100% loading bar to real work
/// instead of a fake timer.
enum OnboardingPhase { savingProfile, savingSettings, generatingPlan, done }

/// Persists onboarding questionnaire answers locally and syncs to backend.
class OnboardingService {
  OnboardingService({
    AuthService? auth,
    ProfileService? profile,
    AiChatService? ai,
  })  : _auth = auth ?? AuthService(),
        _profile = profile ?? ProfileService(),
        _ai = ai ?? AiChatService();

  final AuthService _auth;
  final ProfileService _profile;
  final AiChatService _ai;

  /// Fire-and-forget weekly-plan future started by [prewarmPlanFromGoal].
  /// Shared across OnboardingService instances so the call kicked off from
  /// _StepAITalk can be awaited by _Step18 (loading screen) without holding
  /// a reference. A static field is acceptable here because onboarding is
  /// single-flight per session — the user can't run two onboardings.
  static Future<Map<String, dynamic>>? _prewarmedPlan;
  static String? _prewarmedGoalText;

  // SharedPreferences keys
  static const String _kUnits = 'ob_units';
  static const String _kMuscleGroups = 'ob_muscle_groups';
  static const String _kGoal = 'ob_goal';
  static const String _kGender = 'ob_gender';
  static const String _kHeightCm = 'ob_height_cm';
  static const String _kHeightIn = 'ob_height_in';
  static const String _kWeightKg = 'ob_weight_kg';
  static const String _kWeightLbs = 'ob_weight_lbs';
  static const String _kAge = 'ob_age';

  /// Save all questionnaire answers — local first, then backend.
  Future<void> save(QuestionnaireState state) async {
    await _saveLocal(state);
    await _syncToBackend(state);
  }

  Future<void> _saveLocal(QuestionnaireState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUnits, state.units.name);
    await prefs.setString(
        _kMuscleGroups, jsonEncode(state.muscleGroups.map((g) => g.name).toList()));
    if (state.goal != null) await prefs.setString(_kGoal, state.goal!.name);
    if (state.gender != null) await prefs.setString(_kGender, state.gender!.name);
    await prefs.setDouble(_kHeightCm, state.heightCm);
    await prefs.setDouble(_kHeightIn, state.heightIn);
    await prefs.setDouble(_kWeightKg, state.weightKg);
    await prefs.setDouble(_kWeightLbs, state.weightLbs);
    await prefs.setInt(_kAge, state.age);
  }

  Future<void> _syncToBackend(QuestionnaireState state) async {
    final token = await _auth.getAccessToken();
    if (token == null) return;

    // Determine canonical values (always store metric on server)
    final double weightKg = state.units == UnitSystem.metric
        ? state.weightKg
        : state.weightLbs / 2.20462;
    final double heightCm = state.units == UnitSystem.metric
        ? state.heightCm
        : state.heightIn * 2.54;

    // Map gender enum to backend string
    String? sex;
    switch (state.gender) {
      case Gender.male:
        sex = 'male';
        break;
      case Gender.female:
        sex = 'female';
        break;
      case Gender.nonBinary:
      case Gender.preferNotToSay:
      case null:
        sex = null;
        break;
    }

    // Map unit system to backend string
    final unitSystem = state.units == UnitSystem.metric ? 'metric' : 'imperial';

    // Current year - age = approximate birth year
    final birthYear = DateTime.now().year - state.age;

    // PATCH /v1/me/profile — demographics (+ height for program / nutrition)
    final profileBody = <String, dynamic>{
      'bodyweightKg': double.parse(weightKg.toStringAsFixed(1)),
      'unitSystem': unitSystem,
      'birthYear': birthYear,
      'heightCm': double.parse(heightCm.toStringAsFixed(1)),
      if (sex != null) 'sex': sex,
    };

    try {
      final uri = Uri.parse('$v1Base/me/profile');
      final res = await http.patch(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(profileBody),
      ).withTimeout();
      if (res.statusCode != 200) return;
    } catch (e, st) {
      // Local save already done; backend sync failure is non-fatal during onboarding
      reportError(e, st, reason: 'onboarding:patch-profile');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('profile_height_cm', heightCm);
  }

  /// After onboarding results, persist calculated targets on the user profile.
  Future<void> patchDailyNutritionTargets({
    required int dailyCalories,
    required int dailyProtein,
    required int dailyCarbs,
    required int dailyFat,
  }) async {
    final token = await _auth.getAccessToken();
    if (token == null) return;
    try {
      await http.patch(
        Uri.parse('$v1Base/me/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'dailyCalories': dailyCalories,
          'dailyProtein': dailyProtein,
          'dailyCarbs': dailyCarbs,
          'dailyFat': dailyFat,
        }),
      ).withTimeout();
    } catch (e, st) {
      // Non-fatal: local onboarding already saved
      reportError(e, st, reason: 'onboarding:patch-nutrition-targets');
    }
  }

  /// Greutate metrică salvată local la onboarding (fallback UI dacă profilul server lipsește).
  Future<double?> getSavedWeightKg() async {
    final state = await load();
    if (state == null) return null;
    return state.units == UnitSystem.metric
        ? state.weightKg
        : state.weightLbs / 2.20462;
  }

  /// Re-trimite răspunsurile locale la profil (ex. după ce backend/.env era configurat greșit).
  Future<void> syncSavedQuestionnaireToProfile() async {
    final state = await load();
    if (state == null) return;
    await _syncToBackend(state);
  }

  /// Load previously saved answers (e.g. to pre-fill if user revisits).
  Future<QuestionnaireState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final unitsRaw = prefs.getString(_kUnits);
    if (unitsRaw == null) return null; // never saved

    final state = QuestionnaireState();

    state.units = unitsRaw == 'imperial' ? UnitSystem.imperial : UnitSystem.metric;

    final muscleRaw = prefs.getString(_kMuscleGroups);
    if (muscleRaw != null) {
      final list = (jsonDecode(muscleRaw) as List).cast<String>();
      state.muscleGroups = list
          .map((s) => MuscleGroup.values.firstWhere((g) => g.name == s,
              orElse: () => MuscleGroup.fullBody))
          .toSet();
    }

    final goalRaw = prefs.getString(_kGoal);
    if (goalRaw != null) {
      state.goal = FitnessGoal.values.firstWhere((g) => g.name == goalRaw,
          orElse: () => FitnessGoal.generalFitness);
    }

    final genderRaw = prefs.getString(_kGender);
    if (genderRaw != null) {
      state.gender = Gender.values.firstWhere((g) => g.name == genderRaw,
          orElse: () => Gender.preferNotToSay);
    }

    state.heightCm = prefs.getDouble(_kHeightCm) ?? 170;
    state.heightIn = prefs.getDouble(_kHeightIn) ?? 67;
    state.weightKg = prefs.getDouble(_kWeightKg) ?? 70;
    state.weightLbs = prefs.getDouble(_kWeightLbs) ?? 154;
    state.age = prefs.getInt(_kAge) ?? 25;

    return state;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Onboarding v2 — full profile sync
  // ─────────────────────────────────────────────────────────────────────────

  /// Sex code from the v2 flow ('m'/'f'/'x') → backend canonical string.
  String? _sexFromCode(String? code) {
    switch (code) {
      case 'm':
        return 'male';
      case 'f':
        return 'female';
      case 'x':
        return 'other';
      default:
        return null;
    }
  }

  /// Fire-and-forget prewarm of the weekly-plan generation as soon as the
  /// user submits their free-text goal in `_StepAITalk`. The user still has
  /// ~9 data-collection steps before the loading screen, so by the time
  /// `completeOnboarding` runs, the DeepSeek call is either finished or
  /// nearly so — saving 15-60s of perceived wait.
  ///
  /// Idempotent for the same `goalText`: calling twice in a row with the
  /// same value returns the existing Future without firing a second call.
  /// Calling with a different goalText overrides — useful if the user
  /// rewrites their vision before completion (though _StepAITalk doesn't
  /// currently allow that).
  ///
  /// Errors on the in-flight call are swallowed; `completeOnboarding` will
  /// transparently retry with a fresh call if the prewarm threw.
  void prewarmPlanFromGoal({
    required String goalText,
    String? primaryGoal,
  }) {
    final trimmed = goalText.trim();
    if (trimmed.isEmpty) return;
    if (_prewarmedPlan != null && _prewarmedGoalText == trimmed) return;
    _prewarmedGoalText = trimmed;
    _prewarmedPlan = _ai.generateOnboardingPlan(<String, dynamic>{
      'userGoal': trimmed,
      if (primaryGoal != null) 'primaryGoal': primaryGoal,
    }).catchError((Object e, StackTrace st) {
      // Swallow but log — completeOnboarding will retry with a full payload
      // that includes body stats / PRs, which often makes the second call
      // succeed even when this one timed out on the early data.
      debugPrint('[onboarding] plan prewarm failed: $e');
      return <String, dynamic>{};
    });
  }

  /// Push the full v2 onboarding answer set to the backend.
  ///
  /// 1. `PATCH /v1/me/profile` — core demographics (name, weight, height, sex,
  ///    birth year, unit system).
  /// 2. `PATCH /v1/me/settings` — archetype/goal/experience/PRs/cadence/source +
  ///    permission intents + followed-social list + proTrial intent.
  /// 3. `POST /v1/ai/onboarding-plan` — best-effort starter plan.
  ///
  /// Each phase invokes [onPhase] when the result enum is set. Errors on any
  /// phase don't throw — they accumulate in [OnboardingResult.errors] so the
  /// loading UI can either retry or move on.
  Future<OnboardingResult> completeOnboarding(
    OnboardingPayload p, {
    void Function(OnboardingPhase phase, double progress)? onPhase,
  }) async {
    final errors = <String>[];
    var profileOk = false;
    var settingsOk = false;
    Map<String, dynamic>? plan;

    // Phase 1: core profile (0 → 30%).
    onPhase?.call(OnboardingPhase.savingProfile, 0);
    try {
      final birthYear =
          p.age != null ? DateTime.now().year - p.age!.round() : null;
      final displayName = p.name?.trim();
      await _profile.updateProfile(
        displayName:
            (displayName == null || displayName.isEmpty) ? null : displayName,
        bodyweightKg: p.weight == null
            ? null
            : double.parse(p.weight!.toStringAsFixed(1)),
        heightCm: p.height == null
            ? null
            : double.parse(p.height!.toStringAsFixed(1)),
        sex: _sexFromCode(p.sex),
        birthYear: birthYear,
        unitSystem: p.units,
      );
      profileOk = true;
    } catch (e) {
      errors.add('profile: $e');
    }
    onPhase?.call(OnboardingPhase.savingProfile, 0.3);

    // Phase 2: extended settings (30 → 60%). The backend may not yet recognize
    // every key — server is expected to ignore unknown fields; on 404 we still
    // mark the flow as complete locally (data is in SharedPreferences mirror).
    onPhase?.call(OnboardingPhase.savingSettings, 0.3);
    final settingsPayload = <String, dynamic>{
      if (p.archetype != null) 'archetype': p.archetype,
      if (p.goal != null) 'primaryGoal': p.goal,
      if (p.experience != null) 'experience': p.experience,
      if (p.cadence != null) 'cadence': p.cadence,
      if (p.source != null) 'source': p.source,
      if (p.signInMethod != null) 'signInMethod': p.signInMethod,
      if (p.aiVision != null && p.aiVision!.isNotEmpty) 'aiVision': p.aiVision,
      if (p.dietary.isNotEmpty) 'dietaryRestrictions': p.dietary,
      'gymPrs': <String, dynamic>{
        if (p.bench != null) 'benchKg': p.bench,
        if (p.squat != null) 'squatKg': p.squat,
        if (p.dead != null) 'deadKg': p.dead,
      },
      'cardioPrs': <String, dynamic>{
        if (p.runPace != null && p.runPace!.isNotEmpty) 'fiveKTime': p.runPace,
        if (p.bikeKm != null && p.bikeKm!.isNotEmpty) 'longestRideKm': p.bikeKm,
      },
      'permissions': p.permissions,
      'followedSocial': p.followed,
      'proTrial': p.proTrial,
      'photoTaken': p.photoTaken,
    };
    try {
      await _profile.updateSettings(settingsPayload);
      settingsOk = true;
    } on SettingsUpdateException catch (e) {
      // 404 = endpoint not yet deployed → tolerate silently per task brief.
      if (e.statusCode == 404) {
        settingsOk = true;
      } else {
        errors.add('settings: ${e.message}');
      }
    } catch (e) {
      errors.add('settings: $e');
    }
    onPhase?.call(OnboardingPhase.savingSettings, 0.6);

    // Also persist a local mirror so a later retry has data even if both
    // PATCH calls failed (e.g. user offline).
    await _persistLocalMirror(p, settingsPayload);

    // Persist the user's free-text goal into the training profile so future
    // workout-suggestion + weekly-plan calls see it. Without this, the
    // ai-workout-suggestion service reads an empty onboardingGoalText and
    // falls back to generic enum-based picks unrelated to what the user said.
    final aiVisionText = p.aiVision?.trim();
    if (aiVisionText != null && aiVisionText.isNotEmpty) {
      try {
        await TrainingProfileService().patch({
          'onboardingGoalText': aiVisionText,
          if (p.goal != null) 'primaryGoal': p.goal,
        });
      } catch (e) {
        errors.add('goalText: $e');
      }
    }

    // Phase 3: best-effort plan generation (60 → 100%).
    onPhase?.call(OnboardingPhase.generatingPlan, 0.6);
    try {
      // If _StepAITalk already kicked off a prewarm for the same goal text,
      // reuse its in-flight Future so the loading screen doesn't fire a
      // second DeepSeek call. Falls through to a fresh call when the
      // prewarm didn't happen, raced, or used a different goal.
      // The prewarm (fired at the AI-talk step, before Body Stats) doesn't know
      // the user's dietary restrictions yet — so when they set any, skip the
      // cached plan and regenerate with them so the meal targets actually honor
      // the restrictions. No restrictions → reuse the prewarm for speed.
      final prewarm = p.dietary.isEmpty ? _prewarmedPlan : null;
      final prewarmGoal = _prewarmedGoalText?.trim();
      if (prewarm != null && prewarmGoal != null && prewarmGoal == aiVisionText) {
        try {
          plan = await prewarm;
        } catch (_) {
          plan = null; // fall through and retry below
        } finally {
          _prewarmedPlan = null;
          _prewarmedGoalText = null;
        }
      }
      plan ??= await _ai.generateOnboardingPlan(<String, dynamic>{
        if (p.archetype != null) 'archetype': p.archetype,
        if (p.goal != null) 'primaryGoal': p.goal,
        if (p.experience != null) 'experience': p.experience,
        if (p.cadence != null) 'cadence': p.cadence,
        if (_sexFromCode(p.sex) != null) 'sex': _sexFromCode(p.sex),
        if (p.height != null) 'heightCm': p.height,
        if (p.weight != null) 'weightKg': p.weight,
        if (p.bench != null) 'benchKg': p.bench,
        if (p.squat != null) 'squatKg': p.squat,
        if (p.dead != null) 'deadKg': p.dead,
        // Send the AI vision as `userGoal` — the key that ai_chat_service
        // actually reads when building the `goalText` body for /v1/ai/weekly-plan.
        // Previously sent as `vision`, which was silently dropped → empty
        // goalText → no goalAdvice generated → no CoachTipCard in Train tab.
        if (aiVisionText != null && aiVisionText.isNotEmpty)
          'userGoal': aiVisionText,
        if (p.dietary.isNotEmpty) 'dietary': p.dietary,
      });
    } catch (e) {
      // Plan generation is best-effort; user can still finish onboarding.
      errors.add('plan: $e');
    }

    // Prewarm the nutrition meal plan + the Train AI workout suggestion in the
    // background now that the profile + goal are saved server-side. By the time
    // the user taps through the remaining reveal/community steps and opens the
    // Nutrition / Train tabs, the data is ready — no 30-120s spinner on entry.
    // Fire-and-forget; the tabs still self-generate as a fallback if these
    // haven't finished.
    unawaited(() async {
      try {
        await NutritionService.instance.generateWeeklyPlan();
      } catch (e) {
        debugPrint('[onboarding] nutrition prewarm failed: $e');
      }
      try {
        await WorkoutService().getWorkoutSuggestion();
      } catch (e) {
        debugPrint('[onboarding] workout-suggestion prewarm failed: $e');
      }
    }());

    onPhase?.call(OnboardingPhase.done, 1.0);

    return OnboardingResult(
      profileSynced: profileOk,
      settingsSynced: settingsOk,
      plan: plan,
      errors: errors,
    );
  }

  /// Mirror the v2 payload locally so an offline-first launch can either
  /// pre-fill profile screens or retry the sync later.
  Future<void> _persistLocalMirror(
    OnboardingPayload p,
    Map<String, dynamic> settingsPayload,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ob_v2_settings', jsonEncode(settingsPayload));
      if (p.weight != null) await prefs.setDouble(_kWeightKg, p.weight!);
      if (p.height != null) await prefs.setDouble(_kHeightCm, p.height!);
      if (p.age != null) await prefs.setInt(_kAge, p.age!.round());
      await prefs.setString(_kUnits, p.units);
    } catch (e, st) {
      // Local mirror is non-fatal — backend sync above is the source of truth.
      reportError(e, st, reason: 'onboarding:persist-local-mirror');
    }
  }

  /// Direct REST call used by callers that already serialized the payload —
  /// kept here so the v2 onboarding can also push raw JSON when the typed
  /// PATCH path is missing a field on a given build.
  Future<bool> rawPatch(String pathFromV1, Map<String, dynamic> body) async {
    final token = await _auth.getAccessToken();
    if (token == null) return false;
    try {
      final res = await http.patch(
        Uri.parse('$v1Base/$pathFromV1'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      ).withTimeout();
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e, st) {
      reportError(e, st, reason: 'onboarding:raw-patch');
      return false;
    }
  }
}
