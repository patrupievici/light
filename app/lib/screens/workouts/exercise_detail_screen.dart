import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import '../../services/workout_service.dart';
import '../../widgets/exercise_gif_dialog.dart';
import '../../widgets/zvelt_network_image.dart';

/// Full-page detail view for a single exercise.
class ExerciseDetailScreen extends StatelessWidget {
  const ExerciseDetailScreen({super.key, required this.exercise});

  final ExerciseDto exercise;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        title: Text(
          exercise.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(AppIcons.cross_small),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'View reference GIF',
            icon: const Icon(AppIcons.play),
            onPressed: () => ExerciseGifDialog.show(
              context,
              exerciseName: exercise.name,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SizedBox(height: 12),
          _MediaBanner(exercise: exercise),
          const SizedBox(height: 16),
          _InfoChipRow(exercise: exercise),
          if (exercise.description != null && exercise.description!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              exercise.description!,
              style: TextStyle(
                color: ZveltTokens.text2,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
          const SizedBox(height: 24),
          _SectionCard(
            title: 'MUSCLES',
            child: _MusclesSection(exercise: exercise),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'MOVEMENT',
            child: _MovementSection(exercise: exercise),
          ),
          if (exercise.goalTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'GOALS',
              child: _GoalsSection(exercise: exercise),
            ),
          ],
          const SizedBox(height: 12),
          _SectionCard(
            title: 'RANK TYPE',
            child: _RankTypeSection(exercise: exercise),
          ),
          if (exercise.instructions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'INSTRUCTIONS',
              child: _InstructionsSection(exercise: exercise),
            ),
          ],
          if (exercise.contraindications.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ContraindicationsCard(exercise: exercise),
          ],
        ],
      ),
    );
  }
}

// ─── Media banner ─────────────────────────────────────────────────────────────

class _MediaBanner extends StatelessWidget {
  const _MediaBanner({required this.exercise});

  final ExerciseDto exercise;

  @override
  Widget build(BuildContext context) {
    final media = exercise.media.isNotEmpty ? exercise.media.first : null;
    final preview = media?.previewUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(ZveltTokens.rLg),
      child: SizedBox(
        height: 220,
        width: double.infinity,
        child: preview != null && preview.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ZveltNetworkImage(
                    url: preview,
                    fit: BoxFit.cover,
                    cacheWidth: ZveltImageCacheWidth.feedFull,
                    errorWidget: (_) => const _MediaPlaceholder(),
                  ),
                  if (media!.isVideo)
                    const Center(
                      child: Icon(
                        AppIcons.play,
                        color: Colors.white,
                        size: 56,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
                      ),
                    ),
                ],
              )
            : const _MediaPlaceholder(),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ZveltTokens.bg2,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(AppIcons.gym, color: ZveltTokens.brand, size: 52),
          const SizedBox(height: 8),
          Text(
            'No media',
            style: TextStyle(color: ZveltTokens.text2, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Top chip row ─────────────────────────────────────────────────────────────

class _InfoChipRow extends StatelessWidget {
  const _InfoChipRow({required this.exercise});

  final ExerciseDto exercise;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if (exercise.primaryMuscle != null && exercise.primaryMuscle!.isNotEmpty)
        exercise.primaryMuscle!,
      if (exercise.equipment != null && exercise.equipment!.isNotEmpty)
        exercise.equipment!,
      if (exercise.category != null && exercise.category!.isNotEmpty)
        exercise.category!,
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips
          .map((label) => _SmallChip(label: label, prominent: chips.indexOf(label) == 0))
          .toList(),
    );
  }
}

// ─── Section card wrapper ─────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s3, ZveltTokens.s4, ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: ZveltTokens.fontMono,
              color: ZveltTokens.text2,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: ZveltTokens.s2),
          child,
        ],
      ),
    );
  }
}

// ─── Muscles ──────────────────────────────────────────────────────────────────

class _MusclesSection extends StatelessWidget {
  const _MusclesSection({required this.exercise});

  final ExerciseDto exercise;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (exercise.primaryMuscle != null && exercise.primaryMuscle!.isNotEmpty)
          Text(
            exercise.primaryMuscle!,
            style: TextStyle(
              color: ZveltTokens.text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        if (exercise.secondaryMuscles.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                exercise.secondaryMuscles.map((m) => _SmallChip(label: m)).toList(),
          ),
        ],
        if (exercise.primaryMuscle == null && exercise.secondaryMuscles.isEmpty)
          Text(
            'Not specified',
            style: TextStyle(color: ZveltTokens.text2, fontSize: 13),
          ),
      ],
    );
  }
}

// ─── Movement ─────────────────────────────────────────────────────────────────

class _MovementSection extends StatelessWidget {
  const _MovementSection({required this.exercise});

  final ExerciseDto exercise;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (exercise.movementPattern != null && exercise.movementPattern!.isNotEmpty)
          Text(
            exercise.movementPattern!,
            style: TextStyle(
              color: ZveltTokens.text,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (exercise.fatigueScore != null) ...[
              _FatigueDots(score: exercise.fatigueScore!),
              const SizedBox(width: 8),
              Text(
                'fatigue ${exercise.fatigueScore}/5',
                style: TextStyle(color: ZveltTokens.text2, fontSize: 12),
              ),
              const SizedBox(width: 16),
            ],
            if (exercise.beginnerSuitable)
              const _BadgeChip(
                label: 'Beginner friendly',
                icon: AppIcons.heart,
                color: ZveltTokens.success,
              )
            else
              const _BadgeChip(
                label: 'Advanced',
                icon: AppIcons.flame,
                color: ZveltTokens.warn,
              ),
          ],
        ),
      ],
    );
  }
}

// ─── Goals ────────────────────────────────────────────────────────────────────

class _GoalsSection extends StatelessWidget {
  const _GoalsSection({required this.exercise});

  final ExerciseDto exercise;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: exercise.goalTags.map((tag) => _SmallChip(label: tag)).toList(),
    );
  }
}

// ─── Instructions ─────────────────────────────────────────────────────────────

class _InstructionsSection extends StatelessWidget {
  const _InstructionsSection({required this.exercise});

  final ExerciseDto exercise;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < exercise.instructions.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ZveltTokens.bg2,
                  border: Border.all(color: ZveltTokens.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontMono,
                    color: ZveltTokens.text2,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  exercise.instructions[i],
                  style: TextStyle(
                    color: ZveltTokens.text,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─── Rank type ────────────────────────────────────────────────────────────────

class _RankTypeSection extends StatelessWidget {
  const _RankTypeSection({required this.exercise});

  final ExerciseDto exercise;

  String get _label {
    switch (exercise.rankModel) {
      case 'WEIGHTED':
        return 'Barbell / Dumbbell (e1RM)';
      case 'BW_REPS':
        return 'Bodyweight (reps)';
      case 'TIME':
        return 'Time-based';
      default:
        return exercise.rankModel ?? 'Standard';
    }
  }

  IconData get _icon {
    switch (exercise.rankModel) {
      case 'WEIGHTED':
        return AppIcons.gym;
      case 'BW_REPS':
        return AppIcons.user;
      case 'TIME':
        return AppIcons.stopwatch;
      default:
        return AppIcons.chart_histogram;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ZveltTokens.brandTint,
            borderRadius: BorderRadius.circular(ZveltTokens.rSm),
          ),
          child: Icon(_icon, color: ZveltTokens.brand, size: 18),
        ),
        const SizedBox(width: 12),
        Text(
          _label,
          style: TextStyle(
            color: ZveltTokens.text,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

// ─── Contraindications warning card ──────────────────────────────────────────

class _ContraindicationsCard extends StatelessWidget {
  const _ContraindicationsCard({required this.exercise});

  final ExerciseDto exercise;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: ZveltTokens.warn.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        border: Border.all(color: ZveltTokens.warn.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(AppIcons.exclamation, color: ZveltTokens.warn, size: 18),
              SizedBox(width: 6),
              Text(
                'CAUTION',
                style: TextStyle(
                  fontFamily: ZveltTokens.fontMono,
                  color: ZveltTokens.warn,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...exercise.contraindications.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: ZveltTokens.warn, fontSize: 13)),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        color: ZveltTokens.text,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared micro-widgets ─────────────────────────────────────────────────────

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label, this.prominent = false});

  final String label;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(
          color: prominent ? ZveltTokens.brand.withValues(alpha: 0.4) : ZveltTokens.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: prominent ? ZveltTokens.text : ZveltTokens.text2,
          fontWeight: prominent ? FontWeight.w600 : FontWeight.w400,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _FatigueDots extends StatelessWidget {
  const _FatigueDots({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < score;
        return Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? ZveltTokens.warn : ZveltTokens.border,
          ),
        );
      }),
    );
  }
}
