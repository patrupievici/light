import '../services/workout_service.dart';
import '../utils/formatters.dart';

/// Linie afișată pentru un set completat (fără greutate când nu e cazul).
String formatLoggedSetLine(WorkoutSetDto s, ExerciseDto ex) {
  final mode = setLogModeForExercise(ex);
  final rpe = s.rpe != null ? ' @ RPE ${s.rpe!.toStringAsFixed(1)}' : '';
  switch (mode) {
    case SetLogMode.timeSeconds:
      return 'Set ${s.setIndex + 1}: ${s.weightKg.round()}s hold$rpe';
    case SetLogMode.bodyweightReps:
      return 'Set ${s.setIndex + 1}: ${s.reps} reps$rpe';
    case SetLogMode.weighted:
      // Unit-aware (kg/lb per user pref); storage stays canonical kg.
      return 'Set ${s.setIndex + 1}: ${formatWeight(s.weightKg)} × ${s.reps} reps$rpe';
  }
}

/// Cum se loghează un set în tracker (UI + valori trimise la API).
enum SetLogMode {
  /// Greutate externă (bară, gantere, mașină cu stack).
  weighted,

  /// Fără încărcare externă: doar reps (+ RPE). `weightKg` = 0.
  bodyweightReps,

  /// Hold / timp: `weightKg` stochează secunde, `reps` = 1.
  timeSeconds,
}

/// Nume din seed care nu folosesc încărcare externă (când `category` lipsește din DB).
const _kBodyweightPlyoAndSprintNames = {
  'box jump',
  'box jumps',
  'vertical jump',
  'vertical jumps',
  'broad jump',
  'broad jumps',
  'jump squat',
  'jump squats',
  'depth jump',
  'depth jumps',
  'lateral bound',
  'lateral bounds',
  'burpee',
  'burpees',
  'sprint 40m',
  'clap push-up',
  'clap push up',
  'clap pushups',
};

/// Exerciții fără greutate externă (ex. box jump, sprint) — același catalog ca seed-ul backend.
SetLogMode setLogModeForExercise(ExerciseDto e) {
  final rank = (e.rankModel ?? 'WEIGHTED').toUpperCase();
  if (rank == 'TIME') {
    return SetLogMode.timeSeconds;
  }
  // Aliniat cu backend (Prisma): BW_REPS = calistenics / greutate corporală, fără încărcare externă.
  if (rank == 'BW_REPS') {
    return SetLogMode.bodyweightReps;
  }

  final nameNorm = e.name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  if (_kBodyweightPlyoAndSprintNames.contains(nameNorm)) {
    return SetLogMode.bodyweightReps;
  }

  final eq = (e.equipment ?? '').toLowerCase();
  final cat = (e.category ?? '').toLowerCase();
  final pattern = (e.movementPattern ?? '').toLowerCase();

  final isBw = eq == 'bodyweight';

  // Exerciții custom marcate calisthenics + bodyweight fără rankModel setat corect în DB.
  if (isBw && e.goalTags.any((t) => t.toLowerCase() == 'calisthenics')) {
    return SetLogMode.bodyweightReps;
  }

  // Power Clean etc. au același pattern dar barbell — doar BW.
  if (pattern == 'jump_throw_sprint' && isBw) {
    return SetLogMode.bodyweightReps;
  }

  if (isBw && cat == 'explosive') {
    return SetLogMode.bodyweightReps;
  }
  if (isBw && pattern == 'locomotion_conditioning') {
    return SetLogMode.bodyweightReps;
  }

  return SetLogMode.weighted;
}
