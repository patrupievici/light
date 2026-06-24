import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/workout_result.dart';
import '../../theme/zvelt_tokens.dart';

class PaceChart extends StatelessWidget {
  final List<SplitData> splits;
  final ActivityType activityType;

  const PaceChart({
    super.key,
    required this.splits,
    required this.activityType,
  });

  bool get _isPace => activityType.hasPace;

  @override
  Widget build(BuildContext context) {
    if (splits.isEmpty) return const SizedBox.shrink();

    final values = splits.map((s) {
      if (_isPace) return s.paceSecsPerKm;
      // speed: km / (pace secs / 3600) → 3600 / pace
      return s.paceSecsPerKm > 0 ? 3600.0 / s.paceSecsPerKm : 0.0;
    }).toList();

    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final padding = (maxVal - minVal) * 0.2;
    final chartMin = (minVal - padding).clamp(0, double.infinity).toDouble();
    final chartMax = maxVal + padding;

    final fastestIdx = _isPace
        ? values.indexOf(values.reduce((a, b) => a < b ? a : b))
        : values.indexOf(values.reduce((a, b) => a > b ? a : b));

    return Semantics(
      label: 'Pace per kilometer, fastest split highlighted',
      child: SizedBox(
        height: 160,
        child: BarChart(
          BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: chartMin,
          maxY: chartMax,
          barGroups: [
            for (var i = 0; i < splits.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    fromY: chartMin,
                    color: i == fastestIdx
                        ? ZveltTokens.brand
                        : ZveltTokens.brand.withValues(alpha: 0.45),
                    width: splits.length <= 6 ? 20 : 12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ],
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _isPace ? 30 : 5,
            getDrawingHorizontalLine: (_) => FlLine(
              color: ZveltTokens.hairline,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= splits.length) return const SizedBox.shrink();
                  return Text(
                    '${splits[i].km}',
                    style: ZType.monoXS.copyWith(color: ZveltTokens.text2),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => ZveltTokens.surface2,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final val = values[groupIndex];
                String label;
                if (_isPace) {
                  final m = (val ~/ 60);
                  final s = (val % 60).toInt();
                  label = '$m:${s.toString().padLeft(2, '0')}/km';
                } else {
                  label = '${val.toStringAsFixed(1)} km/h';
                }
                return BarTooltipItem(
                  'km ${splits[groupIndex].km}\n$label',
                  TextStyle(
                    color: ZveltTokens.text,
                    fontSize: 12,
                    fontFamily: ZveltTokens.fontPrimary,
                  ),
                );
              },
            ),
          ),
          ),
        ),
      ),
    );
  }
}

// Line-chart variant used when splits aren't available — plots raw speed over time
class SpeedLineChart extends StatelessWidget {
  final List<double> speedSamples;
  final Color color;

  const SpeedLineChart({
    super.key,
    required this.speedSamples,
    this.color = ZveltTokens.brand,
  });

  @override
  Widget build(BuildContext context) {
    if (speedSamples.isEmpty) return const SizedBox.shrink();

    final spots = [
      for (var i = 0; i < speedSamples.length; i++)
        FlSpot(i.toDouble(), speedSamples[i]),
    ];

    final maxY = speedSamples.reduce((a, b) => a > b ? a : b) * 1.2;

    return SizedBox(
      height: 120,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: ZveltTokens.hairline,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 2,
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
        ),
      ),
    );
  }
}
