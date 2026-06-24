import 'package:fl_chart/fl_chart.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../services/rest_interval_store.dart';
import '../../theme/zvelt_tokens.dart';

/// Rest Time Trend — average wall-clock rest between sets, one bar per
/// recent workout session. Data source is **client-only**: it comes from
/// [RestIntervalStore] which records every set-to-set gap on-device. The
/// backend has no rest-tracking endpoint yet (CLAUDE.md P0.3); when it
/// ships the local store can be swapped for the server aggregate.
class RestTimeTrendChart extends StatefulWidget {
  const RestTimeTrendChart({super.key});

  @override
  State<RestTimeTrendChart> createState() => _RestTimeTrendChartState();
}

class _RestTimeTrendChartState extends State<RestTimeTrendChart> {
  bool _loading = true;
  List<RestSessionPoint> _data = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pts = await RestIntervalStore.instance.recentSessionAverages(limit: 20);
    if (!mounted) return;
    setState(() {
      _data = pts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();
    if (_data.isEmpty) return _buildEmpty();
    return _buildChart();
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
          Icon(AppIcons.stopwatch, size: 48, color: ZveltTokens.text2),
          const SizedBox(height: ZveltTokens.s3),
          Text(
            'Rest Time Trend',
            style: ZType.h4.copyWith(
              color: ZveltTokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Log your first workouts and your average rest between sets will appear here.',
            textAlign: TextAlign.center,
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    const accent = ZveltTokens.brand;

    final avgs = _data.map((p) => p.avgRestSeconds).toList();
    final firstRest = avgs.first;
    final lastRest = avgs.last;
    final overall = avgs.reduce((a, b) => a + b) / avgs.length;

    // Visual y-axis bounds — clamp to a sensible window so a single outlier
    // doesn't flatten the chart.
    final rawMin = avgs.reduce((a, b) => a < b ? a : b);
    final rawMax = avgs.reduce((a, b) => a > b ? a : b);
    final span = (rawMax - rawMin).abs();
    final pad = span < 30 ? 15.0 : span * 0.15;
    final minY = (rawMin - pad).clamp(0.0, double.infinity);
    final maxY = rawMax + pad;

    final spots = <FlSpot>[
      for (var i = 0; i < _data.length; i++) FlSpot(i.toDouble(), _data[i].avgRestSeconds),
    ];

    // Delta badge: only meaningful when there are >=2 sessions.
    final hasDelta = _data.length >= 2 && firstRest > 0;
    final deltaPct = hasDelta ? ((firstRest - lastRest) / firstRest * 100) : 0.0;
    final improved = deltaPct >= 0;
    final badgeColor = improved ? ZveltTokens.success : ZveltTokens.warn;
    final badgeText = hasDelta
        ? '${improved ? '↓' : '↑'} ${deltaPct.abs().toStringAsFixed(1)}%'
        : '—';

    // Bottom-label interval: keep at most ~5 labels.
    final labelStep = (_data.length / 5).ceil().clamp(1, 999);

    return Semantics(
      label: 'Rest time trend, average ${overall.round()} seconds, $badgeText',
      child: Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: const BorderRadius.all(Radius.circular(ZveltTokens.rLg)),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(AppIcons.stopwatch, color: ZveltTokens.text2),
                  const SizedBox(width: ZveltTokens.s2),
                  Text(
                    'Rest Time Trend',
                    style: ZType.h4.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ZveltTokens.text,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: ZveltTokens.s1),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                ),
                child: Text(
                  badgeText,
                  style: ZType.bodyS.copyWith(
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            'Avg rest between sets · last ${_data.length} session${_data.length == 1 ? '' : 's'}',
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
          ),
          const SizedBox(height: ZveltTokens.s4),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: ZveltTokens.hairline,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}s',
                        style: TextStyle(
                          fontSize: 11,
                          color: ZveltTokens.text2,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: labelStep.toDouble(),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _data.length) {
                          return const SizedBox.shrink();
                        }
                        final d = _data[idx].endedAt.toLocal();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${d.day}/${d.month}',
                            style: TextStyle(
                              fontSize: 11,
                              color: ZveltTokens.text2,
                            ),
                          ),
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
                    curveSmoothness: 0.3,
                    color: accent,
                    barWidth: 2.2,
                    dotData: FlDotData(
                      show: false,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 3,
                          color: accent,
                          strokeWidth: 2,
                          strokeColor: ZveltTokens.surface,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.18),
                          accent.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                minY: minY.toDouble(),
                maxY: maxY,
              ),
            ),
          ),
          const SizedBox(height: ZveltTokens.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'First',
                '${firstRest.round()}s',
                AppIcons.arrow_small_left,
                ZveltTokens.text2,
              ),
              _buildStatItem(
                'Average',
                '${overall.round()}s',
                AppIcons.chart_histogram,
                ZveltTokens.text,
              ),
              _buildStatItem(
                'Latest',
                '${lastRest.round()}s',
                improved ? AppIcons.arrow_trend_down : AppIcons.arrow_trend_up,
                improved ? ZveltTokens.success : ZveltTokens.warn,
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: ZveltTokens.s1),
        Text(
          value,
          style: ZType.num_.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: ZType.bodyS.copyWith(
            color: ZveltTokens.text2,
          ),
        ),
      ],
    );
  }
}
