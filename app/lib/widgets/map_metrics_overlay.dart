import 'package:flutter/material.dart';

import '../theme/zvelt_tokens.dart';

/// Metric cards overlaid on a live/recap GPS map — Razvan's run-detail design:
/// a vertical stack of small cards (Distance, Pace, Elev. Gain, Duration)
/// pinned to the left edge of the map. Shared by the live tracking screens.
class MapMetricsOverlay extends StatelessWidget {
  const MapMetricsOverlay({
    super.key,
    required this.distanceM,
    required this.elapsed,
    this.elevGainM,
  });

  final double distanceM;
  final Duration elapsed;

  /// Total elevation gain in meters; card is hidden when null.
  final double? elevGainM;

  @override
  Widget build(BuildContext context) {
    final km = distanceM / 1000;
    final distVal =
        distanceM >= 1000 ? km.toStringAsFixed(2) : distanceM.round().toString();
    final distUnit = distanceM >= 1000 ? 'km' : 'm';

    // Pace (min/km) only once we've actually moved a bit.
    String paceVal = '--';
    if (distanceM > 50 && elapsed.inSeconds > 0) {
      final secPerKm = elapsed.inSeconds / km;
      final m = secPerKm ~/ 60;
      final s = (secPerKm % 60).round();
      paceVal = '$m:${s.toString().padLeft(2, '0')}';
    }

    String two(int n) => n.toString().padLeft(2, '0');
    final durVal = elapsed.inHours > 0
        ? '${elapsed.inHours}:${two(elapsed.inMinutes % 60)}:${two(elapsed.inSeconds % 60)}'
        : '${elapsed.inMinutes}:${two(elapsed.inSeconds % 60)}';

    final cards = <Widget>[
      _MapMetricCard(label: 'Distance', value: distVal, unit: distUnit),
      _MapMetricCard(
          label: 'Pace', value: paceVal, unit: paceVal == '--' ? null : '/km'),
      if (elevGainM != null)
        _MapMetricCard(
            label: 'Elev. Gain', value: elevGainM!.round().toString(), unit: 'm'),
      _MapMetricCard(label: 'Duration', value: durVal),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: ZveltTokens.s2),
          cards[i],
        ],
      ],
    );
  }
}

class _MapMetricCard extends StatelessWidget {
  const _MapMetricCard({required this.label, required this.value, this.unit});
  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 86,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: ZveltTokens.s2),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: ZveltTokens.shadowFloat,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: ZType.eyebrow.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: ZveltTokens.text3,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.num_.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ZveltTokens.text,
                  ),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(
                  unit!,
                  style: ZType.num_.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: ZveltTokens.text2,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
