// createState() returning a private State is the standard Flutter idiom; the
// lint is a known false positive here.
// ignore_for_file: library_private_types_in_public_api
import 'dart:async';
import 'package:zvelt_app/theme/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:uuid/uuid.dart';
import 'xp_complete_screen.dart';
import 'workout_tracker_screen.dart';
import '../ai/ai_chat_screen.dart';
import '../analytics/photo_capture_screen.dart';
import '../nutrition/nutrition_tab.dart';
import '../outdoor/outdoor_track_screen.dart';
import '../social/race_hub_screen.dart';

// ─── Data models ─────────────────────────────────────────────────────────────

enum _PresetType { cardio, gym }

class _GymExercise {
  const _GymExercise(this.name, this.sets, this.repsRange, this.weight);
  final String name;
  final int sets;
  final String repsRange;
  final String weight;
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

const _kDefaultPresetKey = 'fab_default_preset_id';

FabPreset _presetById(String id) => _kAllPresets.firstWhere((p) => p.id == id,
    orElse: () => _kAllPresets.first);

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
  final met = mode == 'bike' ? 6.0 : 9.0;
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
  bool _library = false;
  final Map<String, bool> _shortcutValues = {
    SettingsKeys.scEmpty: true,
    SettingsKeys.scAi: true,
    SettingsKeys.scRun: true,
    SettingsKeys.scMeal: false,
    SettingsKeys.scRace: false,
    SettingsKeys.scPhoto: false,
  };

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
  }

  Future<void> _loadShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (final key in _shortcutValues.keys.toList()) {
        _shortcutValues[key] = prefs.getBool(key) ?? _shortcutValues[key]!;
      }
    });
  }

  Future<void> _openShortcut(String key) async {
    final nav = Navigator.of(context);
    nav.pop();
    switch (key) {
      case SettingsKeys.scEmpty:
        final workout =
            await WorkoutService().createWorkout(label: 'Empty workout');
        await nav.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutTrackerScreen(workoutId: workout.id),
          ),
        );
        break;
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

  /// Long-press on any tile/row pins it as the FAB long-press default —
  /// silent app extra; the design's sheet has no default-preset concept.
  Future<void> _saveDefault(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultPresetKey, id);
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

  /// Design eyebrow with the bolt icon prefix.
  Widget _eyebrow(String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(AppIcons.bolt, size: 12, color: ZveltTokens.brand),
        const SizedBox(width: 4),
        Text(
          text.toUpperCase(),
          style: ZType.eyebrow.copyWith(color: ZveltTokens.text2, fontSize: 11),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── Design (quick-launch.jsx): home = "Quick start / What are we
    // doing?" + 2×2 tile grid (Push / Pull / Legs / Cardio) + "Browse
    // library →"; library = back + "Choose an activity" + activity list.
    // App-specific: tiles map to the real preset starters (countdown →
    // GPS tracker or gym bootstrap); Cardio opens the library, where the
    // GPS activities live. Long-press still sets the FAB default (silent
    // extra). Only activities we can actually track are listed — design's
    // Swim/Yoga/Hike rows have no tracking flow yet, so they're absent.
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
        boxShadow: ZveltTokens.shadowHero,
      ),
      padding: const EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH,
          ZveltTokens.s3, ZveltTokens.screenPaddingH, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: ZveltTokens.s3),
            decoration: BoxDecoration(
              color: ZveltTokens.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (!_library) ...[
            // ── Home: header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _eyebrow('Quick start'),
                    const SizedBox(height: 4),
                    Text(
                      'What are we doing?',
                      style: ZType.display
                          .copyWith(fontSize: 24, color: ZveltTokens.text),
                    ),
                  ],
                ),
              ),
            ),
            // ── 2×2 tile grid ─────────────────────────────────────────
            if (_shortcutValues.values.any((enabled) => enabled)) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                  child: Text(
                    'YOUR SHORTCUTS',
                    style: ZType.eyebrow.copyWith(color: ZveltTokens.text3),
                  ),
                ),
              ),
              SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (_shortcutValues[SettingsKeys.scEmpty]!)
                      _ShortcutAction(
                          label: 'Empty',
                          icon: AppIcons.plus,
                          onTap: () => _openShortcut(SettingsKeys.scEmpty)),
                    if (_shortcutValues[SettingsKeys.scAi]!)
                      _ShortcutAction(
                          label: 'AI workout',
                          icon: AppIcons.sparkles,
                          onTap: () => _openShortcut(SettingsKeys.scAi)),
                    if (_shortcutValues[SettingsKeys.scRun]!)
                      _ShortcutAction(
                          label: 'Run',
                          icon: AppIcons.running,
                          onTap: () => _openShortcut(SettingsKeys.scRun)),
                    if (_shortcutValues[SettingsKeys.scMeal]!)
                      _ShortcutAction(
                          label: 'Meal',
                          icon: AppIcons.restaurant,
                          onTap: () => _openShortcut(SettingsKeys.scMeal)),
                    if (_shortcutValues[SettingsKeys.scRace]!)
                      _ShortcutAction(
                          label: 'Race',
                          icon: AppIcons.trophy,
                          onTap: () => _openShortcut(SettingsKeys.scRace)),
                    if (_shortcutValues[SettingsKeys.scPhoto]!)
                      _ShortcutAction(
                          label: 'Photo',
                          icon: AppIcons.camera,
                          onTap: () => _openShortcut(SettingsKeys.scPhoto)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: _QuickTile(
                    label: 'Push',
                    sub: 'Chest · Shoulders',
                    icon: AppIcons.bolt,
                    color: ZveltTokens.brand,
                    onTap: () => _startPreset(_presetById('push')),
                    onLongPress: () => _saveDefault('push'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickTile(
                    label: 'Pull',
                    sub: 'Back · Biceps',
                    icon: AppIcons.gym,
                    color: ZveltTokens.brand,
                    onTap: () => _startPreset(_presetById('pull')),
                    onLongPress: () => _saveDefault('pull'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _QuickTile(
                    label: 'Legs',
                    sub: 'Quads · Glutes',
                    icon: AppIcons.target,
                    color: ZveltTokens.warn,
                    onTap: () => _startPreset(_presetById('legs')),
                    onLongPress: () => _saveDefault('legs'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickTile(
                    label: 'Cardio',
                    sub: 'Run · Bike',
                    icon: AppIcons.running,
                    color: ZveltTokens.info,
                    onTap: () => setState(() => _library = true),
                  ),
                ),
              ],
            ),
            // ── Browse library ────────────────────────────────────────
            TextButton(
              onPressed: () => setState(() => _library = true),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.all(ZveltTokens.s4),
                minimumSize: const Size(0, 44),
              ),
              child: Text(
                'Browse library →',
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ZveltTokens.text2,
                ),
              ),
            ),
          ] else ...[
            // ── Library: header with back ─────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, ZveltTokens.s4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _library = false),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ZveltTokens.surface,
                        border: Border.all(color: ZveltTokens.border),
                      ),
                      child: Icon(AppIcons.arrow_small_left,
                          size: 18, color: ZveltTokens.text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _eyebrow('Library'),
                      const SizedBox(height: 2),
                      Text(
                        'Choose an activity',
                        style: ZType.display
                            .copyWith(fontSize: 24, color: ZveltTokens.text),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // ── Activity list ─────────────────────────────────────────
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _kAllPresets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final p = _kAllPresets[i];
                  return _LibraryRow(
                    preset: p,
                    onTap: () => _startPreset(p),
                    onLongPress: () => _saveDefault(p.id),
                  );
                },
              ),
            ),
          ],
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
        ],
      ),
    );
  }
}

// ─── Quick tile (design 2×2 grid cell) ───────────────────────────────────────

class _ShortcutAction extends StatelessWidget {
  const _ShortcutAction(
      {required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        child: Container(
          constraints: const BoxConstraints(minWidth: 72),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            border: Border.all(color: ZveltTokens.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: ZveltTokens.brand),
              const SizedBox(height: 4),
              Text(
                label,
                style: ZType.bodyS
                    .copyWith(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.label,
    required this.sub,
    required this.icon,
    required this.color,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    // Design: surface card r20 minHeight 130, radial glow blob top-right,
    // 44px icon halo at 8% tint, bottom-aligned sub eyebrow + 26px label.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        child: Ink(
          height: 130,
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            child: Stack(
              children: [
                Positioned(
                  top: -20,
                  right: -20,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          color.withValues(alpha: 0.18),
                          color.withValues(alpha: 0),
                        ],
                        stops: const [0.0, 0.7],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(ZveltTokens.s5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                        ),
                        child: Icon(icon, size: 22, color: color),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sub.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ZType.eyebrow,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: ZType.display.copyWith(
                              fontSize: 24,
                              color: ZveltTokens.text,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Library row (design activity list item) ─────────────────────────────────

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({
    required this.preset,
    required this.onTap,
    this.onLongPress,
  });

  final FabPreset preset;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  Color get _color => preset.isCardio ? ZveltTokens.info : ZveltTokens.brand;

  @override
  Widget build(BuildContext context) {
    // Design: surface row r16 padding 14, 44px halo at 8% tint, 15/600
    // label + 11.5 sub, plus icon on the right.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
        child: Ink(
          padding: const EdgeInsets.all(ZveltTokens.s4),
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                ),
                child: Icon(preset.icon, size: 22, color: _color),
              ),
              const SizedBox(width: ZveltTokens.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.name,
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ZveltTokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preset.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontSize: 11,
                        color: ZveltTokens.text2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(AppIcons.plus, size: 18, color: ZveltTokens.text3),
            ],
          ),
        ),
      ),
    );
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

  late final AnimationController _pulseAnim;

  String get _cardioMode => widget.preset.id == 'bike' ? 'bike' : 'run';

  @override
  void initState() {
    super.initState();
    _countdownScale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
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

  Future<void> _editSetValues() async {
    final exercises = _displayExercises;
    if (_currentExIdx >= exercises.length) return;
    final presetEx = exercises[_currentExIdx];
    if (_currentExIdx >= _workoutExercises.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workout is still loading. Try again in a moment.'),
          backgroundColor: ZveltTokens.warn,
        ),
      );
      return;
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
    if (result == null || !mounted) return;
    setState(() {
      _currentWeightKg = result.$1;
      _currentReps = result.$2;
      _currentRpe = result.$3;
    });
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

      final workout = await _workoutService.createWorkout();
      final added = <WorkoutExerciseDto>[];
      final display = <_GymExercise>[];
      // Track preset exercises that couldn't be resolved so the user sees
      // a partial-match warning instead of silently getting fewer exercises.
      final skipped = <String>[];
      // Run all catalog name lookups in parallel (one round-trip instead of
      // up to N chained ones). Each lookup keeps its own try/catch so a single
      // network blip degrades that exercise to a skip without killing the rest.
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
              // Network blip on a single exercise lookup shouldn't kill the
              // whole bootstrap — log and continue with the rest of the preset.
              return null;
            }
          }(),
      ]);
      // History-aware prefill: replace the generic preset weights with the
      // user's most recent working weight per lift (best-effort; falls back to
      // the preset label when there's no history). Kills the "edit 6 fake sets
      // before you start" tax and stops showing a beginner 140kg deadlifts.
      final matchedIds = [for (final m in matches) if (m != null) m.id];
      final lastWeights =
          await _workoutService.getLastWorkingWeights(matchedIds);
      // Adds stay SEQUENTIAL in preset order: the backend auto-assigns
      // position = lastPosition + 1, so concurrent adds would scramble order.
      for (var i = 0; i < _displayExercises.length; i++) {
        final ex = _displayExercises[i];
        final match = matches[i];
        if (match == null) {
          skipped.add(ex.name);
          continue;
        }
        final we = await _workoutService.addExercise(workout.id, match.id);
        added.add(we);
        final histKg = lastWeights[match.id];
        final weightLabel = histKg != null
            ? '${histKg.toStringAsFixed(histKg % 1 == 0 ? 0 : 1)} kg'
            : ex.weight;
        display.add(_GymExercise(match.name, ex.sets, ex.repsRange, weightLabel));
      }
      if (!mounted) return;
      setState(() {
        _workoutId = workout.id;
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
      final kind =
          _cardioMode == 'bike' ? ActivityKind.cycle : ActivityKind.run;
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

  Future<void> _finishWorkout() async {
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

    if (_workoutId != null &&
        _currentExIdx < _workoutExercises.length &&
        !_loggingSet) {
      setState(() => _loggingSet = true);
      // Same client-side UUID used for the POST and any later retry from the
      // offline queue, so the server dedupes on `clientSetId` instead of
      // creating duplicate sets when the network blip resolves.
      final clientSetId = const Uuid().v4();
      final we = _workoutExercises[_currentExIdx];
      try {
        await _workoutService.addSet(
          _workoutId!,
          we.id,
          weightKg: _currentWeightKg,
          reps: _currentReps,
          rpe: _currentRpe,
          clientSetId: clientSetId,
        );
        await _saveDraftSnapshot();
      } catch (_) {
        // Honor offline-first: enqueue the set and tell the user it'll sync.
        // Coordinator's connectivity listener flushes automatically on reconnect.
        await OfflineSyncCoordinator.instance.enqueue(
          PendingSetEntry(
            workoutId: _workoutId!,
            weId: we.id,
            weightKg: _currentWeightKg,
            reps: _currentReps,
            rpe: _currentRpe,
            clientSetId: clientSetId,
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
      } finally {
        if (mounted) setState(() => _loggingSet = false);
      }
    }

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
    _pulseAnim.dispose();
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

  Widget _buildGymLive() {
    final exercises = _displayExercises;
    if (exercises.isEmpty) return const SizedBox.shrink();
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
