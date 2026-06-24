import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart' show v1Base;
import '../models/onboarding_models.dart' show ActivityLevel, FitnessGoal;
import '../models/training_profile_models.dart';
import '_crash_reporter.dart';
import 'app_data_cache.dart';
import 'auth_service.dart';
import 'http_client.dart';

/// `GET/PATCH /v1/me/training-profile`
class TrainingProfileService {
  TrainingProfileService({AuthService? auth}) : _auth = auth ?? AuthService();

  final AuthService _auth;

  static int? suggestedDaysFromActivity(ActivityLevel? level) {
    switch (level) {
      case ActivityLevel.sedentary:
      case ActivityLevel.lightlyActive:
        return 3;
      case ActivityLevel.moderatelyActive:
        return 4;
      case ActivityLevel.veryActive:
        return 5;
      case ActivityLevel.extremelyActive:
        return 6;
      case null:
        return null;
    }
  }

  Future<TrainingProfile?> fetch({bool refresh = false}) async {
    if (!refresh) {
      final cached = await AppDataCache.instance.loadTrainingProfile();
      if (cached != null) {
        return TrainingProfile.fromJson(cached);
      }
    }

    try {
      final res = await http.get(
        Uri.parse('$v1Base/me/training-profile'),
        headers: await authedReadHeaders(auth: _auth),
      ).withTimeout();
      if (res.statusCode != 200) {
        final cached = await AppDataCache.instance.loadTrainingProfile();
        return cached != null ? TrainingProfile.fromJson(cached) : null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tp = data['trainingProfile'] as Map<String, dynamic>?;
      if (tp == null) return null;
      await AppDataCache.instance.saveTrainingProfile(tp);
      return TrainingProfile.fromJson(tp);
    } catch (e, st) {
      // Razvan: report to Crashlytics. Mine: fall back to cache for offline.
      reportError(e, st, reason: 'training-profile:fetch');
      final cached = await AppDataCache.instance.loadTrainingProfile();
      return cached != null ? TrainingProfile.fromJson(cached) : null;
    }
  }

  /// Update just the free-text goal (Goal Evolution flow). PATCHes the
  /// training profile and invalidates the local cache so the next fetch
  /// returns the new value. Returns true on HTTP 200, false otherwise.
  Future<bool> updateGoalText(String newGoalText) async {
    final trimmed = newGoalText.trim();
    if (trimmed.isEmpty) return false;
    try {
      final res = await http.patch(
        Uri.parse('$v1Base/me/training-profile'),
        headers: await authedJsonHeaders(auth: _auth),
        body: jsonEncode({'onboardingGoalText': trimmed}),
      ).withTimeout();
      if (res.statusCode != 200) return false;
      // Force-refresh local cache so callers using fetch() without
      // `refresh: true` still see the new goal text.
      await AppDataCache.instance.clearTrainingProfile();
      return true;
    } catch (e, st) {
      reportError(e, st, reason: 'training-profile:update-goal');
      return false;
    }
  }

  /// First sync after questionnaire: sends mapped primary goal + heuristic days + flag.
  Future<bool> syncAfterOnboarding({
    required FitnessGoal? goal,
    ActivityLevel? activityLevel,
  }) async {
    final primary = mapFitnessGoalToPrimaryGoal(goal);
    final days = suggestedDaysFromActivity(activityLevel);

    final body = <String, dynamic>{
      if (primary != null) 'primaryGoal': primary,
      if (days != null) 'daysPerWeek': days,
      'onboardingCompleted': true,
    };

    try {
      final res = await http.patch(
        Uri.parse('$v1Base/me/training-profile'),
        headers: await authedJsonHeaders(auth: _auth),
        body: jsonEncode(body),
      ).withTimeout();
      return res.statusCode == 200;
    } catch (e, st) {
      reportError(e, st, reason: 'training-profile:sync-onboarding');
      return false;
    }
  }

  /// Full patch (for future settings UI).
  Future<TrainingProfile?> patch(Map<String, dynamic> body) async {
    try {
      final res = await http.patch(
        Uri.parse('$v1Base/me/training-profile'),
        headers: await authedJsonHeaders(auth: _auth),
        body: jsonEncode(body),
      ).withTimeout();
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tp = data['trainingProfile'] as Map<String, dynamic>?;
      if (tp == null) return null;
      await AppDataCache.instance.saveTrainingProfile(tp);
      return TrainingProfile.fromJson(tp);
    } catch (e, st) {
      reportError(e, st, reason: 'training-profile:patch');
      return null;
    }
  }
}
