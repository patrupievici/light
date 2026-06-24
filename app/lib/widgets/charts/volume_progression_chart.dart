import 'package:fl_chart/fl_chart.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';
import '../../services/stats_charts_service.dart';

/// Grafic progresie volum total (kg lifted per session)
class VolumeProgressionChart extends StatefulWidget {
  const VolumeProgressionChart({super.key});

  @override
  State<VolumeProgressionChart> createState() => _VolumeProgressionChartState();
}

class _VolumeProgressionChartState extends State<VolumeProgressionChart> {
  final _stats = StatsChartsService();
  bool _loading = true;
  List<DailyTrainingPoint> _data = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _stats.getDailyTraining(days: 60);
      if (mounted) {
        setState(() {
          _data = data.where((d) => d.sessions > 0).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildLoading();
    }

    if (_data.isEmpty) {
      return _buildEmpty();
    }

    final spots = _data.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.volumeKg);
    }).toList();

    if (spots.length < 2) {
      return _buildEmpty();
    }

    return _buildChart(spots);
  }

  Widget _buildLoading() {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s5),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: const Center(
        child: CircularProgressIndicator(color: ZveltTokens.brand),
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s6),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        children: [
          Icon(AppIcons.gym, size: 48, color: ZveltTokens.text2),
          const SizedBox(height: 12),
          Text(
            'No volume data yet',
            style: TextStyle(
              color: ZveltTokens.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Complete workouts to see your volume progression',
            textAlign: TextAlign.center,
            style: TextStyle(color: ZveltTokens.text2, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<FlSpot> spots) {
    final maxVolume = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final minVolume = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final growth = ((spots.last.y - spots.first.y) / spots.first.y * 100)
        .toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Volume Progression',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ZveltTokens.text,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: double.parse(growth) >= 0
                      ? ZveltTokens.success.withValues(alpha: 0.2)
                      : ZveltTokens.error.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${double.parse(growth) >= 0 ? '↑' : '↓'} ${double.parse(growth).abs().toStringAsFixed(1)}%',
                  style: ZType.num_.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: double.parse(growth) >= 0
                        ? ZveltTokens.success
                        : ZveltTokens.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Total kg lifted per session',
            style: TextStyle(fontSize: 12, color: ZveltTokens.text2),
          ),
          const SizedBox(height: 16),
          Semantics(
            label:
                'Volume progression, $growth% over the last ${_data.length} sessions',
            child: SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxVolume / 3,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: ZveltTokens.hairline,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 60,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${(value / 1000).toStringAsFixed(1)}k',
                            style: ZType.num_.copyWith(
                              fontSize: 11,
                              color: ZveltTokens.text2,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: (spots.length / 4).ceil().toDouble(),
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= _data.length) return const SizedBox.shrink();
                          final date = DateTime.parse(_data[idx].day);
                          return Text(
                            '${date.day}/${date.month}',
                            style: TextStyle(fontSize: 11, color: ZveltTokens.text2),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.2,
                      color: ZveltTokens.brand,
                      barWidth: 2.2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            ZveltTokens.brand.withValues(alpha: 0.18),
                            ZveltTokens.brand.withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                  minY: minVolume * 0.9,
                  maxY: maxVolume * 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
