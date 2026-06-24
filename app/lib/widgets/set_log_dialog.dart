import 'package:flutter/material.dart';

import '../models/exercise_load_policy.dart';
import '../services/workout_service.dart';
import '../theme/zvelt_tokens.dart';
import 'plate_calculator.dart';

/// Dialog for logging weight, reps, and optional RPE for a set.
class SetLogDialog extends StatefulWidget {
  const SetLogDialog({
    super.key,
    required this.exercise,
    required this.initialWeight,
    required this.initialReps,
    required this.maxReps,
    required this.title,
    this.allowTagSelection = false,
    this.timeMaxSeconds = 600,
    this.timeDivisions = 119,
    this.holdInitGuardMax = 900,
  });

  final ExerciseDto exercise;
  final double initialWeight;
  final int initialReps;
  final int maxReps;
  final String title;

  /// When true, shows a Work / Warmup / Drop selector. Warmup & drop sets are
  /// excluded from e1RM/PR server-side (brief §8). Only the ADD path persists
  /// the tag end-to-end (online + offline replay), so callers completing a
  /// pre-created set leave this false.
  final bool allowTagSelection;

  /// Upper bound (and slider max) for the time-mode seconds slider.
  final double timeMaxSeconds;

  /// Number of discrete steps on the time-mode seconds slider.
  final int timeDivisions;

  /// Upper guard applied in [initState] when seeding `_holdSeconds` from
  /// [initialWeight] for time-mode exercises.
  final double holdInitGuardMax;

  @override
  State<SetLogDialog> createState() => _SetLogDialogState();
}

class _SetLogDialogState extends State<SetLogDialog> {
  late final SetLogMode _mode;
  late double _weightKg;
  late int _reps;
  late double _holdSeconds;
  double? _rpe;
  String _tag = 'WORK';

  @override
  void initState() {
    super.initState();
    _mode = setLogModeForExercise(widget.exercise);
    _weightKg = widget.initialWeight.clamp(0.0, 500.0);
    _reps = widget.initialReps.clamp(1, widget.maxReps);
    _holdSeconds = (widget.initialWeight >= 5 && widget.initialWeight <= widget.holdInitGuardMax)
        ? widget.initialWeight
        : 45.0;
    _rpe = null;
  }

  void _submit() {
    switch (_mode) {
      case SetLogMode.weighted:
        Navigator.of(context).pop((_weightKg, _reps, _rpe, _tag));
        break;
      case SetLogMode.bodyweightReps:
        Navigator.of(context).pop((0.0, _reps, _rpe, _tag));
        break;
      case SetLogMode.timeSeconds:
        Navigator.of(context).pop((_holdSeconds.roundToDouble(), 1, _rpe, _tag));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ZveltTokens.surface,
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_mode == SetLogMode.weighted) ...[
              Row(
                children: [
                  const Text('Weight (kg) '),
                  Expanded(
                    child: Slider(
                      value: _weightKg.clamp(0, 300),
                      min: 0,
                      max: 300,
                      divisions: 300,
                      onChanged: (v) => setState(() => _weightKg = v),
                    ),
                  ),
                  Text(_weightKg.clamp(0, 300).toStringAsFixed(0)),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => showPlateCalculator(context, _weightKg),
                  icon: const Icon(Icons.fitness_center, size: 16),
                  label: const Text('Plate calculator'),
                  style: TextButton.styleFrom(
                    foregroundColor: ZveltTokens.brandDeep,
                    padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s2),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              Row(
                children: [
                  const Text('Reps '),
                  Expanded(
                    child: Slider(
                      value: _reps.toDouble().clamp(1, widget.maxReps.toDouble()),
                      min: 1,
                      max: widget.maxReps.toDouble(),
                      divisions: widget.maxReps > 1 ? widget.maxReps - 1 : null,
                      onChanged: (v) => setState(() => _reps = v.round().clamp(1, widget.maxReps)),
                    ),
                  ),
                  Text('$_reps'),
                ],
              ),
            ],
            if (_mode == SetLogMode.bodyweightReps) ...[
              Text(
                'No added weight — log reps only.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ZveltTokens.text2),
              ),
              const SizedBox(height: ZveltTokens.s2),
              Row(
                children: [
                  const Text('Reps '),
                  Expanded(
                    child: Slider(
                      value: _reps.toDouble().clamp(1, widget.maxReps.toDouble()),
                      min: 1,
                      max: widget.maxReps.toDouble(),
                      divisions: widget.maxReps > 1 ? widget.maxReps - 1 : null,
                      onChanged: (v) => setState(() => _reps = v.round().clamp(1, widget.maxReps)),
                    ),
                  ),
                  Text('$_reps'),
                ],
              ),
            ],
            if (_mode == SetLogMode.timeSeconds) ...[
              Text(
                'Time is stored as duration (seconds).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ZveltTokens.text2),
              ),
              const SizedBox(height: ZveltTokens.s2),
              Row(
                children: [
                  const Text('Seconds '),
                  Expanded(
                    child: Slider(
                      value: _holdSeconds.clamp(5, widget.timeMaxSeconds),
                      min: 5,
                      max: widget.timeMaxSeconds,
                      divisions: widget.timeDivisions,
                      onChanged: (v) => setState(() => _holdSeconds = v),
                    ),
                  ),
                  Text('${_holdSeconds.round()}'),
                ],
              ),
            ],
            if (widget.allowTagSelection && _mode != SetLogMode.timeSeconds) ...[
              const SizedBox(height: ZveltTokens.s2),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Set type',
                    style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
              ),
              const SizedBox(height: ZveltTokens.s1),
              Row(
                children: [
                  for (final t in const [
                    ('WORK', 'Work'),
                    ('WARMUP', 'Warmup'),
                    ('DROP', 'Drop'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: ZveltTokens.s2),
                      child: ChoiceChip(
                        label: Text(t.$2),
                        selected: _tag == t.$1,
                        onSelected: (_) => setState(() => _tag = t.$1),
                        selectedColor: ZveltTokens.brandTint,
                        labelStyle: ZType.bodyS.copyWith(
                          color: _tag == t.$1 ? ZveltTokens.brandDeep : ZveltTokens.text2,
                          fontWeight: _tag == t.$1 ? FontWeight.w600 : FontWeight.w400,
                        ),
                        side: BorderSide.none,
                      ),
                    ),
                ],
              ),
            ],
            Row(
              children: [
                const Text('RPE (optional) '),
                Expanded(
                  child: Slider(
                    value: (_rpe ?? 7),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    onChanged: (v) => setState(() => _rpe = v),
                  ),
                ),
                Text(_rpe?.toStringAsFixed(1) ?? '—'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
