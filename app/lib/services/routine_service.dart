import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart' show v1Base;
import 'auth_service.dart';
import 'http_client.dart';

/// One exercise slot in a saved routine (mirrors the backend exercisesJson item).
class RoutineExercise {
  RoutineExercise({
    required this.name,
    this.exerciseId,
    this.sets,
    this.reps,
    this.restSeconds,
    this.notes,
  });

  final String name;
  final String? exerciseId;
  final int? sets;
  final int? reps;
  final int? restSeconds;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (exerciseId != null) 'exerciseId': exerciseId,
        if (sets != null) 'sets': sets,
        if (reps != null) 'reps': reps,
        if (restSeconds != null) 'restSeconds': restSeconds,
        if (notes != null) 'notes': notes,
      };

  static RoutineExercise fromJson(Map<String, dynamic> j) => RoutineExercise(
        name: j['name'] as String? ?? 'Exercise',
        exerciseId: j['exerciseId'] as String?,
        sets: (j['sets'] as num?)?.toInt(),
        reps: (j['reps'] as num?)?.toInt(),
        restSeconds: (j['restSeconds'] as num?)?.toInt(),
        notes: j['notes'] as String?,
      );
}

/// A reusable workout template (mockup 4 "Routines").
class Routine {
  Routine({
    required this.id,
    required this.name,
    this.focus,
    required this.exerciseCount,
    required this.exercises,
  });

  final String id;
  final String name;
  final String? focus;
  final int exerciseCount;
  final List<RoutineExercise> exercises;

  static Routine fromJson(Map<String, dynamic> j) => Routine(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Routine',
        focus: j['focus'] as String?,
        exerciseCount: (j['exerciseCount'] as num?)?.toInt() ?? 0,
        exercises: (j['exercises'] as List<dynamic>? ?? [])
            .map((e) => RoutineExercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Saved routines (mockup 4): list, create, edit, delete, and start-as-workout.
class RoutineService {
  final _auth = AuthService();
  Future<Map<String, String>> _headers() => authedJsonHeaders(auth: _auth);

  Future<List<Routine>> getRoutines() async {
    final res = await http
        .get(Uri.parse('$v1Base/routines'), headers: await _headers())
        .withTimeout();
    if (res.statusCode != 200) {
      throw Exception('Could not load routines (${res.statusCode})');
    }
    final data = (jsonDecode(res.body) as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
    return data.map((r) => Routine.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<Routine> createRoutine({
    required String name,
    String? focus,
    required List<RoutineExercise> exercises,
  }) async {
    final res = await http
        .post(
          Uri.parse('$v1Base/routines'),
          headers: await _headers(),
          body: jsonEncode({
            'name': name,
            if (focus != null && focus.isNotEmpty) 'focus': focus,
            'exercises': exercises.map((e) => e.toJson()).toList(),
          }),
        )
        .withTimeout();
    if (res.statusCode != 201) {
      throw Exception('Could not save routine (${res.statusCode})');
    }
    return Routine.fromJson(
        (jsonDecode(res.body) as Map<String, dynamic>)['routine'] as Map<String, dynamic>);
  }

  Future<void> deleteRoutine(String id) async {
    final res = await http
        .delete(Uri.parse('$v1Base/routines/$id'), headers: await _headers())
        .withTimeout();
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw Exception('Could not delete routine (${res.statusCode})');
    }
  }

  /// Starts the routine → returns the new draft workout id for the tracker.
  Future<String> startRoutine(String id) async {
    final res = await http
        .post(Uri.parse('$v1Base/routines/$id/start'), headers: await _headers())
        .withTimeout();
    if (res.statusCode != 201) {
      throw Exception('Could not start routine (${res.statusCode})');
    }
    final w = (jsonDecode(res.body) as Map<String, dynamic>)['workout'] as Map<String, dynamic>;
    return w['id'] as String;
  }
}
