import 'package:flutter/material.dart';

import '../screens/workouts/post_workout_screen.dart';

/// Unified entry for “share to feed” after workouts, streak nudges, or XP screens.
class PostPromptSheet {
  PostPromptSheet._();

  static Future<bool?> open(
    BuildContext context, {
    String? workoutId,
    String? initialCaption,
    bool showSnackOnSuccess = true,
  }) async {
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PostWorkoutScreen(
          workoutId: workoutId,
          initialCaption: initialCaption,
        ),
      ),
    );
    if (posted == true && showSnackOnSuccess && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workout shared to your feed')),
      );
    }
    return posted;
  }
}
