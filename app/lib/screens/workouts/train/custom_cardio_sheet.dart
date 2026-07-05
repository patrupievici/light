import 'package:flutter/material.dart';

import '../../../models/activity_kind.dart';
import '../../../theme/zvelt_tokens.dart';

/// Result of [showCustomCardioSheet]: the chosen activity + its duration.
class CustomCardioResult {
  const CustomCardioResult({required this.kind, required this.durationMin});

  final ActivityKind kind;
  final int durationMin;
}

/// Shows the "Log custom cardio" modal bottom sheet.
///
/// Returns the chosen [CustomCardioResult], or `null` if the sheet was
/// dismissed without logging.
Future<CustomCardioResult?> showCustomCardioSheet(BuildContext context) {
  return showModalBottomSheet<CustomCardioResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CustomCardioSheet(),
  );
}

/// The selectable activity kinds, in display order, with their chip labels.
const List<(ActivityKind, String)> _kindChoices = [
  (ActivityKind.walk, 'Walk'),
  (ActivityKind.run, 'Run'),
  (ActivityKind.cycle, 'Bike'),
  (ActivityKind.swim, 'Swim'),
  (ActivityKind.other, 'Other'),
];

const List<int> _durationChoices = [10, 20, 30, 45, 60, 90];

class _CustomCardioSheet extends StatefulWidget {
  const _CustomCardioSheet();

  @override
  State<_CustomCardioSheet> createState() => _CustomCardioSheetState();
}

class _CustomCardioSheetState extends State<_CustomCardioSheet> {
  ActivityKind _selectedKind = ActivityKind.walk;
  int _selectedDuration = 30;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, viewInsets + 24),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grabber pill.
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: ZveltTokens.surface3,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Text(
            'Log custom cardio',
            style: ZType.h3.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: ZveltTokens.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Any activity — pick what and how long.',
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
          ),
          const _SectionLabel('ACTIVITY'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (kind, fallback) in _kindChoices)
                _PillChip(
                  label: _chipLabel(kind, fallback),
                  selected: _selectedKind == kind,
                  onTap: () => setState(() => _selectedKind = kind),
                ),
            ],
          ),
          const _SectionLabel('DURATION'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final minutes in _durationChoices)
                _PillChip(
                  label: '$minutes min',
                  selected: _selectedDuration == minutes,
                  onTap: () => setState(() => _selectedDuration = minutes),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _LogButton(
            onTap: () => Navigator.pop(
              context,
              CustomCardioResult(
                kind: _selectedKind,
                durationMin: _selectedDuration,
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// Prefer the short literal label from the design; fall back to the model's
  /// richer `.label` if the choice list ever omits one.
  String _chipLabel(ActivityKind kind, String fallback) {
    return fallback.isNotEmpty ? fallback : kind.label;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: ZType.eyebrow.copyWith(color: ZveltTokens.text2),
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? ZveltTokens.brand : ZveltTokens.bg2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: ZType.bodyM.copyWith(
              color: selected ? ZveltTokens.onBrand : ZveltTokens.text2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _LogButton extends StatelessWidget {
  const _LogButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZveltTokens.brand,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          alignment: Alignment.center,
          child: Text(
            'Log activity',
            style: ZType.bodyM.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: ZveltTokens.onBrand,
            ),
          ),
        ),
      ),
    );
  }
}
