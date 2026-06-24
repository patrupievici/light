import 'package:flutter/material.dart';

import '../theme/zvelt_tokens.dart';

/// A barbell plate-math helper (brief §8 "Plate calculator"). Given a target
/// total weight and a bar weight, it computes which plates to load **per side**
/// using a greedy largest-first fill, and surfaces any remainder that can't be
/// matched with standard plates.
///
/// All math is in **kilograms** — Zvelt stores weight canonically in kg. The
/// standard kg plate set is used; bar weight is user-selectable.
class PlateMath {
  PlateMath._();

  /// Standard kg plates, largest first.
  static const List<double> kgPlates = [25, 20, 15, 10, 5, 2.5, 1.25];

  /// Common bar weights (kg). 20 = Olympic, 15 = women's, 10 = training, 0 = none.
  static const List<double> kgBars = [20, 15, 10, 0];

  /// Returns the per-side plate breakdown for [targetKg] on a [barKg] bar.
  /// `plates` is largest-first with one entry per loaded plate (so duplicates
  /// repeat); `remainderKg` is the part of one side that couldn't be filled.
  static ({List<double> plates, double remainderKg}) loadout(
    double targetKg,
    double barKg,
  ) {
    var perSide = (targetKg - barKg) / 2;
    if (perSide <= 0) return (plates: const <double>[], remainderKg: 0);
    final picked = <double>[];
    for (final p in kgPlates) {
      while (perSide + 1e-6 >= p) {
        picked.add(p);
        perSide -= p;
      }
    }
    // Round away floating dust below the smallest plate.
    final remainder = perSide < 0.01 ? 0.0 : perSide;
    return (plates: picked, remainderKg: remainder);
  }
}

/// Opens the plate calculator as a bottom sheet, seeded with [weightKg].
Future<void> showPlateCalculator(BuildContext context, double weightKg) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PlateCalculatorSheet(initialWeight: weightKg),
  );
}

class _PlateCalculatorSheet extends StatefulWidget {
  const _PlateCalculatorSheet({required this.initialWeight});

  final double initialWeight;

  @override
  State<_PlateCalculatorSheet> createState() => _PlateCalculatorSheetState();
}

class _PlateCalculatorSheetState extends State<_PlateCalculatorSheet> {
  late double _target = widget.initialWeight.clamp(0, 500);
  double _bar = 20;

  @override
  Widget build(BuildContext context) {
    final result = PlateMath.loadout(_target, _bar);
    final plates = result.plates;

    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      padding: EdgeInsets.fromLTRB(
        ZveltTokens.s5,
        ZveltTokens.s4,
        ZveltTokens.s5,
        MediaQuery.paddingOf(context).bottom + ZveltTokens.s5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ZveltTokens.surface3,
                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
              ),
            ),
          ),
          const SizedBox(height: ZveltTokens.s4),
          Text('Plate calculator', style: ZType.h3),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            'Plates to load on each side',
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
          ),
          const SizedBox(height: ZveltTokens.s5),

          // ── Target weight stepper ───────────────────────────────────────
          Row(
            children: [
              Text('Target', style: ZType.bodyM),
              const Spacer(),
              _StepButton(
                icon: Icons.remove,
                onTap: () => setState(
                    () => _target = (_target - 2.5).clamp(0, 500)),
              ),
              const SizedBox(width: ZveltTokens.s3),
              SizedBox(
                width: 86,
                child: Text(
                  '${_fmt(_target)} kg',
                  textAlign: TextAlign.center,
                  style: ZType.num_.copyWith(fontSize: 22),
                ),
              ),
              const SizedBox(width: ZveltTokens.s3),
              _StepButton(
                icon: Icons.add,
                onTap: () => setState(
                    () => _target = (_target + 2.5).clamp(0, 500)),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s4),

          // ── Bar selector ────────────────────────────────────────────────
          Text('Bar', style: ZType.eyebrow),
          const SizedBox(height: ZveltTokens.s2),
          Wrap(
            spacing: ZveltTokens.s2,
            children: [
              for (final b in PlateMath.kgBars)
                ChoiceChip(
                  label: Text(b == 0 ? 'None' : '${_fmt(b)} kg'),
                  selected: _bar == b,
                  onSelected: (_) => setState(() => _bar = b),
                  selectedColor: ZveltTokens.brandTint,
                  backgroundColor: ZveltTokens.bg2,
                  labelStyle: ZType.bodyS.copyWith(
                    color: _bar == b ? ZveltTokens.brandDeep : ZveltTokens.text2,
                    fontWeight: _bar == b ? FontWeight.w600 : FontWeight.w400,
                  ),
                  side: BorderSide.none,
                ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s5),

          // ── Result ──────────────────────────────────────────────────────
          if (plates.isEmpty)
            Text(
              _target <= _bar
                  ? 'Bar only — no plates needed.'
                  : 'Add weight above the bar to see plates.',
              style: ZType.bodyM.copyWith(color: ZveltTokens.text2),
            )
          else
            Wrap(
              spacing: ZveltTokens.s2,
              runSpacing: ZveltTokens.s2,
              children: [
                for (final entry in _grouped(plates).entries)
                  _PlateChip(weight: entry.key, count: entry.value),
              ],
            ),
          if (result.remainderKg > 0) ...[
            const SizedBox(height: ZveltTokens.s3),
            Text(
              '${_fmt(result.remainderKg)} kg/side unmatched — closest you can load is ${_fmt(_target - result.remainderKg * 2)} kg.',
              style: ZType.bodyS.copyWith(color: ZveltTokens.warn),
            ),
          ],
          const SizedBox(height: ZveltTokens.s5),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ZveltTokens.brand,
                foregroundColor: ZveltTokens.onBrand,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

  /// Largest-first plate list → {plate: count}, preserving descending order.
  Map<double, int> _grouped(List<double> plates) {
    final map = <double, int>{};
    for (final p in plates) {
      map[p] = (map[p] ?? 0) + 1;
    }
    return map;
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZveltTokens.bg2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: ZveltTokens.text),
        ),
      ),
    );
  }
}

class _PlateChip extends StatelessWidget {
  const _PlateChip({required this.weight, required this.count});

  final double weight;
  final int count;

  @override
  Widget build(BuildContext context) {
    final label = weight == weight.roundToDouble()
        ? weight.toStringAsFixed(0)
        : weight.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
      decoration: BoxDecoration(
        color: ZveltTokens.brandTint,
        borderRadius: BorderRadius.circular(ZveltTokens.rMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count', style: ZType.num_.copyWith(color: ZveltTokens.brandDeep)),
          Text('  ×  ', style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
          Text('$label kg',
              style: ZType.bodyM.copyWith(
                  color: ZveltTokens.text, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
