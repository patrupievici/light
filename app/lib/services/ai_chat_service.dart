import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../config/api_config.dart' show v1Base;
import 'auth_service.dart';
import 'http_client.dart';

/// Per QA P1.6 — enforce a hard 30s ceiling on AI chat endpoints so the UI
/// can surface a timeout state instead of hanging indefinitely.
const Duration kAiChatTimeout = Duration(seconds: 30);

/// Typed exception so the UI layer can branch on timeout vs network vs HTTP.
class AiChatException implements Exception {
  AiChatException(this.message, {this.isTimeout = false, this.isNetworkError = false, this.statusCode});
  final String message;
  final bool isTimeout;
  final bool isNetworkError;
  final int? statusCode;

  @override
  String toString() => message;
}

class AiChatService {
  AiChatService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  // Razvan's typed-throw version — explicit AiChatException is better for
  // crash reporting than a silent null token.
  Future<Map<String, String>> _headers() async {
    final token = await _auth.getAccessToken();
    if (token == null) throw AiChatException('Not signed in', statusCode: 401);
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  void _throwIfError(http.Response res) {
    if (res.statusCode == 200 || res.statusCode == 201) return;
    Map<String, dynamic>? err;
    try { err = jsonDecode(res.body) as Map<String, dynamic>?; } catch (e) {
      debugPrint('[AiChatService._throwIfError] body decode best-effort skip: $e');
    }
    throw AiChatException(
      err?['message']?.toString() ?? 'AI error (${res.statusCode})',
      statusCode: res.statusCode,
    );
  }

  /// Wraps any AI HTTP call with a 30s ceiling and converts errors to [AiChatException].
  Future<http.Response> _run(Future<http.Response> Function() send) async {
    try {
      final res = await send().withAiTimeout(kAiChatTimeout);
      _throwIfError(res);
      return res;
    } on TimeoutException {
      throw AiChatException(
        'AI request timed out after ${kAiChatTimeout.inSeconds}s',
        isTimeout: true,
      );
    } on SocketException catch (e) {
      throw AiChatException('Network unreachable: ${e.message}', isNetworkError: true);
    } on http.ClientException catch (e) {
      throw AiChatException('Network error: ${e.message}', isNetworkError: true);
    } on AiChatException {
      rethrow;
    } catch (e) {
      throw AiChatException(e.toString());
    }
  }

  /// POST /v1/ai/chat
  Future<String> send(List<Map<String, String>> messages) async {
    final res = await _run(() async => http.post(
      Uri.parse('$v1Base/ai/chat'),
      headers: await _headers(),
      body: jsonEncode({'messages': messages}),
    ));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['reply'] as String? ?? '';
  }

  /// POST /v1/ai/trainer
  Future<Map<String, dynamic>> askTrainer(String question, {bool createWorkout = false}) async {
    final res = await _run(() async => http.post(
      Uri.parse('$v1Base/ai/trainer'),
      headers: await _headers(),
      body: jsonEncode({'question': question, 'createWorkout': createWorkout}),
    ));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// POST /v1/ai/weekly-plan
  Future<Map<String, dynamic>> generateWeeklyPlan(Map<String, dynamic> inputs) async {
    final res = await _run(() async => http.post(
      Uri.parse('$v1Base/ai/weekly-plan'),
      headers: await _headers(),
      body: jsonEncode(inputs),
    ));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// POST /v1/ai/goal-interpret
  ///
  /// Fast confirmation call (~1.5s) used by the "AI got me" onboarding moment:
  /// the user has just written their free-text goal and we want to prove the
  /// AI understood before triggering the slow weekly-plan call (~10s).
  ///
  /// Returns null on AI errors so the caller can fall back gracefully
  /// (overlay just doesn't appear; weekly plan still runs).
  Future<GoalInterpretation?> interpretGoal(String goalText) async {
    final trimmed = goalText.trim();
    if (trimmed.length < 3) return null;
    try {
      final res = await http.post(
        Uri.parse('$v1Base/ai/goal-interpret'),
        headers: await _headers(),
        body: jsonEncode({'goalText': trimmed}),
      ).withAiTimeout();
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return GoalInterpretation.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// POST /v1/ai/onboarding-interpret
  Future<Map<String, dynamic>> interpretOnboarding({
    String? gymExperience,
    String? injuriesLimitations,
  }) async {
    final res = await _run(() async => http.post(
      Uri.parse('$v1Base/ai/onboarding-interpret'),
      headers: await _headers(),
      body: jsonEncode({
        if (gymExperience != null) 'gymExperience': gymExperience,
        if (injuriesLimitations != null) 'injuriesLimitations': injuriesLimitations,
      }),
    ));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Generate the complete workout + meal plan from onboarding context.
  /// Backed by `/v1/ai/weekly-plan` (the unified endpoint). The legacy
  /// `/v1/ai/onboarding-plan` is gone — this preserves the old method name
  /// so callers don't have to change, but maps the new payload shape into
  /// the keys the UI already expects.
  /// Map onboarding picker goal ids to the backend's accepted `goal` enum
  /// (fat_loss|maintenance|hypertrophy|strength|calisthenics|explosive_power).
  /// Unknown ids — the picker's 'endurance'/'recomp'/'clarity' have no backend
  /// bucket — return null so we OMIT `goal` instead of sending a value that
  /// fails server-side zod validation and 400s the whole plan request. The
  /// free-text goalText carries the real signal anyway (it's top priority in
  /// the planner prompt), so omitting the enum hint is safe.
  static String? _backendGoalEnum(String id) {
    switch (id) {
      case 'strength':
        return 'strength';
      case 'hypertrophy':
        return 'hypertrophy';
      case 'recomp':
        return 'maintenance';
      case 'fat_loss':
      case 'weightLoss':
        return 'fat_loss';
      case 'calisthenics':
        return 'calisthenics';
      case 'explosivePower':
      case 'explosive_power':
        return 'explosive_power';
      default:
        return null; // endurance, clarity, … — let goalText drive it.
    }
  }

  Future<Map<String, dynamic>> generateOnboardingPlan(Map<String, dynamic> context) async {
    final rawGoal = context['primaryGoal'];
    final goalEnum = rawGoal is String ? _backendGoalEnum(rawGoal) : null;
    final body = <String, dynamic>{
      'goalText': context['userGoal'],
      if (goalEnum != null) 'goal': goalEnum,
      if (context['dietary'] is List && (context['dietary'] as List).isNotEmpty)
        'dietaryRestrictions': context['dietary'],
      if (context['trainingDays'] is num)
        'daysPerWeek': (context['trainingDays'] as num).toInt(),
      if (context['sessionMinutes'] is num)
        'sessionMinutes': (context['sessionMinutes'] as num).toInt(),
      if (context['equipment'] is List) 'equipment': context['equipment'],
      'applyDailyTargets': true,
    };
    final res = await http.post(
      Uri.parse('$v1Base/ai/weekly-plan'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).withAiTimeout();
    _throwIfError(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    // Adapt for the existing onboarding UI which reads `workoutPlan`,
    // `mealPlan`, `goalAdvice`. We rebuild those shapes from the unified
    // weekly-plan response.
    final plan = (data['plan'] as Map?)?.cast<String, dynamic>() ?? const {};
    final weekPlan = (plan['weekPlan'] as List?) ?? const [];
    final dailyTargets =
        (plan['dailyTargets'] as Map?)?.cast<String, dynamic>() ?? const {};
    final trainingDays = weekPlan
        .whereType<Map>()
        .where((d) {
          final w = d['workout'];
          return w is Map && (w['exercises'] as List?)?.isNotEmpty == true;
        })
        .map((d) {
          final w = (d['workout'] as Map).cast<String, dynamic>();
          return {
            'day': d['dayOfWeek'],
            'name': w['name'],
            'focus': w['focus'],
            'exercises': w['exercises'],
          };
        })
        .toList();
    return {
      'workoutPlan': {
        'summary': (plan['notes'] is List && (plan['notes'] as List).isNotEmpty)
            ? (plan['notes'] as List).first
            : '',
        'trainingDays': trainingDays,
        'restDays': weekPlan
            .whereType<Map>()
            .where((d) {
              final w = d['workout'];
              return w is! Map || (w['exercises'] as List?)?.isEmpty != false;
            })
            .map((d) => d['dayOfWeek'])
            .toList(),
      },
      'mealPlan': {
        'dailyTargets': dailyTargets,
        'guidelines': plan['notes'] ?? const [],
      },
      'goalAdvice': data['goalAdvice'] ?? '',
      'plannedWorkouts': data['plannedWorkouts'] ?? const [],
      'generatedAt': DateTime.now().toIso8601String(),
      'model': data['model'],
    };
  }
}

/// Result of `POST /v1/ai/goal-interpret` — the warm "we got you" payload
/// shown in the onboarding intermediate screen before the slow plan runs.
class GoalInterpretation {
  const GoalInterpretation({
    required this.paraphrase,
    required this.priorities,
    this.intentLabel,
  });

  /// 1-2 sentences confirming the AI's understanding of the goal.
  final String paraphrase;

  /// 3-5 short bullet items describing what the plan will focus on.
  final List<String> priorities;

  /// One of: 'jump' | 'sprint' | 'strength' | 'calisthenics' | 'fat_loss'
  /// | 'hypertrophy' | 'endurance' | null. Used for icon / styling hints.
  final String? intentLabel;

  static GoalInterpretation fromJson(Map<String, dynamic> j) {
    final priorities = (j['priorities'] as List?)
            ?.map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    return GoalInterpretation(
      paraphrase: (j['paraphrase'] as String?)?.trim() ?? '',
      priorities: priorities,
      intentLabel: (j['intentLabel'] as String?)?.trim().isNotEmpty == true
          ? j['intentLabel'] as String
          : null,
    );
  }
}
