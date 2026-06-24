import 'package:fl_chart/fl_chart.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../services/stats_charts_service.dart';
import '../../theme/zvelt_tokens.dart';

/// "Hero" chart on the Progress hub: year-long cumulative training volume.
///
/// Why this chart specifically:
///  - It NEVER goes down. Even on a bad week the curve creeps up because the
///    user added *something*. That's the psychological win that plain 1RM
///    charts can't deliver during plateaus.
///  - Single-glance value: one number ("12.4 t lifted this year") + one line
///    you can read in two seconds. No legend hunt, no axis interpretation.
///
/// Loads its own data so callers don't need to plumb a service in.
class CumulativeVolumeCard extends StatefulWidget {
  const CumulativeVolumeCard({super.key, this.year, this.service});

  /// Year to plot (UTC). Defaults to the server's current year.
  final int? year;

  /// Injected for tests; production callers leave it null.
  final StatsChartsService? service;

  @override
  State<CumulativeVolumeCard> createState() => _CumulativeVolumeCardState();
}

class _CumulativeVolumeCardState extends State<CumulativeVolumeCard> {
  late final StatsChartsService _service;
  CumulativeVolumeYear? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? StatsChartsService();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _service.getCumulativeVolume(year: widget.year);
      if (!mounted) return;
      setState(() {
        _data = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final tonnes = data == null ? '—' : (data.totalKg / 1000).toStringAsFixed(1);
    final activeDays = data?.activeDays ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4, ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(tonnes, activeDays),
          const SizedBox(height: ZveltTokens.s3),
          Semantics(
            label: 'Total volume lifted this year: $tonnes tonnes, $activeDays active days',
            child: SizedBox(height: 140, child: _buildChartArea()),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String tonnes, int activeDays) {
    final data = _data;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOTAL VOLUME ${data?.year ?? ''}'.trim(),
                style: ZType.eyebrow.copyWith(color: ZveltTokens.text2),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    tonnes,
                    style: ZType.num_.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: ZveltTokens.s1),
                  Text(
                    'tonnes lifted',
                    style: ZType.bodyS,
                  ),
                ],
              ),
              if (data != null && activeDays > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '$activeDays active day${activeDays == 1 ? '' : 's'}',
                    style: ZType.bodyS,
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          icon: Icon(AppIcons.refresh, color: ZveltTokens.text2, size: 20),
          onPressed: _loading ? null : _load,
        ),
      ],
    );
  }

  Widget _buildChartArea() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: ZveltTokens.brand, strokeWidth: 2),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: ZType.bodyS,
          textAlign: TextAlign.center,
        ),
      );
    }
    final pts = _data?.points ?? const <CumulativeVolumePoint>[];
    if (pts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'No lifts logged this year yet — your line starts the day you do.',
            textAlign: TextAlign.center,
            style: ZType.bodyS,
          ),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (var i = 0; i < pts.length; i++) {
      spots.add(FlSpot(i.toDouble(), pts[i].cumulativeVolumeKg / 1000));
    }
    final maxY = spots.last.y;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: spots.length > 1 ? spots.length - 1.0 : 1,
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.05,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => ZveltTokens.bg.withValues(alpha: 0.95),
            tooltipBorder: BorderSide(color: ZveltTokens.border, width: 1),
            getTooltipItems: (items) => items.map((it) {
              final idx = it.x.toInt().clamp(0, pts.length - 1);
              final day = pts[idx].day;
              final cumT = (pts[idx].cumulativeVolumeKg / 1000).toStringAsFixed(2);
              return LineTooltipItem(
                '$day\n$cumT t',
                ZType.monoXS.copyWith(color: ZveltTokens.text),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: ZveltTokens.brand,
            barWidth: 2.2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ZveltTokens.brand.withValues(alpha: 0.22),
                  ZveltTokens.brand.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
