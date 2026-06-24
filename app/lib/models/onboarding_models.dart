import 'package:flutter/material.dart' show IconData;
import 'package:zvelt_app/theme/app_icons.dart';

/// Shared models for onboarding questionnaire and OnboardingService.
/// Kept in a separate file so the service can import without circular dependency.

enum UnitSystem { metric, imperial }

enum MuscleGroup { chest, back, shoulders, arms, core, legs, glutes, fullBody }

enum FitnessGoal { strength, hypertrophy, explosivePower, generalFitness, weightLoss }

enum Gender { male, female, nonBinary, preferNotToSay }

extension MuscleGroupLabel on MuscleGroup {
  String get label {
    switch (this) {
      case MuscleGroup.chest: return 'Chest';
      case MuscleGroup.back: return 'Back';
      case MuscleGroup.shoulders: return 'Shoulders';
      case MuscleGroup.arms: return 'Arms';
      case MuscleGroup.core: return 'Core';
      case MuscleGroup.legs: return 'Legs';
      case MuscleGroup.glutes: return 'Glutes';
      case MuscleGroup.fullBody: return 'Full Body';
    }
  }

  IconData get icon {
    switch (this) {
      case MuscleGroup.chest: return AppIcons.gym;
      case MuscleGroup.back: return AppIcons.arrow_small_up;
      case MuscleGroup.shoulders: return AppIcons.angle_small_down;
      case MuscleGroup.arms: return AppIcons.gym;
      case MuscleGroup.core: return AppIcons.square;
      case MuscleGroup.legs: return AppIcons.running;
      case MuscleGroup.glutes: return AppIcons.user;
      case MuscleGroup.fullBody: return AppIcons.user;
    }
  }
}

extension FitnessGoalLabel on FitnessGoal {
  String get label {
    switch (this) {
      case FitnessGoal.strength: return 'Max Strength';
      case FitnessGoal.hypertrophy: return 'Muscle Mass';
      case FitnessGoal.explosivePower: return 'Explosive Power';
      case FitnessGoal.generalFitness: return 'General Fitness';
      case FitnessGoal.weightLoss: return 'Weight Loss';
    }
  }

  String get subtitle {
    switch (this) {
      case FitnessGoal.strength: return 'Lift heavier, increase 1RM';
      case FitnessGoal.hypertrophy: return 'Build size and definition';
      case FitnessGoal.explosivePower: return 'Speed, jumps, athleticism';
      case FitnessGoal.generalFitness: return 'Stay active and healthy';
      case FitnessGoal.weightLoss: return 'Burn fat, get lean';
    }
  }
}

extension GenderLabel on Gender {
  String get label {
    switch (this) {
      case Gender.male: return 'Male';
      case Gender.female: return 'Female';
      case Gender.nonBinary: return 'Non-binary';
      case Gender.preferNotToSay: return 'Prefer not to say';
    }
  }
}

enum ActivityLevel {
  sedentary,
  lightlyActive,
  moderatelyActive,
  veryActive,
  extremelyActive,
}

extension ActivityLevelExt on ActivityLevel {
  String get label {
    switch (this) {
      case ActivityLevel.sedentary:
        return 'Sedentary';
      case ActivityLevel.lightlyActive:
        return 'Lightly Active';
      case ActivityLevel.moderatelyActive:
        return 'Moderately Active';
      case ActivityLevel.veryActive:
        return 'Very Active';
      case ActivityLevel.extremelyActive:
        return 'Extremely Active';
    }
  }

  String get subtitle {
    switch (this) {
      case ActivityLevel.sedentary:
        return 'Office job, little to no exercise';
      case ActivityLevel.lightlyActive:
        return '1–3 workouts/week';
      case ActivityLevel.moderatelyActive:
        return '3–5 workouts/week';
      case ActivityLevel.veryActive:
        return '6–7 workouts/week';
      case ActivityLevel.extremelyActive:
        return 'Physical job + daily training';
    }
  }

  double get multiplier {
    switch (this) {
      case ActivityLevel.sedentary:
        return 1.2;
      case ActivityLevel.lightlyActive:
        return 1.375;
      case ActivityLevel.moderatelyActive:
        return 1.55;
      case ActivityLevel.veryActive:
        return 1.725;
      case ActivityLevel.extremelyActive:
        return 1.9;
    }
  }
}

/// State object for the onboarding questionnaire; used by UI and OnboardingService.
class QuestionnaireState {
  UnitSystem units = UnitSystem.metric;
  Set<MuscleGroup> muscleGroups = {};
  FitnessGoal? goal;
  Gender? gender;
  double heightCm = 170;
  double heightIn = 67; // 5'7"
  double weightKg = 70;
  double weightLbs = 154;
  int age = 25;
}
