import 'onboarding_models.dart';

// ─── Enums (aligned with backend `training-profile.ts`) ────────────────────

enum PrimaryTrainingGoal {
  fatLoss,
  maintenance,
  hypertrophy,
  strength,
  calisthenics,
  explosivePower,
  verticalJump,
}

extension PrimaryTrainingGoalX on PrimaryTrainingGoal {
  String get apiValue => switch (this) {
        PrimaryTrainingGoal.fatLoss => 'fat_loss',
        PrimaryTrainingGoal.maintenance => 'maintenance',
        PrimaryTrainingGoal.hypertrophy => 'hypertrophy',
        PrimaryTrainingGoal.strength => 'strength',
        PrimaryTrainingGoal.calisthenics => 'calisthenics',
        PrimaryTrainingGoal.explosivePower => 'explosive_power',
        PrimaryTrainingGoal.verticalJump => 'vertical_jump',
      };

  String get label => switch (this) {
        PrimaryTrainingGoal.fatLoss => 'Fat loss',
        PrimaryTrainingGoal.maintenance => 'Maintenance',
        PrimaryTrainingGoal.hypertrophy => 'Muscle gain',
        PrimaryTrainingGoal.strength => 'Max strength',
        PrimaryTrainingGoal.calisthenics => 'Calisthenics',
        PrimaryTrainingGoal.explosivePower => 'Explosive power',
        PrimaryTrainingGoal.verticalJump => 'Vertical jump',
      };

  String get subtitle => switch (this) {
        PrimaryTrainingGoal.fatLoss =>
          'Keep muscle, sustainable deficit, simple progression',
        PrimaryTrainingGoal.maintenance =>
          'Stay strong with minimal effective dose',
        PrimaryTrainingGoal.hypertrophy => 'Build size — volume & frequency',
        PrimaryTrainingGoal.strength => 'Squat, hinge, press, pull — heavy work',
        PrimaryTrainingGoal.calisthenics =>
          'Relative strength, skills, bodyweight progressions',
        PrimaryTrainingGoal.explosivePower =>
          'Jumps, throws, speed — quality over fatigue',
        PrimaryTrainingGoal.verticalJump =>
          'Strength + plyometrics + sprint mechanics',
      };
}

/// Maps to legacy [FitnessGoal] for TDEE / protein heuristics in onboarding.
FitnessGoal legacyFitnessGoalFromPrimary(PrimaryTrainingGoal p) => switch (p) {
      PrimaryTrainingGoal.fatLoss => FitnessGoal.weightLoss,
      PrimaryTrainingGoal.maintenance => FitnessGoal.generalFitness,
      PrimaryTrainingGoal.hypertrophy => FitnessGoal.hypertrophy,
      PrimaryTrainingGoal.strength => FitnessGoal.strength,
      PrimaryTrainingGoal.calisthenics => FitnessGoal.hypertrophy,
      PrimaryTrainingGoal.explosivePower => FitnessGoal.explosivePower,
      PrimaryTrainingGoal.verticalJump => FitnessGoal.explosivePower,
    };

PrimaryTrainingGoal? primaryFromLegacyFitnessGoal(FitnessGoal g) => switch (g) {
      FitnessGoal.weightLoss => PrimaryTrainingGoal.fatLoss,
      FitnessGoal.generalFitness => PrimaryTrainingGoal.maintenance,
      FitnessGoal.hypertrophy => PrimaryTrainingGoal.hypertrophy,
      FitnessGoal.strength => PrimaryTrainingGoal.strength,
      FitnessGoal.explosivePower => PrimaryTrainingGoal.explosivePower,
    };

enum SecondaryTrainingGoal {
  mobility,
  posture,
  conditioning,
  core,
  endurance,
}

extension SecondaryTrainingGoalX on SecondaryTrainingGoal {
  String get apiValue => name;
  String get label => switch (this) {
        SecondaryTrainingGoal.mobility => 'Mobility',
        SecondaryTrainingGoal.posture => 'Posture',
        SecondaryTrainingGoal.conditioning => 'Conditioning',
        SecondaryTrainingGoal.core => 'Core',
        SecondaryTrainingGoal.endurance => 'Endurance',
      };
}

enum UserTrainingLevel { beginner, novice, intermediate, advanced }

extension UserTrainingLevelX on UserTrainingLevel {
  String get apiValue => name;
  String get label => switch (this) {
        UserTrainingLevel.beginner => 'Beginner',
        UserTrainingLevel.novice => 'Novice',
        UserTrainingLevel.intermediate => 'Intermediate',
        UserTrainingLevel.advanced => 'Advanced',
      };
  String get subtitle => switch (this) {
        UserTrainingLevel.beginner => '< 6 months consistent training',
        UserTrainingLevel.novice => '6 months – 2 years',
        UserTrainingLevel.intermediate => '2 – 5 years',
        UserTrainingLevel.advanced => '5+ years, serious training',
      };
}

enum TrainingSplitPreference {
  fullBody,
  upperLower,
  pushPullLegs,
  skillBased,
  /// Server-side blueprint default only — not shown in onboarding (conflicts with AI weekly plan flow).
  auto,
}

extension TrainingSplitPreferenceX on TrainingSplitPreference {
  String get apiValue => switch (this) {
        TrainingSplitPreference.fullBody => 'full_body',
        TrainingSplitPreference.upperLower => 'upper_lower',
        TrainingSplitPreference.pushPullLegs => 'push_pull_legs',
        TrainingSplitPreference.skillBased => 'skill_based',
        TrainingSplitPreference.auto => 'auto',
      };
  String get label => switch (this) {
        TrainingSplitPreference.fullBody => 'Full body',
        TrainingSplitPreference.upperLower => 'Upper / lower',
        TrainingSplitPreference.pushPullLegs => 'Push / pull / legs',
        TrainingSplitPreference.skillBased => 'Skill-based',
      TrainingSplitPreference.auto => 'Let Zvelt decide',
      };
}

/// Preset equipment tags (stored as strings on server).
class EquipmentPreset {
  const EquipmentPreset(this.id, this.label);
  final String id;
  final String label;
}

const List<EquipmentPreset> kTrainingEquipmentPresets = [
  EquipmentPreset('bodyweight_only', 'Bodyweight only'),
  EquipmentPreset('dumbbells', 'Dumbbells'),
  EquipmentPreset('barbell_rack', 'Barbell & rack'),
  EquipmentPreset('cables', 'Cables'),
  EquipmentPreset('machines', 'Machines'),
  EquipmentPreset('kettlebells', 'Kettlebells'),
  EquipmentPreset('pullup_bar', 'Pull-up bar'),
  EquipmentPreset('resistance_bands', 'Bands'),
  EquipmentPreset('full_commercial_gym', 'Full gym access'),
];

/// Mirrors backend `UserTrainingProfile` + Zod enums (`training-profile.ts`).
class TrainingProfile {
  const TrainingProfile({
    required this.userId,
    this.primaryGoal,
    this.secondaryGoals = const [],
    this.trainingLevel,
    this.gymExperience,
    this.daysPerWeek,
    this.sessionMinutes,
    this.equipment = const [],
    this.injuriesLimitations,
    this.splitPreference,
    this.onboardingCompleted = false,
    this.onboardingGoalText,
    this.goalAdviceText,
    this.updatedAt,
  });

  final String userId;
  final String? primaryGoal;
  final List<String> secondaryGoals;
  final String? trainingLevel;
  final String? gymExperience;
  final int? daysPerWeek;
  final int? sessionMinutes;
  final List<String> equipment;
  final String? injuriesLimitations;
  final String? splitPreference;
  final bool onboardingCompleted;
  /// Narrativa liberă din onboarding (aceeași ca la plan AI).
  final String? onboardingGoalText;
  /// Al doilea output AI — sfaturi practice pentru obiectiv.
  final String? goalAdviceText;
  final DateTime? updatedAt;

  factory TrainingProfile.fromJson(Map<String, dynamic> json) {
    return TrainingProfile(
      userId: json['userId'] as String? ?? '',
      primaryGoal: json['primaryGoal'] as String?,
      secondaryGoals: (json['secondaryGoals'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      trainingLevel: json['trainingLevel'] as String?,
      gymExperience: json['gymExperience'] as String?,
      daysPerWeek: json['daysPerWeek'] as int?,
      sessionMinutes: json['sessionMinutes'] as int?,
      equipment: (json['equipment'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      injuriesLimitations: json['injuriesLimitations'] as String?,
      splitPreference: json['splitPreference'] as String?,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      onboardingGoalText: json['onboardingGoalText'] as String?,
      goalAdviceText: json['goalAdviceText'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        if (primaryGoal != null) 'primaryGoal': primaryGoal,
        'secondaryGoals': secondaryGoals,
        if (trainingLevel != null) 'trainingLevel': trainingLevel,
        if (gymExperience != null) 'gymExperience': gymExperience,
        if (daysPerWeek != null) 'daysPerWeek': daysPerWeek,
        if (sessionMinutes != null) 'sessionMinutes': sessionMinutes,
        'equipment': equipment,
        if (injuriesLimitations != null) 'injuriesLimitations': injuriesLimitations,
        if (splitPreference != null) 'splitPreference': splitPreference,
        'onboardingCompleted': onboardingCompleted,
        if (onboardingGoalText != null) 'onboardingGoalText': onboardingGoalText,
        if (goalAdviceText != null) 'goalAdviceText': goalAdviceText,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}

/// Map legacy onboarding [FitnessGoal] → API `primary_goal` snake-style keys.
String? mapFitnessGoalToPrimaryGoal(FitnessGoal? goal) {
  if (goal == null) return null;
  return primaryFromLegacyFitnessGoal(goal)?.apiValue;
}
