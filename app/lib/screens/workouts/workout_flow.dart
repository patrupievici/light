import 'package:flutter/material.dart';

import '../../services/planned_workouts_service.dart';
import '../../services/workout_service.dart';
import '../../theme/zvelt_tokens.dart';
import 'quick_launch_sheet.dart';

/// Single entry for starting gym/cardio sessions or resuming drafts.
class WorkoutFlow {
  WorkoutFlow._();

  static Future<void> openPreset(BuildContext context, FabPreset preset) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => ActiveWorkoutView(preset: preset)),
    );
  }

  static Future<void> openExistingWorkout(BuildContext context, String workoutId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ActiveWorkoutView.forExistingWorkout(workoutId: workoutId),
      ),
    );
  }

  static Future<void> openRun(BuildContext context) async {
    final preset = fabPresetById('run');
    if (preset != null) await openPreset(context, preset);
  }

  static Future<void> startSuggestedOrEmpty(BuildContext context) async {
    WorkoutDto created;
    try {
      created = await WorkoutService().createWorkoutFromSuggestion();
    } catch (_) {
      created = await WorkoutService().createWorkout();
    }
    if (!context.mounted) return;
    await openExistingWorkout(context, created.id);
  }

  /// Materialize an AI-planned day into a real Workout and open the tracker.
  /// Surfaces unresolved AI exercise names via a snackbar so the user knows
  /// when the AI suggested something the catalog can't back.
  static Future<void> startPlannedWorkout(BuildContext context, String plannedWorkoutId) async {
    StartFromPlannedResult result;
    try {
      result = await PlannedWorkoutsService().startFromPlanned(plannedWorkoutId);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: ZveltTokens.error,
        ),
      );
      return;
    }
    if (!context.mounted) return;
    if (result.unresolved.isNotEmpty) {
      final list = result.unresolved.take(3).join(', ');
      final more = result.unresolved.length > 3 ? ' (+${result.unresolved.length - 3} more)' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Skipped exercises not in catalog: $list$more"),
          backgroundColor: ZveltTokens.warn,
        ),
      );
    }
    await openExistingWorkout(context, result.workoutId);
  }
}
