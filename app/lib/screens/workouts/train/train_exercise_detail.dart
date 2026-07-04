import 'package:flutter/material.dart';

import '../../../services/exercise_db_service.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/zvelt_tokens.dart';
import '../../../widgets/zvelt_network_image.dart';

/// Exercise detail — full-screen page pushed via Navigator. 1:1 with the design
/// handoff: back button + title, a 3-up stat grid, a 7-session volume trend
/// chart, muscle chips, an instructions block, and a sticky-feel "Add to
/// Workout" CTA at the bottom.
///
/// Neutrals come from the theme-aware [ZveltTokens] getters, so the decorations
/// and styles that read them can't be `const` (only the brand/status colors and
/// shadows are compile-time constants).
class TrainExerciseDetailScreen extends StatelessWidget {
  const TrainExerciseDetailScreen({
    super.key,
    this.name = 'Bench Press',
    this.lastSet = '70 kg × 8',
    this.best = '80 kg × 5',
    this.volumeDeltaLabel = '+8% · last 7',
    this.bars = const [0.40, 0.55, 0.48, 0.70, 0.60, 0.88, 1.00],
    this.muscles = const ['Chest', 'Shoulders', 'Triceps'],
    this.instructions =
        'Lie flat with feet planted and shoulder blades pinched. Lower the bar '
        'under control to mid-chest, then press up and slightly back. Keep your '
        'wrists stacked over your elbows and stop a rep short of failure.',
    this.onAddToWorkout,
  });

  final String name, lastSet, best, volumeDeltaLabel, instructions;
  final List<double> bars;
  final List<String> muscles;
  final VoidCallback? onAddToWorkout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          children: [
            // ── Back button ──────────────────────────────────────────────
            _BackButton(onTap: () => Navigator.maybePop(context)),
            const SizedBox(height: 16),

            // ── Title ────────────────────────────────────────────────────
            Text(
              name,
              style: ZType.h1.copyWith(
                color: ZveltTokens.text,
                fontWeight: FontWeight.w700,
                fontSize: 26,
                letterSpacing: -0.02 * 26,
              ),
            ),
            const SizedBox(height: 18),

            // ── Exercise demo GIF (ExerciseDB via the backend proxy) ─────
            _ExerciseGif(name: name),

            // ── Stat cards (3-col) ───────────────────────────────────────
            Row(
              children: [
                Expanded(child: _StatCard(label: 'Last set', value: lastSet)),
                const SizedBox(width: 11),
                Expanded(child: _StatCard(label: 'Best', value: best)),
                const SizedBox(width: 11),
                Expanded(
                  child: _StatCard(
                    label: 'Volume',
                    value: volumeDeltaLabel,
                    valueColor: ZveltTokens.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Volume trend chart ───────────────────────────────────────
            _VolumeTrendCard(bars: bars),
            const SizedBox(height: 18),

            // ── Muscles worked ───────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in muscles) _MuscleChip(label: m),
              ],
            ),
            const SizedBox(height: 18),

            // ── Instructions ─────────────────────────────────────────────
            Text(
              'INSTRUCTIONS',
              style: ZType.bodyS.copyWith(
                color: ZveltTokens.text2,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.1 * 13,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              instructions,
              style: ZType.bodyM.copyWith(
                color: ZveltTokens.text,
                fontWeight: FontWeight.w400,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),

            // ── Add to Workout CTA ───────────────────────────────────────
            _AddToWorkoutButton(
              onTap: onAddToWorkout ?? () => Navigator.maybePop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// 40×40 circular back button — card surface, soft shadow, chevron-left.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZveltTokens.surface,
      shape: const CircleBorder(),
      shadowColor: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          shape: BoxShape.circle,
          boxShadow: ZveltTokens.shadowCard,
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              AppIcons.angle_small_left,
              color: ZveltTokens.text2,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the three center-aligned stat cards.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: ZType.bodyS.copyWith(
              color: ZveltTokens.text2,
              fontWeight: FontWeight.w400,
              fontSize: 11,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ZType.bodyM.copyWith(
              color: valueColor ?? ZveltTokens.text,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Volume trend card — label + a 7-bar mini chart aligned to the bottom. The 3
/// most-recent (rightmost) bars use the accent; older bars use the muted accent.
class _VolumeTrendCard extends StatelessWidget {
  const _VolumeTrendCard({required this.bars});

  final List<double> bars;

  static const double _chartHeight = 72;

  @override
  Widget build(BuildContext context) {
    final n = bars.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Volume trend — last $n ${n == 1 ? 'session' : 'sessions'}',
            style: ZType.bodyS.copyWith(
              color: ZveltTokens.text2,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: _chartHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: (bars[i].clamp(0.0, 1.0) * _chartHeight)
                            .clamp(2.0, _chartHeight),
                        decoration: BoxDecoration(
                          color: i >= n - 3
                              ? ZveltTokens.brand
                              : ZveltTokens.brand2,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Accent-soft chip for a worked muscle.
class _MuscleChip extends StatelessWidget {
  const _MuscleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: ZveltTokens.brandTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: ZType.bodyS.copyWith(
          color: ZveltTokens.brand,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Full-width accent CTA with the periwinkle glow.
class _AddToWorkoutButton extends StatelessWidget {
  const _AddToWorkoutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: ZveltTokens.glowBrand,
      ),
      child: Material(
        color: ZveltTokens.brand,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            alignment: Alignment.center,
            child: Text(
              'Add to Workout',
              style: ZType.bodyL.copyWith(
                color: ZveltTokens.onBrand,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Resolves the exercise's demo GIF by name through the backend ExerciseDB
/// proxy and renders it. Shows nothing while loading or when unavailable
/// (e.g. the server has no EXERCISEDB_KEY) — degrades gracefully, no broken box.
class _ExerciseGif extends StatefulWidget {
  const _ExerciseGif({required this.name});

  final String name;

  @override
  State<_ExerciseGif> createState() => _ExerciseGifState();
}

class _ExerciseGifState extends State<_ExerciseGif> {
  String? _gifUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await ExerciseDbService().searchByName(widget.name);
      final withGif = results.where((e) => e.hasGif).toList();
      if (!mounted) return;
      setState(() => _gifUrl = withGif.isNotEmpty ? withGif.first.gifUrl : null);
    } catch (_) {
      // 503 (key not set) / offline / no match → just show no GIF.
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _gifUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: ZveltTokens.shadowCard,
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 1,
          child: ZveltNetworkImage(url: url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
