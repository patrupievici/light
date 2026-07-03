import 'package:flutter/material.dart';

import '../../../services/workout_service.dart';
import '../../../theme/app_icons.dart';
import '../../../theme/zvelt_tokens.dart';
import '../../../utils/formatters.dart';

/// Bottom-sheet preview of the AI coach's suggested session — every exercise
/// with its targets and the "why", plus any safety warnings from the
/// generator. Pops with the suggestion to start, or null when dismissed.
///
/// [regenerate] keeps the sheet OPEN and swaps content in place: the AI
/// round-trip can take many seconds, so the user needs a visible in-progress
/// state instead of a closed sheet that silently reopens later.
Future<WorkoutSuggestionDto?> showAiWorkoutPreviewSheet(
  BuildContext context, {
  required WorkoutSuggestionDto suggestion,
  Future<WorkoutSuggestionDto> Function()? regenerate,
  ValueChanged<WorkoutSuggestionDto>? onSuggestionChanged,
}) {
  return showModalBottomSheet<WorkoutSuggestionDto>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AiWorkoutPreviewSheet(
      suggestion: suggestion,
      regenerate: regenerate,
      onSuggestionChanged: onSuggestionChanged,
    ),
  );
}

class AiWorkoutPreviewSheet extends StatefulWidget {
  const AiWorkoutPreviewSheet({
    super.key,
    required this.suggestion,
    this.regenerate,
    this.onSuggestionChanged,
  });

  final WorkoutSuggestionDto suggestion;
  final Future<WorkoutSuggestionDto> Function()? regenerate;

  /// Fired when a regenerate succeeds so the launching screen (hero / hub
  /// tile) reflects the new suggestion even if the user then dismisses.
  final ValueChanged<WorkoutSuggestionDto>? onSuggestionChanged;

  @override
  State<AiWorkoutPreviewSheet> createState() => _AiWorkoutPreviewSheetState();
}

class _AiWorkoutPreviewSheetState extends State<AiWorkoutPreviewSheet> {
  late WorkoutSuggestionDto _suggestion = widget.suggestion;
  bool _regenerating = false;
  String? _regenerateError;

  Future<void> _regenerate() async {
    final regenerate = widget.regenerate;
    if (regenerate == null || _regenerating) return;
    setState(() {
      _regenerating = true;
      _regenerateError = null;
    });
    try {
      final next = await regenerate();
      if (!mounted) return;
      setState(() {
        if (next.exercises.isNotEmpty) {
          _suggestion = next;
          widget.onSuggestionChanged?.call(next);
        }
        _regenerating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _regenerating = false;
        _regenerateError =
            "Couldn't build a new workout. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: ZveltTokens.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
          boxShadow: ZveltTokens.shadowFloat,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            _header(),
            Flexible(
              child: Stack(
                children: [
                  ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, 0,
                        ZveltTokens.s5, ZveltTokens.s3),
                    children: [
                      for (var i = 0; i < _suggestion.exercises.length; i++)
                        _exerciseRow(_suggestion.exercises[i],
                            last: i == _suggestion.exercises.length - 1),
                      if (_suggestion.warnings.isNotEmpty) _warningsCallout(),
                    ],
                  ),
                  // Regenerating veil — the old plan stays visible but clearly
                  // "on the way out"; never renders placeholder exercises.
                  if (_regenerating)
                    Positioned.fill(
                      child: ColoredBox(
                        color: ZveltTokens.surface.withValues(alpha: 0.6),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: ZveltTokens.brand),
                              ),
                              const SizedBox(height: ZveltTokens.s3),
                              Text('Building a new workout…',
                                  style: ZType.bodyS
                                      .copyWith(color: ZveltTokens.text2)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _handle() {
    return Container(
      width: 42,
      height: 5,
      margin: const EdgeInsets.only(top: ZveltTokens.s3, bottom: ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface3,
        borderRadius: BorderRadius.circular(9),
      ),
    );
  }

  Widget _header() {
    final goal = (_suggestion.primaryGoal ?? '').trim();
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(ZveltTokens.s5, 0, ZveltTokens.s5, ZveltTokens.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ZveltTokens.brandTint,
              borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            ),
            child: const Icon(AppIcons.sparkles,
                color: ZveltTokens.brand, size: 22),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "COACH'S PICK",
                  style: ZType.bodyS.copyWith(
                    color: ZveltTokens.brand,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.08 * 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(_suggestion.title,
                    style: ZType.h3.copyWith(height: 1.25)),
                if (_suggestion.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _suggestion.description.trim(),
                    style: ZType.bodyS,
                  ),
                ],
                if (goal.isNotEmpty) ...[
                  const SizedBox(height: ZveltTokens.s2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: ZveltTokens.s3, vertical: 5),
                    decoration: BoxDecoration(
                      color: ZveltTokens.brandTint,
                      borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                    ),
                    child: Text(
                      goal,
                      style: ZType.bodyS.copyWith(
                        color: ZveltTokens.brand,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
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

  Widget _exerciseRow(SuggestedExerciseDto e, {required bool last}) {
    final reps = e.repRange.trim();
    final weight =
        e.suggestedWeightKg <= 0 ? 'BW' : formatWeight(e.suggestedWeightKg, decimals: 1);
    final detail = [
      if (e.sets > 0) '${e.sets}×${reps.isEmpty ? '—' : reps}',
      if (e.restSeconds > 0) '${e.restSeconds}s rest',
      weight,
    ].join(' · ');
    final why = e.whyThisExercise?.trim();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: ZveltTokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.name,
                  style: ZType.bodyM
                      .copyWith(fontWeight: FontWeight.w600, height: 1.35),
                ),
              ),
              if (e.weightSource == 'history')
                Text(
                  'from your history',
                  style: ZType.bodyS
                      .copyWith(color: ZveltTokens.text3, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(detail,
              style: ZType.bodyS.copyWith(fontWeight: FontWeight.w500)),
          if (why != null && why.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              why,
              style: ZType.bodyS.copyWith(
                fontStyle: FontStyle.italic,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _warningsCallout() {
    return Container(
      margin: const EdgeInsets.only(top: ZveltTokens.s3),
      padding: const EdgeInsets.all(ZveltTokens.s3),
      decoration: BoxDecoration(
        color: ZveltTokens.warn.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(AppIcons.exclamation, size: 18, color: ZveltTokens.warn),
          const SizedBox(width: ZveltTokens.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final w in _suggestion.warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(w,
                        style: ZType.bodyS
                            .copyWith(color: ZveltTokens.text, height: 1.45)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.s5, ZveltTokens.s3, ZveltTokens.s5, ZveltTokens.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_regenerateError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: ZveltTokens.s2),
              child: Text(
                _regenerateError!,
                textAlign: TextAlign.center,
                style: ZType.bodyS.copyWith(color: ZveltTokens.error),
              ),
            ),
          Semantics(
            button: true,
            label: 'Start this workout',
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: ZveltTokens.glowBrand,
              ),
              child: Material(
                color: ZveltTokens.brand,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _regenerating
                      ? null
                      : () => Navigator.of(context).pop(_suggestion),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    alignment: Alignment.center,
                    child: Text(
                      'Start this workout',
                      style: ZType.bodyM.copyWith(
                        color: ZveltTokens.onBrand,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.regenerate != null) ...[
            const SizedBox(height: ZveltTokens.s1),
            Semantics(
              button: true,
              label: 'Regenerate suggestion',
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _regenerating ? null : _regenerate,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding:
                        const EdgeInsets.symmetric(horizontal: ZveltTokens.s4),
                    alignment: Alignment.center,
                    child: Text(
                      _regenerating ? 'Regenerating…' : 'Regenerate',
                      style: ZType.bodyS.copyWith(
                        color: ZveltTokens.text2,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
