// createState() returning a private State is the standard Flutter idiom; the
// lint is a known false positive here.
// ignore_for_file: library_private_types_in_public_api
import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../models/activity_kind.dart';
import '../../widgets/set_log_dialog.dart';
import '../../services/activity_calendar_store.dart';
import '../../services/app_data_cache.dart';
import '../../config/map_style.dart';
import '../../services/health_service.dart';
import '../../services/muscle_recovery_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../services/workout_service.dart';
import '../../services/workout_draft_store.dart';
import '../../services/offline_set_queue.dart';
import '../../services/offline_sync_coordinator.dart';
import '../../services/settings_store.dart';
import '../../services/cardio_flow_helper.dart';
import '../../services/route_tracker.dart';
import '../../widgets/map_metrics_overlay.dart';
import '../../widgets/weight_jump_note_sheet.dart';
import 'package:uuid/uuid.dart';
import 'xp_complete_screen.dart';
import 'workout_tracker_screen.dart';
import 'train/quick_start_hub.dart';
import 'active_program_screen.dart';
import 'programs_library_screen.dart';
import 'exercise_library_screen.dart';
import 'post_workout_screen.dart';
import 'train/custom_cardio_sheet.dart';
import '../../services/program_service.dart';
import '../ai/ai_chat_screen.dart';
import 'train/ai_workout_preview_sheet.dart';
import '../analytics/photo_capture_screen.dart';
import '../nutrition/nutrition_tab.dart';
import '../outdoor/outdoor_track_screen.dart';
import '../social/race_hub_screen.dart';

// ─── Data models ─────────────────────────────────────────────────────────────

enum _PresetType { cardio, gym }

class _GymExercise {
  const _GymExercise(this.name, this.sets, this.repsRange, this.weight,
      [this.fromHistory = false]);
  final String name;
  final int sets;
  final String repsRange;
  final String weight;
  /// True when [weight] came from the user's real training history (safe to
  /// prefill + log). False = a static preset number, which must NOT be
  /// auto-logged as a real set — the user confirms it on the first set.
  final bool fromHistory;
}

class FabPreset {
  const FabPreset({
    required this.id,
    required this.name,
    required this.type,
    required this.subtitle,
    required this.tagline,
    required this.icon,
    required this.accent,
    this.exercises = const [],
  });

  final String id;
  final String name;
  final _PresetType type;
  final String subtitle;
  final String tagline;
  final IconData icon;
  final List<Color> accent;
  final List<_GymExercise> exercises;

  bool get isCardio => type == _PresetType.cardio;
}

// ─── Preset definitions ───────────────────────────────────────────────────────

const _kAllPresets = <FabPreset>[
  FabPreset(
    id: 'run',
    name: 'Outdoor Run',
    type: _PresetType.cardio,
    subtitle: 'GPS · Map · Pace · HR',
    tagline: 'Lace up',
    icon: AppIcons.running,
    accent: [ZveltTokens.brandDeep, ZveltTokens.brand],
  ),
  FabPreset(
    id: 'bike',
    name: 'Cycling',
    type: _PresetType.cardio,
    subtitle: 'Speed · Elev · Distance',
    tagline: 'Ride out',
    icon: AppIcons.bike,
    accent: [Color(0xFF4DA3FF), Color(0xFF1E5BCC)],
  ),
  FabPreset(
    id: 'walk',
    name: 'Walk',
    type: _PresetType.cardio,
    subtitle: 'Distance · Pace · Time',
    tagline: 'Step out',
    icon: AppIcons.running,
    accent: [ZveltTokens.info, Color(0xFF1E5BCC)],
  ),
  FabPreset(
    id: 'push',
    name: 'Push Day',
    type: _PresetType.gym,
    subtitle: 'Chest · Shoulders · Triceps',
    tagline: 'Press heavy',
    icon: AppIcons.gym,
    accent: [ZveltTokens.brandDeep, ZveltTokens.brand],
    exercises: [
      _GymExercise('Bench Press', 4, '6-8', '80 kg'),
      _GymExercise('Overhead Press', 4, '8-10', '50 kg'),
      _GymExercise('Incline DB Press', 3, '10', '28 kg'),
      _GymExercise('Dips', 3, '8-12', '+15 kg'),
      _GymExercise('Lateral Raises', 3, '12-15', '12 kg'),
      _GymExercise('Tricep Pushdown', 3, '12', '25 kg'),
    ],
  ),
  FabPreset(
    id: 'pull',
    name: 'Pull Day',
    type: _PresetType.gym,
    subtitle: 'Back · Biceps · Rear Delts',
    tagline: 'Pull hard',
    icon: AppIcons.gym,
    accent: [Color(0xFF1E5BCC), Color(0xFF4DA3FF)],
    exercises: [
      _GymExercise('Deadlift', 4, '5', '140 kg'),
      _GymExercise('Pull-Ups', 4, '6-10', 'BW'),
      _GymExercise('Barbell Row', 4, '8', '70 kg'),
      _GymExercise('Face Pull', 3, '12-15', '20 kg'),
      _GymExercise('Barbell Curl', 3, '10', '35 kg'),
      _GymExercise('Hammer Curl', 3, '12', '14 kg'),
    ],
  ),
  FabPreset(
    id: 'legs',
    name: 'Leg Day',
    type: _PresetType.gym,
    subtitle: 'Quads · Hamstrings · Calves',
    tagline: 'Grind it',
    icon: AppIcons.gym,
    accent: [Color(0xFF7C3AED), Color(0xFFA855F7)],
    exercises: [
      _GymExercise('Back Squat', 5, '5', '120 kg'),
      _GymExercise('Romanian Deadlift', 4, '8', '100 kg'),
      _GymExercise('Bulgarian Split Squat', 3, '10', '20 kg'),
      _GymExercise('Leg Curl', 3, '12', '40 kg'),
      _GymExercise('Calf Raises', 4, '15', '60 kg'),
    ],
  ),
  FabPreset(
    id: 'full',
    name: 'Full Body',
    type: _PresetType.gym,
    subtitle: 'All muscle groups',
    tagline: 'Full send',
    icon: AppIcons.gym,
    accent: [ZveltTokens.brand2, ZveltTokens.brand],
    exercises: [
      _GymExercise('Back Squat', 4, '6', '110 kg'),
      _GymExercise('Bench Press', 4, '6', '75 kg'),
      _GymExercise('Barbell Row', 4, '8', '65 kg'),
      _GymExercise('Overhead Press', 3, '8', '45 kg'),
      _GymExercise('Romanian Deadlift', 3, '8', '90 kg'),
      _GymExercise('Plank', 3, '60s', 'BW'),
    ],
  ),
  FabPreset(
    id: 'upper',
    name: 'Upper Body',
    type: _PresetType.gym,
    subtitle: 'Chest · Back · Shoulders · Arms',
    tagline: 'Upper cut',
    icon: AppIcons.gym,
    accent: [Color(0xFF22C55E), Color(0xFF0F8C40)],
    exercises: [
      _GymExercise('Bench Press', 4, '6-8', '80 kg'),
      _GymExercise('Pull-Ups', 4, '6-8', '+10 kg'),
      _GymExercise('Overhead Press', 3, '8-10', '50 kg'),
      _GymExercise('Cable Row', 3, '10', '55 kg'),
      _GymExercise('Barbell Curl', 3, '12', '14 kg'),
      _GymExercise('Tricep Extension', 3, '12', '22 kg'),
    ],
  ),
  FabPreset(
    id: 'lower',
    name: 'Lower Body',
    type: _PresetType.gym,
    subtitle: 'Legs · Glutes · Core',
    tagline: 'Leg press',
    icon: AppIcons.gym,
    accent: [Color(0xFFEAB308), Color(0xFFFFB14A)],
    exercises: [
      _GymExercise('Front Squat', 4, '6', '95 kg'),
      _GymExercise('Hip Thrust', 4, '8', '110 kg'),
      _GymExercise('Walking Lunge', 3, '20', '16 kg'),
      _GymExercise('Leg Extension', 3, '12', '45 kg'),
      _GymExercise('Calf Raises', 4, '15', '50 kg'),
    ],
  ),
];

FabPreset _presetById(String id) => _kAllPresets.firstWhere((p) => p.id == id,
    orElse: () => _kAllPresets.first);

/// Maps the AI coach's suggestion onto the same preset structure the template
/// engine runs, so an AI session gets catalog matching, history-weight
/// prefill and draft/resume for free. Lives in this file because FabPreset's
/// exercise list type is library-private.
FabPreset aiSuggestionPreset(WorkoutSuggestionDto s) {
  final subtitle = (s.primaryGoal ?? '').trim();
  return FabPreset(
    id: 'ai',
    name: s.title,
    type: _PresetType.gym,
    subtitle: subtitle.isNotEmpty ? subtitle : 'Built by Zvelt Coach',
    tagline: "Coach's pick",
    icon: AppIcons.sparkles,
    accent: const [ZveltTokens.brand2, ZveltTokens.brand],
    exercises: [
      for (final e in s.exercises)
        _GymExercise(
          e.name,
          e.sets.clamp(1, 10),
          e.repRange.trim().isEmpty ? '8-10' : e.repRange.trim(),
          e.suggestedWeightKg <= 0
              ? 'BW'
              : '${e.suggestedWeightKg.toStringAsFixed(e.suggestedWeightKg % 1 == 0 ? 0 : 1)} kg',
        ),
    ],
  );
}

FabPreset? fabPresetById(String id) {
  for (final p in _kAllPresets) {
    if (p.id == id) return p;
  }
  return null;
}

double _parsePresetWeightKg(String raw) {
  final s = raw.trim().toUpperCase();
  if (s == 'BW') return 0;
  final m = RegExp(r'([\d.]+)').firstMatch(s);
  return m != null ? double.tryParse(m.group(1)!) ?? 0 : 0;
}

int _parsePresetReps(String raw) {
  final s = raw.trim();
  if (s.endsWith('s')) {
    final sec = int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? '') ?? 1;
    return sec.clamp(1, 50);
  }
  final m = RegExp(r'(\d+)').firstMatch(s);
  return int.tryParse(m?.group(1) ?? '') ?? 8;
}

int _estimateCardioKcal(String mode, int elapsedSec) {
  if (elapsedSec < 10) return 0;
  final met = mode == 'bike'
      ? 6.0
      : mode == 'walk'
          ? 3.5
          : 9.0;
  return (met * 70 * (elapsedSec / 3600)).round();
}

LocationSettings _cardioLocationSettings() => const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

String _formatSetWeightLabel(double kg, String presetWeightRaw) {
  if (presetWeightRaw.trim().toUpperCase() == 'BW' && kg == 0) return 'BW';
  if (kg == 0) return '0 kg';
  return '${kg.toStringAsFixed(kg % 1 == 0 ? 0 : 1)} kg';
}

// ─── QuickLaunchSheet ─────────────────────────────────────────────────────────

class QuickLaunchSheet extends StatefulWidget {
  const QuickLaunchSheet({super.key});

  @override
  State<QuickLaunchSheet> createState() => _QuickLaunchSheetState();
}

class _QuickLaunchSheetState extends State<QuickLaunchSheet> {
  bool _loadingHub = true;
  QsHubData _hubData = const QsHubData();
  WorkoutDraftSnapshot? _draft;
  String? _completedWorkoutId;
  WorkoutSuggestionDto? _aiSuggestion;

  @override
  void initState() {
    super.initState();
    _loadHubData();
    _loadAiSuggestion();
  }

  // Fire-and-forget: the tile shows the suggestion title once it lands; until
  // then (or on failure) it keeps honest generic copy. Never blocks the hub.
  Future<void> _loadAiSuggestion() async {
    try {
      final s = await WorkoutService().getWorkoutSuggestion();
      if (!mounted || s.exercises.isEmpty) return;
      setState(() => _aiSuggestion = s);
    } catch (_) {
      // No cache + no network / AI disabled — tile copy stays generic.
    }
  }

  Future<void> _openAiWorkout() async {
    final messenger = ScaffoldMessenger.of(context);
    var s = _aiSuggestion;
    if (s == null) {
      try {
        s = await WorkoutService().getWorkoutSuggestion();
      } catch (_) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
              "Coach's pick isn't ready yet. Check your connection and try again."),
          backgroundColor: ZveltTokens.error,
        ));
        return;
      }
      if (!mounted) return;
      if (s.exercises.isEmpty) {
        messenger.showSnackBar(const SnackBar(
          content: Text(
              "Coach's pick isn't ready yet. Log a workout or set a goal first."),
          backgroundColor: ZveltTokens.error,
        ));
        return;
      }
      setState(() => _aiSuggestion = s);
    }
    final start = await showAiWorkoutPreviewSheet(
      context,
      suggestion: s,
      regenerate: () => WorkoutService().getWorkoutSuggestion(refresh: true),
      onSuggestionChanged: (next) => setState(() => _aiSuggestion = next),
    );
    if (start == null || !mounted) return;
    await _startPreset(aiSuggestionPreset(start));
  }

  // Loads the real context for the primary card: an unfinished draft (resume),
  // the active program + today's session (next), or today's completed workout.
  Future<void> _loadHubData() async {
    WorkoutDraftSnapshot? draft;
    WorkoutDto? draftWorkout;
    ActiveProgramView? active;
    WorkoutsResponse? workouts;
    try { draft = await WorkoutDraftStore().load(); } catch (_) {}
    if (draft != null) {
      try { draftWorkout = await WorkoutService().getWorkout(draft.workoutId); } catch (_) {}
    }
    try { active = await ProgramService().getActive(); } catch (_) {}
    try { workouts = await WorkoutService().getWorkouts(); } catch (_) {}
    // Opportunistically warm the local exercise catalog while we're online, so
    // an offline "start workout" / preset can still resolve & pick exercises.
    // Best-effort and fire-and-forget — never blocks the hub render.
    unawaited(WorkoutService().prefetchCatalog());
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _hubData = _buildHubData(draft, draftWorkout, active, workouts?.data ?? const []);
      _loadingHub = false;
    });
  }

  QsHubData _buildHubData(WorkoutDraftSnapshot? draft, WorkoutDto? draftWorkout,
      ActiveProgramView? active, List<WorkoutDto> workouts) {
    final today = DateUtils.dateOnly(DateTime.now());
    WorkoutDto? doneToday;
    for (final w in workouts) {
      if (w.status != 'completed') continue;
      // Server timestamps are UTC; compare on the LOCAL calendar day so an
      // early-morning (UTC+2/+3) session isn't pushed to the previous day.
      final d = DateUtils.dateOnly((w.endedAt ?? w.startedAt).toLocal());
      if (d == today) {
        doneToday = w;
        break;
      }
    }
    if (draft != null) {
      // Real progress: exercises with at least one logged set / total exercises.
      final total = draftWorkout?.exercises.length ?? draft.exerciseCount;
      final started = draftWorkout == null
          ? 0
          : draftWorkout.exercises
              .where((we) => we.sets.any((s) => s.isCompleted))
              .length;
      final progress = total > 0 ? (started / total).clamp(0.0, 1.0) : 0.0;
      final parts = <String>[
        if (total > 0) '$started/$total exercises',
        '${draft.setsLogged} sets logged',
      ];
      return QsHubData(
        primary: QsPrimaryKind.resume,
        resumeTitle: draft.title,
        resumeMeta: parts.join(' · '),
        resumeProgress: progress,
      );
    }
    final prog = active?.program;
    if (prog != null && doneToday == null && active?.completed != true) {
      final dayTitle = active?.today?.title;
      final exCount = active?.today?.exercises.length ?? 0;
      final meta = <String>[
        if (exCount > 0) '$exCount exercises',
        'Week ${prog.currentWeek} of ${prog.totalWeeks}',
      ];
      return QsHubData(
        primary: QsPrimaryKind.next,
        nextTitle: (dayTitle != null && dayTitle.isNotEmpty) ? dayTitle : prog.title,
        nextMuscles: prog.title,
        nextMeta: meta.join(' · '),
      );
    }
    if (doneToday != null) {
      _completedWorkoutId = doneToday.id;
      var vol = 0.0;
      var sets = 0;
      for (final we in doneToday.exercises) {
        for (final s in we.sets) {
          if (s.tag == 'WARMUP') continue;
          vol += s.weightKg * s.reps;
          sets++;
        }
      }
      final dur = doneToday.endedAt != null
          ? _fmtDur(doneToday.endedAt!.difference(doneToday.startedAt))
          : '—';
      return QsHubData(
        primary: QsPrimaryKind.completed,
        completedTitle: _sessionLabel(doneToday),
        completedSummary: '$sets sets · ${_fmtInt(vol)} kg · $dur',
      );
    }
    return const QsHubData(primary: QsPrimaryKind.choose);
  }

  String _fmtInt(num n) {
    final s = n.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  String _fmtDur(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  // Kept in sync with workouts_tab.dart's _muscleGroup so a session gets the
  // same "{group} Day" label on the Quick Start card and the History/Today tabs.
  String _muscleGroup(String? raw) {
    final v = (raw ?? '').toLowerCase();
    if (v.contains('chest') || v.contains('pec')) return 'Chest';
    if (v.contains('back') || v.contains('lat') || v.contains('trap') || v.contains('rhom')) return 'Back';
    if (v.contains('quad') || v.contains('glute') || v.contains('ham') || v.contains('calf') || v.contains('leg')) return 'Legs';
    if (v.contains('delt') || v.contains('shoulder')) return 'Shoulders';
    if (v.contains('bicep') || v.contains('tricep') || v.contains('forearm') || v.contains('arm')) return 'Arms';
    if (v.contains('ab') || v.contains('core') || v.contains('oblique')) return 'Core';
    return 'Other';
  }

  String _sessionLabel(WorkoutDto w) {
    final vol = <String, double>{};
    for (final we in w.exercises) {
      final g = _muscleGroup(we.exercise.primaryMuscle);
      if (g == 'Other') continue;
      var sv = 0.0;
      for (final s in we.sets) {
        if (s.tag == 'WARMUP') continue;
        sv += s.weightKg * s.reps + s.reps;
      }
      vol[g] = (vol[g] ?? 0) + sv;
    }
    if (vol.isEmpty) return 'Workout';
    return '${vol.entries.reduce((a, b) => a.value >= b.value ? a : b).key} Day';
  }

  Future<void> _openShortcut(String key) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (key == SettingsKeys.scEmpty) {
      // Mint the workout id locally so the online create and any offline replay
      // upsert on the SAME id (local id == server id — no remapping anywhere).
      final workoutId = const Uuid().v4();
      const label = 'Empty workout';
      try {
        await WorkoutService().createWorkout(label: label, clientId: workoutId);
      } catch (_) {
        // Offline-first: enqueue the workout-create and start logging against
        // the local id immediately. The coordinator replays the create on
        // reconnect (before its exercises/sets); the tracker synthesizes a
        // local draft from the queue while the server has no record yet.
        await OfflineSyncCoordinator.instance
            .enqueueBootstrapWorkout(workoutId: workoutId, label: label);
        // Persist the resume pointer so a kill/relaunch (and the tracker's
        // offline draft rebuild) recovers the same session with its start time.
        await WorkoutService.saveActiveWorkoutPointer(
          WorkoutDto(
            id: workoutId,
            status: 'draft',
            startedAt: DateTime.now(),
          ),
          label: label,
        );
        if (mounted) {
          messenger.showSnackBar(const SnackBar(
            content: Text('Started offline — will sync when back online.'),
            backgroundColor: ZveltTokens.warn,
          ));
        }
      }
      if (!mounted) return;
      nav.pop();
      await nav.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => WorkoutTrackerScreen(workoutId: workoutId),
        ),
      );
      return;
    }
    nav.pop();
    switch (key) {
      case SettingsKeys.scAi:
        await nav.push<void>(
            MaterialPageRoute<void>(builder: (_) => const AiChatScreen()));
        break;
      case SettingsKeys.scRun:
        await nav.push<void>(MaterialPageRoute<void>(
            builder: (_) => const OutdoorTrackScreen()));
        break;
      case SettingsKeys.scMeal:
        await nav.push<void>(
            MaterialPageRoute<void>(builder: (_) => const NutritionTab()));
        break;
      case SettingsKeys.scRace:
        await nav.push<void>(
            MaterialPageRoute<void>(builder: (_) => const RaceHubScreen()));
        break;
      case SettingsKeys.scPhoto:
        await nav.push<void>(MaterialPageRoute<void>(
            builder: (_) => const PhotoCaptureScreen()));
        break;
    }
  }

  Future<void> _startPreset(FabPreset preset) async {
    final nav = Navigator.of(context);
    nav.pop();
    if (!mounted) return;
    await nav.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ActiveWorkoutView(preset: preset),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingHub) {
      return Scaffold(
        backgroundColor: ZveltTokens.bg,
        body: const Center(child: CircularProgressIndicator(color: ZveltTokens.brand)),
      );
    }
    return QuickStartHub(
      data: _hubData,
      templates: _quickStartTemplates(),
      aiTitle: _aiSuggestion?.title,
      onAiWorkout: _openAiWorkout,
      onClose: () => Navigator.of(context).maybePop(),
      onResume: _resumeDraft,
      onStartNext: _openActiveProgram,
      onPreviewNext: _openActiveProgram,
      onEditNext: _openActiveProgram,
      onSkipNext: _openActiveProgram,
      onShareCompleted: _shareCompleted,
      onLogAnother: () => _openShortcut(SettingsKeys.scEmpty),
      onChooseProgram: _openPrograms,
      onStartEmpty: () => _openShortcut(SettingsKeys.scEmpty),
      onGenerateSmart: _startSmart,
      onCardio: _startCardio,
      onTemplate: _startTemplate,
      onBrowseLibrary: _openExerciseLibrary,
    );
  }

  Future<void> _resumeDraft() async {
    final draft = _draft;
    if (draft == null) return;
    final nav = Navigator.of(context);
    nav.pop();
    await nav.push<void>(MaterialPageRoute<void>(
      builder: (_) => ActiveWorkoutView.forExistingWorkout(workoutId: draft.workoutId),
    ));
  }

  // Single source of truth: the Quick Start preview cards are built from the
  // same _kAllPresets the workout engine actually starts, so what you preview
  // is exactly what you train.
  List<QsTemplate> _quickStartTemplates() {
    const ids = {'push': 'push', 'pull': 'pull', 'legs': 'legs', 'full': 'fullbody'};
    final out = <QsTemplate>[];
    ids.forEach((presetId, hubId) {
      final p = _presetById(presetId);
      out.add(QsTemplate(
        hubId,
        p.name,
        p.subtitle,
        p.exercises.length,
        [for (final e in p.exercises) (e.name, '${e.sets}×${e.repsRange} · ${e.weight}')],
      ));
    });
    return out;
  }

  void _startTemplate(String id) {
    // Hub uses 'fullbody'; the matching preset id is 'full'.
    _startPreset(_presetById(id == 'fullbody' ? 'full' : id));
  }

  void _startCardio(String kind) {
    if (kind == 'custom') {
      _openCustomCardio();
      return;
    }
    // run / walk / bike each have a tracked GPS engine (walk logs as walk).
    final id = kind == 'bike'
        ? 'bike'
        : kind == 'walk'
            ? 'walk'
            : 'run';
    _startPreset(_presetById(id));
  }

  // Custom cardio = no GPS: a manual log (activity + duration) → calendar store.
  Future<void> _openCustomCardio() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showCustomCardioSheet(context);
    if (result == null || !mounted) return;
    try {
      await ActivityCalendarStore().addManualSession(
        AppDataCache.localDayYmd(),
        ManualCardioSession(kind: result.kind, durationMin: result.durationMin),
      );
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Logged ${result.durationMin} min ${result.kind.label}.'),
        backgroundColor: ZveltTokens.success,
      ),
    );
  }

  // Share the just-completed workout via the real feed composer (pre-fills the
  // workout summary server-side from the workoutId).
  void _shareCompleted() {
    final id = _completedWorkoutId;
    final nav = Navigator.of(context);
    nav.pop();
    nav.push<void>(MaterialPageRoute<void>(
      builder: (_) => PostWorkoutScreen(workoutId: id),
    ));
  }

  // Smart workout: the goal/duration/equipment pills genuinely drive a session,
  // which then runs through the same engine as the templates (catalog match +
  // history-weight prefill + countdown). Equipment filters the pool, goal sets
  // the rep range / set count, duration sets how many exercises.
  void _startSmart(String goal, int duration, String equip) {
    const pools = <String, List<String>>{
      'gym': [
        'Back Squat', 'Bench Press', 'Deadlift', 'Overhead Press', 'Barbell Row',
        'Lat Pulldown', 'Leg Press', 'Romanian Deadlift', 'Lateral Raise',
        'Tricep Pushdown', 'Barbell Curl', 'Leg Curl',
      ],
      'dumbbells': [
        'Dumbbell Bench Press', 'Goblet Squat', 'Dumbbell Row',
        'Dumbbell Shoulder Press', 'Dumbbell Romanian Deadlift', 'Dumbbell Lunge',
        'Dumbbell Lateral Raise', 'Hammer Curl', 'Overhead Tricep Extension',
        'Dumbbell Curl',
      ],
      'bodyweight': [
        'Pull-up', 'Push-up', 'Bodyweight Squat', 'Walking Lunge', 'Dip',
        'Pike Push-up', 'Glute Bridge', 'Plank', 'Mountain Climber', 'Burpee',
      ],
    };
    final pool = pools[equip] ?? pools['gym']!;
    final rawCount = duration <= 30 ? 4 : (duration <= 45 ? 6 : 8);
    final n = rawCount.clamp(1, pool.length);
    final (sets, reps) = switch (goal) {
      'strength' => (5, '5'),
      'muscle' => (4, '8-12'),
      'fat' => (3, '12-15'),
      _ => (3, '8-10'),
    };
    final isBw = equip == 'bodyweight';
    final exercises = <_GymExercise>[
      for (var i = 0; i < n; i++)
        _GymExercise(pool[i], sets, reps, isBw ? 'BW' : '20 kg'),
    ];
    final preset = FabPreset(
      id: 'smart',
      name: 'Smart Workout (${duration}min)',
      type: _PresetType.gym,
      subtitle: _smartSubtitle(goal),
      tagline: 'Generated for you',
      icon: AppIcons.sparkles,
      accent: const [ZveltTokens.brand2, ZveltTokens.brand],
      exercises: exercises,
    );
    _startPreset(preset);
  }

  String _smartSubtitle(String goal) => switch (goal) {
        'strength' => 'Strength · heavy & low reps',
        'muscle' => 'Muscle gain · hypertrophy',
        'fat' => 'Fat loss · high volume',
        _ => 'General fitness',
      };

  void _openActiveProgram() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push<void>(MaterialPageRoute<void>(builder: (_) => const ActiveProgramScreen()));
  }

  void _openPrograms() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push<void>(MaterialPageRoute<void>(builder: (_) => const ProgramsLibraryScreen()));
  }

  void _openExerciseLibrary() {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push<void>(MaterialPageRoute<void>(builder: (_) => const ExerciseLibraryScreen()));
  }
}

// ─── ActiveWorkoutView ────────────────────────────────────────────────────────

enum _WorkoutPhase { countdown, live }

class ActiveWorkoutView extends StatefulWidget {
  const ActiveWorkoutView(
      {super.key, required this.preset, this.existingWorkoutId});

  const ActiveWorkoutView.forExistingWorkout(
      {super.key, required String workoutId})
      : preset = const FabPreset(
          id: 'custom',
          name: 'Workout',
          type: _PresetType.gym,
          subtitle: 'Your session',
          tagline: 'Let\'s go',
          icon: AppIcons.gym,
          accent: [ZveltTokens.info, Color(0xFF4DA3FF)],
        ),
        existingWorkoutId = workoutId;

  final FabPreset preset;
  final String? existingWorkoutId;

  @override
  State<ActiveWorkoutView> createState() => _ActiveWorkoutViewState();
}

class _ActiveWorkoutViewState extends State<ActiveWorkoutView>
    with TickerProviderStateMixin {
  final WorkoutService _workoutService = WorkoutService();
  final MapController _map = MapController();

  _WorkoutPhase _phase = _WorkoutPhase.countdown;

  // Countdown
  int _countdownValue = 3;
  Timer? _countdownTimer;
  late final AnimationController _countdownScale;

  // Live workout
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;
  bool _paused = false;

  // Gym backend
  String? _workoutId;
  List<WorkoutExerciseDto> _workoutExercises = [];
  bool _bootstrapping = false;
  String? _bootstrapError;
  bool _loggingSet = false;

  // Gym UI
  int _currentExIdx = 0;
  int _currentSet = 0; // 0-based
  double _currentWeightKg = 0;

  /// Exercise indices whose (preset-sourced) weight the user has explicitly
  /// confirmed at least once — so we prompt for confirmation only on the FIRST
  /// set, never auto-logging a fabricated preset number.
  final Set<int> _weightConfirmedExIdx = <int>{};
  int _currentReps = 8;
  double? _currentRpe;
  bool _resting = false;
  final int _restSeconds = 90;
  int _restRemaining = 90;
  Timer? _restTimer;

  // Cardio GPS — RouteTracker filters jitter/teleports so distance is honest.
  StreamSubscription<Position>? _gpsSub;
  RouteTracker _routeTracker = RouteTracker();
  LatLng? _livePosition;
  LatLng _mapCenter = const LatLng(44.4268, 26.1025);
  bool _cardioLocBusy = true;
  String? _cardioError;
  bool _cardioTracking = false;

  List<_GymExercise> _displayExercises = [];


  String get _cardioMode => widget.preset.id == 'bike'
      ? 'bike'
      : widget.preset.id == 'walk'
          ? 'walk'
          : 'run';

  @override
  void initState() {
    super.initState();
    _countdownScale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    if (widget.preset.isCardio) {
      _initCardioLocation();
    } else {
      _displayExercises = List<_GymExercise>.from(widget.preset.exercises);
      _bootstrapGymWorkout();
    }
    _startCountdown();
  }

  void _syncSetValuesFromPreset() {
    final exercises = _displayExercises;
    if (_currentExIdx >= exercises.length) return;
    final presetEx = exercises[_currentExIdx];
    _currentWeightKg = _parsePresetWeightKg(presetEx.weight);
    _currentReps = _parsePresetReps(presetEx.repsRange);
    _currentRpe = null;
  }

  /// Opens the set editor. Returns true when the user confirmed (values
  /// applied), false on cancel or when the workout isn't ready.
  Future<bool> _editSetValues() async {
    final exercises = _displayExercises;
    if (_currentExIdx >= exercises.length) return false;
    final presetEx = exercises[_currentExIdx];
    if (_currentExIdx >= _workoutExercises.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout is still loading. Try again in a moment.'),
          backgroundColor: ZveltTokens.warn,
        ),
      );
      return false;
    }
    final exercise = _workoutExercises[_currentExIdx].exercise;
    final result = await showDialog<(double, int, double?, String)?>(
      context: context,
      builder: (ctx) => SetLogDialog(
        exercise: exercise,
        initialWeight: _currentWeightKg,
        initialReps: _currentReps,
        maxReps: 50,
        title: presetEx.name,
      ),
    );
    if (result == null || !mounted) return false;
    setState(() {
      _currentWeightKg = result.$1;
      _currentReps = result.$2;
      _currentRpe = result.$3;
    });
    return true;
  }

  Future<void> _bootstrapGymWorkout() async {
    if (widget.preset.isCardio) return;
    setState(() {
      _bootstrapping = true;
      _bootstrapError = null;
    });
    try {
      if (widget.existingWorkoutId != null) {
        final workout =
            await _workoutService.getWorkout(widget.existingWorkoutId!);
        final added = workout.exercises;
        final display = <_GymExercise>[
          for (final we in added)
            _GymExercise(
              we.exercise.name,
              we.sets.isEmpty ? 3 : we.sets.length.clamp(1, 10),
              '8-10',
              '20 kg',
            ),
        ];
        if (!mounted) return;
        setState(() {
          _workoutId = workout.id;
          _workoutExercises = added;
          _displayExercises = display;
          _bootstrapping = false;
        });
        _syncSetValuesFromPreset();
        await _saveDraftSnapshot();
        return;
      }

      if (_displayExercises.isEmpty) {
        setState(() => _bootstrapping = false);
        return;
      }

      // Mint the workout id locally so an online create and an offline replay
      // upsert on the SAME id (local id == server id). serverWorkout stays null
      // when the create failed offline — we then queue the create instead.
      final workoutId = const Uuid().v4();
      WorkoutDto? serverWorkout;
      try {
        serverWorkout = await _workoutService.createWorkout(clientId: workoutId);
      } catch (_) {
        serverWorkout = null;
      }
      // Once online (server workout exists) and no add has failed yet.
      var online = serverWorkout != null;

      final added = <WorkoutExerciseDto>[];
      final display = <_GymExercise>[];
      // Track preset exercises that couldn't be resolved so the user sees
      // a partial-match warning instead of silently getting fewer exercises.
      final skipped = <String>[];
      // Run all catalog name lookups in parallel. getExercises transparently
      // falls back to the LOCAL catalog cache when offline, so a warm cache
      // still resolves preset names without a connection.
      final matches = await Future.wait([
        for (final ex in _displayExercises)
          () async {
            try {
              final res =
                  await _workoutService.getExercises(query: ex.name, limit: 20);
              // Prefer an exact case-insensitive name match; fall back to the
              // top result (server already sorted by relevance).
              for (final candidate in res.data) {
                if (candidate.name.toLowerCase() == ex.name.toLowerCase()) {
                  return candidate;
                }
              }
              return res.data.isNotEmpty ? res.data.first : null;
            } catch (_) {
              // Cold cache offline (or a blip) — degrade this one exercise to a
              // skip without killing the rest of the preset.
              return null;
            }
          }(),
      ]);
      // History-aware prefill: replace the generic preset weights with the
      // user's most recent working weight per lift (best-effort; offline this
      // returns {} and we fall back to the preset label).
      final matchedIds = [for (final m in matches) if (m != null) m.id];
      final lastWeights =
          await _workoutService.getLastWorkingWeights(matchedIds);
      // Adds stay SEQUENTIAL in preset order so position is deterministic.
      for (var i = 0; i < _displayExercises.length; i++) {
        final ex = _displayExercises[i];
        final match = matches[i];
        if (match == null) {
          skipped.add(ex.name);
          continue;
        }
        // Mint the workout_exercise PK locally — the same id every set targets.
        final weId = const Uuid().v4();
        WorkoutExerciseDto we;
        if (online) {
          try {
            we = await _workoutService.addExercise(
              serverWorkout!.id,
              match.id,
              position: i,
              clientId: weId,
            );
          } catch (_) {
            // Fell offline mid-bootstrap — enqueue this and every remaining add.
            online = false;
            await OfflineSyncCoordinator.instance.enqueueBootstrapExercise(
              workoutId: workoutId,
              exerciseId: match.id,
              weId: weId,
              position: i,
            );
            we = WorkoutExerciseDto(
              id: weId,
              exerciseId: match.id,
              position: i,
              exercise: match,
              sets: const [],
            );
          }
        } else {
          await OfflineSyncCoordinator.instance.enqueueBootstrapExercise(
            workoutId: workoutId,
            exerciseId: match.id,
            weId: weId,
            position: i,
          );
          we = WorkoutExerciseDto(
            id: weId,
            exerciseId: match.id,
            position: i,
            exercise: match,
            sets: const [],
          );
        }
        added.add(we);
        final histKg = lastWeights[match.id];
        final weightLabel = histKg != null
            ? '${histKg.toStringAsFixed(histKg % 1 == 0 ? 0 : 1)} kg'
            : ex.weight;
        // fromHistory = the weight is the user's real last working load (safe to
        // log); otherwise it's a static preset number needing confirmation.
        display.add(_GymExercise(
            match.name, ex.sets, ex.repsRange, weightLabel, histKg != null));
      }

      // If the workout itself never reached the server (offline create), we can
      // only proceed local-first when the catalog resolved at least one
      // exercise. A COLD cache resolves nothing → keep the honest "couldn't
      // start — Try again" state (don't fabricate a workout with no exercises).
      final createdOnServer = serverWorkout != null;
      if (!createdOnServer) {
        if (added.isEmpty) {
          if (!mounted) return;
          setState(() {
            _bootstrapError =
                "You're offline and this workout isn't cached yet. Reconnect and try again.";
            _bootstrapping = false;
          });
          return; // _workoutId stays null → retry state (nothing fabricated)
        }
        // Warm cache: queue the workout-create (flush replays it before the
        // exercise-creates) and persist a resume pointer.
        await OfflineSyncCoordinator.instance
            .enqueueBootstrapWorkout(workoutId: workoutId, label: null);
        await WorkoutService.saveActiveWorkoutPointer(
          WorkoutDto(id: workoutId, status: 'draft', startedAt: DateTime.now()),
          label: 'Workout',
        );
      }

      if (!mounted) return;
      setState(() {
        // serverWorkout.id == workoutId when created online (clientId upsert),
        // so this local id is correct in both paths.
        _workoutId = workoutId;
        _workoutExercises = added;
        _displayExercises = display;
        _bootstrapping = false;
        if (added.isEmpty) {
          _bootstrapError =
              'Could not match any preset exercises in the catalog.';
        } else if (skipped.isNotEmpty) {
          // Partial — show inline so user knows their preset lost exercises.
          _bootstrapError =
              'Could not match: ${skipped.join(', ')}. Continuing with the rest.';
        }
      });
      if (added.isNotEmpty) _syncSetValuesFromPreset();
      await _saveDraftSnapshot();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootstrapError = e.toString().replaceFirst('Exception: ', '');
        _bootstrapping = false;
      });
    }
  }

  Future<void> _initCardioLocation() async {
    setState(() {
      _cardioLocBusy = true;
      _cardioError = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _cardioError = 'Enable location to track your route.';
          _cardioLocBusy = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: _cardioLocationSettings(),
      );
      final ll = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _mapCenter = ll;
        _livePosition = ll;
        _cardioLocBusy = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _map.move(ll, 16);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cardioError = 'Could not get GPS fix.';
        _cardioLocBusy = false;
      });
    }
  }

  Future<void> _startCardioTracking() async {
    if (_cardioTracking) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      setState(() => _cardioError = 'Enable location to track your route.');
      return;
    }
    setState(() {
      _cardioError = null;
      _cardioTracking = true;
      _routeTracker = RouteTracker(isBike: _cardioMode == 'bike');
      _livePosition = null;
    });
    await WakelockPlus.enable();
    // Bailed out during the wakelock await → don't open an orphan GPS stream.
    if (!mounted) return;
    _gpsSub = Geolocator.getPositionStream(
            locationSettings: _cardioLocationSettings())
        .listen(_handleCardioPosition);
  }

  void _handleCardioPosition(Position pos) {
    if (!mounted || _paused) return;
    // RouteTracker drops low-accuracy fixes and jitter; rejected fixes
    // shouldn't move the marker or camera either, so the route stays honest.
    if (!_routeTracker.add(pos)) return;
    final ll = _routeTracker.lastPoint!;
    setState(() {
      _livePosition = ll;
      _mapCenter = ll;
    });
    _map.move(ll, _map.camera.zoom);
  }

  void _recenterCardioMap() {
    final target = _livePosition ?? _routeTracker.lastPoint ?? _mapCenter;
    _map.move(target, 16);
  }

  Future<void> _stopCardioTracking({required bool save}) async {
    await _gpsSub?.cancel();
    _gpsSub = null;
    await WakelockPlus.disable();
    if (save && (_elapsedSeconds >= 30 || _routeTracker.meters >= 50)) {
      final store = ActivityCalendarStore();
      final day = AppDataCache.localDayYmd();
      final kind = _cardioMode == 'bike'
          ? ActivityKind.cycle
          : _cardioMode == 'walk'
              ? ActivityKind.walk
              : ActivityKind.run;
      await store.addManualSession(
        day,
        ManualCardioSession(
          kind: kind,
          distanceKm:
              _routeTracker.meters > 0 ? _routeTracker.meters / 1000 : null,
          durationMin: (_elapsedSeconds / 60).ceil().clamp(1, 999),
        ),
      );
    }
    if (mounted) setState(() => _cardioTracking = false);
  }

  void _startCountdown() {
    _countdownScale.forward(from: 0);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_countdownValue > 1) {
          _countdownValue--;
          _countdownScale.forward(from: 0);
        } else {
          t.cancel();
          _phase = _WorkoutPhase.live;
          _startElapsed();
        }
      });
    });
  }

  void _startElapsed() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _paused) return;
      setState(() => _elapsedSeconds++);
    });
    if (widget.preset.isCardio) {
      _startCardioTracking();
    }
  }

  Future<void> _saveDraftSnapshot() async {
    final id = _workoutId;
    if (id == null || widget.preset.isCardio) return;
    var setsLogged = 0;
    for (final we in _workoutExercises) {
      setsLogged += we.sets.where((s) => s.isCompleted).length;
    }
    await WorkoutDraftStore().save(
      WorkoutDraftSnapshot(
        workoutId: id,
        title: widget.preset.name,
        savedAt: DateTime.now(),
        exerciseCount: _displayExercises.length,
        setsLogged: setsLogged,
      ),
    );
  }

  Future<void> _confirmExitGym() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ZveltTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ZveltTokens.rLg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AppIcons.pause),
              title: const Text('Save & exit'),
              subtitle: const Text('Resume later from Home'),
              onTap: () => Navigator.pop(ctx, 'minimize'),
            ),
            ListTile(
              leading: const Icon(AppIcons.flag,
                  color: ZveltTokens.success),
              title: const Text('Complete workout'),
              subtitle: const Text('Complete session and earn XP'),
              onTap: () => Navigator.pop(ctx, 'end'),
            ),
            ListTile(
              leading:
                  const Icon(AppIcons.trash, color: ZveltTokens.error),
              title: const Text('Discard session',
                  style: TextStyle(color: ZveltTokens.error)),
              onTap: () => Navigator.pop(ctx, 'discard'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'minimize') {
      await _saveDraftSnapshot();
      if (mounted) Navigator.of(context).pop();
    } else if (choice == 'discard') {
      await WorkoutDraftStore().clear();
      if (mounted) Navigator.of(context).pop();
    } else if (choice == 'end') {
      await _finishWorkout();
    }
  }

  bool _finishing = false;

  Future<void> _finishWorkout() async {
    if (_finishing) return; // guard: double-tap must not complete twice
    _finishing = true;
    if (widget.preset.isCardio) {
      await _stopCardioTracking(save: false);
      if (!mounted) return;
      await CardioFlowHelper.showRecapAndXp(
        context: context,
        mode: _cardioMode,
        meters: _routeTracker.meters,
        elapsedSeconds: _elapsedSeconds,
        source: 'quick_launch',
        afterDone: () {
          if (mounted) Navigator.of(context).pop();
        },
      );
      return;
    }
    if (_workoutId != null) {
      try {
        final result = await _workoutService.completeWorkout(_workoutId!);
        await WorkoutDraftStore().clear();
        await MuscleRecoveryService().invalidateCache();
        HealthService.instance.writeWorkoutToHealth(result.workout).ignore();
        if (!mounted) return;
        await Navigator.of(context).pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (ctx) => XpCompleteScreen(
              workoutId: _workoutId!,
              xpGain: result.xpGain,
              ageMultiplier: result.ageMultiplier,
              gameXp: result.gameXp,
              xpBreakdown: result.xpBreakdown,
              onDone: () => Navigator.of(ctx).pop(),
            ),
          ),
        );
        return;
      } catch (e) {
        _finishing = false; // allow a retry after a failed completion
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceFirst('Exception: ', '')),
              backgroundColor: ZveltTokens.error,
            ),
          );
        }
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _doneSet() async {
    final exercises = _displayExercises;
    if (exercises.isEmpty) return;
    final presetEx = exercises[_currentExIdx];

    // A static preset weight (not the user's real history) must be confirmed on
    // the FIRST set before it's logged — otherwise tapping "Done" records a
    // fabricated number (e.g. a beginner's 140 kg deadlift) into e1RM/PRs/rank.
    // On confirm we fall through and log the confirmed values; on cancel we
    // stay put and log nothing.
    if (!presetEx.fromHistory &&
        !_weightConfirmedExIdx.contains(_currentExIdx) &&
        !_loggingSet &&
        _workoutId != null &&
        _currentExIdx < _workoutExercises.length) {
      final confirmed = await _editSetValues();
      if (!mounted || !confirmed) return;
      setState(() => _weightConfirmedExIdx.add(_currentExIdx));
    }

    if (_workoutId != null &&
        _currentExIdx < _workoutExercises.length &&
        !_loggingSet) {
      setState(() => _loggingSet = true);
      // Same client-side UUID used for the POST and any later retry from the
      // offline queue, so the server dedupes on `clientSetId` instead of
      // creating duplicate sets when the network blip resolves.
      final clientSetId = const Uuid().v4();
      final we = _workoutExercises[_currentExIdx];
      // Anti-cheat retry loop: a >2× weight jump vs the recent personal max is
      // rejected until a justification note is attached. On cancel we stay on
      // this set (don't advance) so the user can adjust or note it.
      String? note;
      var cancelled = false;
      var done = false;
      while (!done && !cancelled) {
        try {
          await _workoutService.addSet(
            _workoutId!,
            we.id,
            weightKg: _currentWeightKg,
            reps: _currentReps,
            rpe: _currentRpe,
            clientSetId: clientSetId,
            note: note,
          );
          await _saveDraftSnapshot();
          done = true;
        } on WeightJumpNoteRequiredException catch (ex) {
          if (!mounted) return;
          final entered = await showWeightJumpNoteSheet(context, message: ex.message);
          if (entered == null) {
            cancelled = true;
          } else {
            note = entered;
          }
        } catch (_) {
          // Honor offline-first: enqueue the set (with any note) and tell the
          // user it'll sync. Coordinator flushes automatically on reconnect.
          await OfflineSyncCoordinator.instance.enqueue(
            PendingSetEntry(
              workoutId: _workoutId!,
              weId: we.id,
              weightKg: _currentWeightKg,
              reps: _currentReps,
              rpe: _currentRpe,
              clientSetId: clientSetId,
              note: note,
            ),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Saved offline — will sync when back online.'),
                backgroundColor: ZveltTokens.warn,
              ),
            );
          }
          await _saveDraftSnapshot();
          done = true;
        }
      }
      if (mounted) setState(() => _loggingSet = false);
      if (cancelled) return; // user declined the note → stay on this set
    }

    if (!mounted) return;
    final ex = presetEx;
    setState(() {
      if (_currentSet + 1 < ex.sets) {
        _currentSet++;
        _startRest();
      } else {
        _resting = false;
        if (_currentExIdx + 1 < exercises.length) {
          _currentExIdx++;
          _currentSet = 0;
          _syncSetValuesFromPreset();
          _startRest();
        } else {
          _finishWorkout();
        }
      }
    });
  }

  void _startRest() {
    _restRemaining = _restSeconds;
    _resting = true;
    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_restRemaining > 0) {
          _restRemaining--;
        } else {
          t.cancel();
          _resting = false;
        }
      });
    });
  }

  void _skipRest() {
    _restTimer?.cancel();
    setState(() => _resting = false);
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _elapsedTimer?.cancel();
    _restTimer?.cancel();
    _gpsSub?.cancel();
    WakelockPlus.disable();
    _countdownScale.dispose();
    _map.dispose();
    super.dispose();
  }

  String _formatElapsed() {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _phase == _WorkoutPhase.countdown
            ? _buildCountdown()
            : widget.preset.isCardio
                ? _buildCardioLive()
                : _buildGymLive(),
      ),
    );
  }

  // ── Countdown ──────────────────────────────────────────────────────────────

  Widget _buildCountdown() {
    return Container(
      key: const ValueKey('countdown'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            widget.preset.accent.first.withValues(alpha: 0.25),
            ZveltTokens.bg,
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.preset.name,
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                color: ZveltTokens.text2,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Starting in',
              style: TextStyle(color: ZveltTokens.text2, fontSize: 13),
            ),
            const SizedBox(height: 40),
            ScaleTransition(
              scale: CurvedAnimation(
                  parent: _countdownScale, curve: Curves.elasticOut),
              child: Text(
                _countdownValue > 0 ? '$_countdownValue' : 'GO!',
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontStyle: FontStyle.italic,
                  fontSize: 200,
                  fontWeight: FontWeight.w900,
                  height: 0.9,
                  color: ZveltTokens.text,
                  shadows: [
                    Shadow(
                      color: widget.preset.accent.first.withValues(alpha: 0.7),
                      blurRadius: 60,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 80),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: ZveltTokens.text2, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Cardio live ────────────────────────────────────────────────────────────

  Widget _buildCardioLive() {
    final topPad = MediaQuery.paddingOf(context).top;
    final kcal = _estimateCardioKcal(_cardioMode, _elapsedSeconds);
    final avgKmh = _elapsedSeconds >= 5 && _routeTracker.meters >= 5
        ? (_routeTracker.meters / _elapsedSeconds) * 3.6
        : 0.0;

    // Full-bleed map with the metric cards overlaid on the left edge —
    // Razvan's run-detail design applied to the live screen.
    return Stack(
      key: const ValueKey('cardio'),
      fit: StackFit.expand,
      children: [
        if (_cardioLocBusy)
          const Center(
              child: CircularProgressIndicator(color: ZveltTokens.brand))
        else
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: 16,
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              TileLayer(
                urlTemplate: kMapTileUrl,
                userAgentPackageName: 'com.lunaoscar.zvelt',
              ),
              if (_routeTracker.points.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routeTracker.points,
                      strokeWidth: 5,
                      color: widget.preset.accent.first,
                    ),
                  ],
                ),
              if (_livePosition != null || _routeTracker.points.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _livePosition ?? _routeTracker.points.last,
                      width: 36,
                      height: 36,
                      child: Icon(
                        _cardioMode == 'bike'
                            ? AppIcons.bike
                            : AppIcons.running,
                        color: widget.preset.accent.first,
                        size: 32,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        Positioned(
          top: topPad + 12,
          left: 16,
          child: _RecordingPill(
            accentColor: widget.preset.accent.first,
            recording: _cardioTracking && !_paused,
          ),
        ),
        if (!_cardioLocBusy)
          Positioned(
            top: topPad + 12,
            right: 16,
            child: Material(
              color: ZveltTokens.surface.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Recenter map',
                icon: const Icon(AppIcons.location_alt, size: 20),
                color: ZveltTokens.text,
                onPressed: _recenterCardioMap,
              ),
            ),
          ),
        // Metric cards overlaid on the map (Distance / Pace / Elev / Duration).
        Positioned(
          top: topPad + 64,
          left: 16,
          child: MapMetricsOverlay(
            distanceM: _routeTracker.meters,
            elapsed: Duration(seconds: _elapsedSeconds),
            elevGainM: _routeTracker.elevGainM,
          ),
        ),
        if (_cardioError != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 132,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: ZveltTokens.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                border:
                    Border.all(color: ZveltTokens.error.withValues(alpha: 0.4)),
              ),
              // Retry button so the user can re-init GPS after granting
              // permission in system settings — otherwise the error
              // banner stayed pinned and the only escape was closing
              // the workout entirely.
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _cardioError!,
                      style: const TextStyle(
                          color: ZveltTokens.error, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _cardioLocBusy ? null : _initCardioLocation,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: ZveltTokens.brand,
                    ),
                    child: const Text('Retry',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        // Slim bottom control panel.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rLg)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 18,
                    offset: Offset(0, -4)),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      [
                        if (kcal > 0) '$kcal kcal (est.)',
                        if (avgKmh > 0) '${avgKmh.toStringAsFixed(1)} km/h avg',
                        _cardioTracking ? 'GPS live' : 'GPS —',
                      ].join(' · '),
                      style: TextStyle(
                          color: ZveltTokens.text2, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _togglePause,
                            icon: Icon(_paused
                                ? AppIcons.play
                                : AppIcons.pause),
                            label: Text(_paused ? 'Resume' : 'Pause'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ZveltTokens.text,
                              side: BorderSide(color: ZveltTokens.border),
                              padding: const EdgeInsets.symmetric(
                                  vertical: ZveltTokens.s4),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(ZveltTokens.rSm)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _finishWorkout,
                            icon: const Icon(AppIcons.stop),
                            label: const Text('Finish'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.preset.accent.first,
                              foregroundColor: ZveltTokens.onBrand,
                              padding: const EdgeInsets.symmetric(
                                  vertical: ZveltTokens.s4),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(ZveltTokens.rSm)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Gym live ───────────────────────────────────────────────────────────────

  // Shown when the workout couldn't be created/loaded (offline / server error)
  // — an honest retry state instead of a live-looking logger that drops sets.
  Widget _bootstrapFailedView() {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(AppIcons.cross_small, color: ZveltTokens.text2),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(AppIcons.gym, size: 48, color: ZveltTokens.text3),
                  const SizedBox(height: 16),
                  Text(
                    _bootstrapError ??
                        "Couldn't start this workout. Check your connection "
                            'and try again.',
                    textAlign: TextAlign.center,
                    style: ZType.bodyM.copyWith(color: ZveltTokens.text2),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed:
                        _bootstrapping ? null : () => _bootstrapGymWorkout(),
                    style: FilledButton.styleFrom(
                      backgroundColor: ZveltTokens.brand,
                      foregroundColor: ZveltTokens.onBrand,
                    ),
                    child: Text(_bootstrapping ? 'Starting…' : 'Try again'),
                  ),
                  const SizedBox(height: ZveltTokens.s3),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text('Close',
                        style: ZType.bodyM.copyWith(color: ZveltTokens.text2)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGymLive() {
    final exercises = _displayExercises;
    // No server workout id yet. While bootstrapping → loader. If the bootstrap
    // FAILED (e.g. offline createWorkout threw), show a retry state — NOT the
    // live logger: _doneSet is guarded on `_workoutId != null`, so every set
    // tap would silently no-op and Finish would discard the whole session.
    if (_workoutId == null) {
      if (_bootstrapping) {
        return const Center(
            child: CircularProgressIndicator(color: ZveltTokens.brand));
      }
      return _bootstrapFailedView();
    }
    if (exercises.isEmpty) {
      // Still resolving the catalog → loader; otherwise a real dead-end (zero
      // matches, e.g. a Smart preset whose names aren't in the catalog) — show
      // an error with a way out instead of a trapped blank screen.
      if (_bootstrapping) {
        return const Center(
            child: CircularProgressIndicator(color: ZveltTokens.brand));
      }
      return SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(AppIcons.cross_small, color: ZveltTokens.text2),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(AppIcons.gym, size: 48, color: ZveltTokens.text3),
                    const SizedBox(height: 16),
                    Text(
                      _bootstrapError ??
                          "Couldn't load this workout's exercises.",
                      textAlign: TextAlign.center,
                      style: ZType.bodyM.copyWith(color: ZveltTokens.text2),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: ZveltTokens.brand,
                        foregroundColor: ZveltTokens.onBrand,
                      ),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    final ex = exercises[_currentExIdx];

    return Column(
      key: const ValueKey('gym'),
      children: [
        // Top bar
        Container(
          color: ZveltTokens.surface,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _confirmExitGym,
                    icon: Icon(AppIcons.cross_small,
                        color: ZveltTokens.text2),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          widget.preset.name.toUpperCase(),
                          style: TextStyle(
                            color: ZveltTokens.text2,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatElapsed(),
                          style: ZType.num_.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _togglePause,
                    icon: Icon(
                      _paused ? AppIcons.play : AppIcons.pause,
                      color: ZveltTokens.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Exercise progress bar
        Container(
          height: 3,
          color: ZveltTokens.bg2,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: ((_currentExIdx * 10 + _currentSet + 1) /
                    (exercises.fold(0, (s, e) => s + e.sets)))
                .clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: widget.preset.accent),
              ),
            ),
          ),
        ),
        // Main card area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ZveltTokens.s4),
            child: Column(
              children: [
                if (_bootstrapping)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(color: ZveltTokens.brand),
                  ),
                if (_bootstrapError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _bootstrapError!,
                      style: const TextStyle(
                          color: ZveltTokens.warn, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                // Current exercise card
                _resting
                    ? _RestTimerCard(
                        remaining: _restRemaining,
                        total: _restSeconds,
                        accent: widget.preset.accent,
                        onSkip: _skipRest,
                      )
                    : _SetCard(
                        exercise: ex,
                        currentSet: _currentSet,
                        accent: widget.preset.accent,
                        busy: _loggingSet || _bootstrapping,
                        weightLabel:
                            _formatSetWeightLabel(_currentWeightKg, ex.weight),
                        repsLabel: '$_currentReps',
                        onEditValues: _editSetValues,
                        onDone: _doneSet,
                      ),
                const SizedBox(height: 20),
                // Exercise list
                Text(
                  'EXERCISES',
                  style: TextStyle(
                    color: ZveltTokens.text2,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                ...exercises.asMap().entries.map((e) {
                  final idx = e.key;
                  final exItem = e.value;
                  final done = idx < _currentExIdx;
                  final current = idx == _currentExIdx;
                  return _ExerciseListRow(
                    exercise: exItem,
                    done: done,
                    current: current,
                    currentSet: current ? _currentSet : 0,
                    accent: widget.preset.accent.first,
                  );
                }),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Gym sub-widgets ──────────────────────────────────────────────────────────

class _SetCard extends StatelessWidget {
  const _SetCard({
    required this.exercise,
    required this.currentSet,
    required this.accent,
    required this.onDone,
    required this.weightLabel,
    required this.repsLabel,
    required this.onEditValues,
    this.busy = false,
  });

  final _GymExercise exercise;
  final int currentSet;
  final List<Color> accent;
  final VoidCallback onDone;
  final String weightLabel;
  final String repsLabel;
  final VoidCallback onEditValues;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s5),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        children: [
          Text(
            exercise.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              color: ZveltTokens.text,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Set ${currentSet + 1} of ${exercise.sets}',
            style: TextStyle(color: ZveltTokens.text2, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _SetStat(label: 'Reps', value: repsLabel, onTap: onEditValues),
              Container(width: 1, height: 40, color: ZveltTokens.border),
              _SetStat(
                  label: 'Weight', value: weightLabel, onTap: onEditValues),
            ],
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: busy ? null : onEditValues,
            icon: const Icon(AppIcons.settings_sliders, size: 16),
            label: const Text('Adjust weight & reps'),
            style: TextButton.styleFrom(foregroundColor: ZveltTokens.brand),
          ),
          const SizedBox(height: ZveltTokens.s4),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: busy ? null : onDone,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent.first,
                foregroundColor: ZveltTokens.onBrand,
                padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ZveltTokens.rMd)),
                elevation: 0,
              ),
              child: Text(
                busy ? 'Saving…' : 'Done Set ✓',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetStat extends StatelessWidget {
  const _SetStat({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      children: [
        Text(
          value,
          style: ZType.num_.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
        ),
      ],
    );
    return Expanded(
      child: onTap == null
          ? child
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(ZveltTokens.rSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s1),
                child: child,
              ),
            ),
    );
  }
}

class _RestTimerCard extends StatelessWidget {
  const _RestTimerCard({
    required this.remaining,
    required this.total,
    required this.accent,
    required this.onSkip,
  });

  final int remaining;
  final int total;
  final List<Color> accent;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: accent.map((c) => c.withValues(alpha: 0.25)).toList(),
        ),
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        border: Border.all(color: accent.first.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            'REST',
            style: TextStyle(
              color: accent.first,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$remaining',
            style: ZType.num_.copyWith(
              fontStyle: FontStyle.italic,
              fontSize: 72,
              fontWeight: FontWeight.w900,
              color: ZveltTokens.text,
              height: 1.0,
            ),
          ),
          Text(
            'seconds',
            style: TextStyle(color: ZveltTokens.text2, fontSize: 13),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: remaining / total,
            backgroundColor: ZveltTokens.border,
            valueColor: AlwaysStoppedAnimation<Color>(accent.first),
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
            minHeight: 4,
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: onSkip,
            style: OutlinedButton.styleFrom(
              foregroundColor: accent.first,
              side: BorderSide(color: accent.first),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
              padding: const EdgeInsets.symmetric(
                  horizontal: ZveltTokens.s6, vertical: 10),
            ),
            child: const Text('Skip Rest →',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ExerciseListRow extends StatelessWidget {
  const _ExerciseListRow({
    required this.exercise,
    required this.done,
    required this.current,
    required this.currentSet,
    required this.accent,
  });

  final _GymExercise exercise;
  final bool done;
  final bool current;
  final int currentSet;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: ZveltTokens.s2),
      padding:
          const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: 10),
      decoration: BoxDecoration(
        color: current ? accent.withValues(alpha: 0.12) : ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
        border: Border.all(
          color: current ? accent.withValues(alpha: 0.5) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? ZveltTokens.success.withValues(alpha: 0.2)
                  : current
                      ? accent.withValues(alpha: 0.2)
                      : ZveltTokens.bg2,
            ),
            child: Icon(
              done
                  ? AppIcons.check
                  : current
                      ? AppIcons.play
                      : AppIcons.circle,
              size: 16,
              color: done
                  ? ZveltTokens.success
                  : current
                      ? accent
                      : ZveltTokens.text2.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  style: TextStyle(
                    color: done ? ZveltTokens.text2 : ZveltTokens.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  // The weight here is a SUGGESTION from the preset, not the
                  // user's actual lifting weight. Mark it as such so new users
                  // don't think we're claiming they bench 80kg.
                  '${exercise.sets} × ${exercise.repsRange} · suggested ${exercise.weight}',
                  style: TextStyle(
                    color: ZveltTokens.text2,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          if (current)
            Text(
              '${currentSet + 1}/${exercise.sets}',
              style: TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (done)
            const Text(
              '✓',
              style: TextStyle(
                  color: ZveltTokens.success,
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}

// ─── Cardio sub-widgets ───────────────────────────────────────────────────────

class _RecordingPill extends StatefulWidget {
  const _RecordingPill({required this.accentColor, this.recording = true});

  final Color accentColor;
  final bool recording;

  @override
  State<_RecordingPill> createState() => _RecordingPillState();
}

class _RecordingPillState extends State<_RecordingPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ZveltTokens.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _blink,
            builder: (_, __) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.accentColor
                    .withValues(alpha: 0.4 + _blink.value * 0.6),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.recording ? 'REC' : 'PAUSED',
            style: TextStyle(
              color: ZveltTokens.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
