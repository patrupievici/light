import '../models/social_challenge.dart';

/// Antrenamente din sala + calistenics / fitness — numele sunt aliniate cu `backend/prisma/seed.ts`.
enum ChallengeExerciseTrack {
  gym,
  calisthenicsFitness,
}

extension ChallengeExerciseTrackX on ChallengeExerciseTrack {
  String get label => switch (this) {
        ChallengeExerciseTrack.gym => 'Gym',
        ChallengeExerciseTrack.calisthenicsFitness => 'Calisthenics & fitness',
      };
}

/// O linie din picker: cum apare în UI și cum se mapează la `POST /v1/challenges`.
class ChallengeCatalogEntry {
  const ChallengeCatalogEntry({
    required this.id,
    required this.displayName,
    required this.track,
    required this.apiKind,
    this.fixedCustomTitle,
    this.requiresManualTitle = false,
  }) : assert(!requiresManualTitle || apiKind == SocialChallengeKind.custom);

  /// Slug stabil (persistare UI / comparații).
  final String id;
  final String displayName;
  final ChallengeExerciseTrack track;

  /// Patru preseturi API sau [SocialChallengeKind.custom] pentru nume liber.
  final SocialChallengeKind apiKind;

  /// Dacă e custom dar nu „Other”, titlul trimis la API (dacă null → [displayName]).
  final String? fixedCustomTitle;

  /// `true` doar pentru „Other (custom title)” — utilizatorul completează în sheet.
  final bool requiresManualTitle;

  /// Titlu pentru corpul request-ului: gol pentru preseturi non-custom.
  String customTitleForPublish(String manualCustomTitle) {
    if (apiKind != SocialChallengeKind.custom) return '';
    if (requiresManualTitle) return manualCustomTitle.trim();
    return (fixedCustomTitle ?? displayName).trim();
  }
}

/// Intrarea „scrie tu titlul” — mereu la final în picker.
const kChallengeCatalogManualEntry = ChallengeCatalogEntry(
  id: 'custom_manual',
  displayName: 'Other (custom title)',
  track: ChallengeExerciseTrack.gym,
  apiKind: SocialChallengeKind.custom,
  requiresManualTitle: true,
);

ChallengeCatalogEntry _preset(
  String id,
  String displayName,
  ChallengeExerciseTrack track,
  SocialChallengeKind kind,
) =>
    ChallengeCatalogEntry(id: id, displayName: displayName, track: track, apiKind: kind);

ChallengeCatalogEntry _namedCustom(String id, String displayName, ChallengeExerciseTrack track) =>
    ChallengeCatalogEntry(id: id, displayName: displayName, track: track, apiKind: SocialChallengeKind.custom);

/// Lista efective (fără intrarea manuală).
final List<ChallengeCatalogEntry> kChallengeExerciseCatalogCore = [
  // ── Gym (seed: barbell, dumbbell, machine, cable) ─────────────────────────
  _namedCustom('barbell_row', 'Barbell Row', ChallengeExerciseTrack.gym),
  _preset('bench_press', 'Bench Press', ChallengeExerciseTrack.gym, SocialChallengeKind.benchPress),
  _namedCustom('cable_row', 'Cable Row', ChallengeExerciseTrack.gym),
  _namedCustom('chest_fly', 'Chest Fly', ChallengeExerciseTrack.gym),
  _namedCustom('db_curl', 'Dumbbell Curl', ChallengeExerciseTrack.gym),
  _namedCustom('db_lunge', 'Dumbbell Lunge', ChallengeExerciseTrack.gym),
  _namedCustom('db_press', 'Dumbbell Press', ChallengeExerciseTrack.gym),
  _namedCustom('db_row', 'Dumbbell Row', ChallengeExerciseTrack.gym),
  _preset('deadlift', 'Deadlift', ChallengeExerciseTrack.gym, SocialChallengeKind.deadlift),
  _namedCustom('front_squat', 'Front Squat', ChallengeExerciseTrack.gym),
  _namedCustom('hang_clean', 'Hang Clean', ChallengeExerciseTrack.gym),
  _namedCustom('hip_thrust', 'Hip Thrust', ChallengeExerciseTrack.gym),
  _namedCustom('lat_pulldown', 'Lat Pulldown', ChallengeExerciseTrack.gym),
  _namedCustom('lat_raise', 'Lateral Raise', ChallengeExerciseTrack.gym),
  _namedCustom('leg_curl', 'Leg Curl', ChallengeExerciseTrack.gym),
  _namedCustom('leg_extension', 'Leg Extension', ChallengeExerciseTrack.gym),
  _namedCustom('leg_press', 'Leg Press', ChallengeExerciseTrack.gym),
  _namedCustom('ohp', 'Overhead Press', ChallengeExerciseTrack.gym),
  _namedCustom('power_clean', 'Power Clean', ChallengeExerciseTrack.gym),
  _namedCustom('power_snatch', 'Power Snatch', ChallengeExerciseTrack.gym),
  _namedCustom('push_press', 'Push Press', ChallengeExerciseTrack.gym),
  _namedCustom('rdl', 'Romanian Deadlift', ChallengeExerciseTrack.gym),
  _namedCustom('sled_push', 'Sled Push', ChallengeExerciseTrack.gym),
  _preset('squat', 'Squat', ChallengeExerciseTrack.gym, SocialChallengeKind.squat),
  _namedCustom('tricep_pushdown', 'Tricep Pushdown', ChallengeExerciseTrack.gym),
  // ── Calisthenics & fitness (bodyweight / plyo / sprint din seed) ─────────
  _namedCustom('bodyweight_good_morning', 'Bodyweight Good Morning', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('bodyweight_squat', 'Bodyweight Squat', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('box_jump', 'Box Jump', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('broad_jump', 'Broad Jump', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('burpee', 'Burpee', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('clap_pushup', 'Clap Push-up', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('depth_jump', 'Depth Jump', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('dip', 'Dip', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('inverted_row', 'Inverted Row', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('jump_squat', 'Jump Squat', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('lateral_bound', 'Lateral Bound', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('plank', 'Plank', ChallengeExerciseTrack.calisthenicsFitness),
  _preset('pull_up', 'Pull-up', ChallengeExerciseTrack.calisthenicsFitness, SocialChallengeKind.pullUps),
  _namedCustom('push_up', 'Push-up', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('reverse_lunge', 'Reverse Lunge', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('sprint_40m', 'Sprint 40m', ChallengeExerciseTrack.calisthenicsFitness),
  _namedCustom('vertical_jump', 'Vertical Jump', ChallengeExerciseTrack.calisthenicsFitness),
];

ChallengeCatalogEntry? catalogExerciseById(String id) {
  for (final e in kChallengeExerciseCatalogCore) {
    if (e.id == id) return e;
  }
  if (kChallengeCatalogManualEntry.id == id) return kChallengeCatalogManualEntry;
  return null;
}

/// Implicit la deschiderea sheet-ului: Pull-up (preset API).
ChallengeCatalogEntry get defaultChallengeCatalogEntry =>
    catalogExerciseById('pull_up') ?? kChallengeExerciseCatalogCore.first;
