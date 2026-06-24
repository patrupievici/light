import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme/zvelt_tokens.dart';

class ElevationChart extends StatelessWidget {
  /// Elevation samples in metres, evenly spaced along the route.
  final List<double> elevationM;
  final Color color;

  const ElevationChart({
    super.key,
    required this.elevationM,
    this.color = ZveltTokens.brand,
  });

  @override
  Widget build(BuildContext context) {
    if (elevationM.isEmpty) return const SizedBox.shrink();

    final samples = _downsample(elevationM, 120);

    final minY = samples.reduce((a, b) => a < b ? a : b);
    final maxY = samples.reduce((a, b) => a > b ? a : b);
    final range = (maxY - minY).clamp(10.0, double.infinity);
    final paddedMin = minY - range * 0.1;
    final paddedMax = maxY + range * 0.15;

    final spots = [
      for (var i = 0; i < samples.length; i++) FlSpot(i.toDouble(), samples[i]),
    ];

    // Total positive elevation gain across the route (sum of upward deltas).
    var totalGainM = 0.0;
    for (var i = 1; i < samples.length; i++) {
      final delta = samples[i] - samples[i - 1];
      if (delta > 0) totalGainM += delta;
    }

    return Semantics(
      label: 'Elevation profile, ${totalGainM.toStringAsFixed(0)} m total gain',
      child: SizedBox(
        height: 140,
        child: LineChart(
          LineChartData(
            minY: paddedMin,
            maxY: paddedMax,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: range / 2,
              getDrawingHorizontalLine: (_) => FlLine(
                color: ZveltTokens.hairline,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (value, meta) {
                    if (value == meta.min || value == meta.max) {
                      return const SizedBox.shrink();
                    }
                    return Text(
                      '${value.toStringAsFixed(0)}m',
                      style: ZType.num_.copyWith(
                        color: ZveltTokens.text2,
                        fontSize: 11,
                      ),
                    );
                  },
                ),
              ),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.25,
                color: color,
                barWidth: 2.2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: 0.18),
                      color.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => ZveltTokens.surface2,
                getTooltipItems: (spots) => spots
                    .map((s) => LineTooltipItem(
                          '${s.y.toStringAsFixed(0)} m',
                          ZType.num_.copyWith(
                            color: ZveltTokens.text,
                            fontSize: 12,
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static List<double> _downsample(List<double> data, int maxPoints) {
    if (data.length <= maxPoints) return data;
    final step = data.length / maxPoints;
    return [
      for (var i = 0; i < maxPoints; i++)
        data[(i * step).round().clamp(0, data.length - 1)]
    ];
  }
}
