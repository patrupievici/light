import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import 'workout_service.dart';

/// Bridge Flutter ↔ Apple Watch via WatchConnectivity method/event channels.
/// On non-iOS or when watch is unavailable, calls are silently no-ops.
class WatchConnectivityService {
  WatchConnectivityService._();
  static final WatchConnectivityService instance = WatchConnectivityService._();

  static const _method = MethodChannel('com.lunaoscar.zvelt/watch');
  static const _events = EventChannel('com.lunaoscar.zvelt/watch_events');

  Stream<Map<String, dynamic>>? _incomingStream;

  /// Sends the active workout state to the paired Apple Watch.
  Future<void> sendWorkoutState(WorkoutDto workout) async {
    try {
      final lastSet = _lastSet(workout);
      final currentExercise = _currentExercise(workout);
      await _method.invokeMethod<void>('sendWorkoutState', {
        'currentExercise': currentExercise,
        'startedAt': workout.startedAt.toIso8601String(),
        if (lastSet != null) 'lastSet': lastSet,
      });
    } catch (e) {
      // Watch not available — best-effort no-op
      debugPrint('[WatchConnectivity.sendWorkoutState] best-effort skip: $e');
    }
  }

  /// Sends idle state (streak, XP, level) to the watch.
  Future<void> sendIdleState({
    required int streak,
    required int xp,
    required String level,
  }) async {
    try {
      await _method.invokeMethod<void>('sendIdleState', {
        'streak': streak,
        'xp': xp,
        'level': level,
      });
    } catch (e) {
      // Watch not available — best-effort no-op
      debugPrint('[WatchConnectivity.sendIdleState] best-effort skip: $e');
    }
  }

  /// Stream of incoming messages from the Apple Watch (e.g. logSet, completeWorkout).
  Stream<Map<String, dynamic>> get incomingMessages {
    _incomingStream ??= _events
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
    return _incomingStream!;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static String? _currentExercise(WorkoutDto workout) {
    for (final we in workout.exercises) {
      final pending = we.sets.where((s) => !s.isCompleted);
      if (pending.isNotEmpty) return we.exercise.name;
    }
    return workout.exercises.isNotEmpty ? workout.exercises.last.exercise.name : null;
  }

  static Map<String, dynamic>? _lastSet(WorkoutDto workout) {
    for (final we in workout.exercises.reversed) {
      final done = we.sets.where((s) => s.isCompleted).toList();
      if (done.isNotEmpty) {
        final s = done.last;
        return {'weightKg': s.weightKg, 'reps': s.reps};
      }
    }
    return null;
  }
}
