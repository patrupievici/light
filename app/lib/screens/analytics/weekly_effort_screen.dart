import 'package:fl_chart/fl_chart.dart';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../theme/zvelt_tokens.dart';
import '../../services/stats_charts_service.dart';

/// Volum săptămânal (kg×reps) — backend + fl_chart (todo Excel #46).
class WeeklyEffortScreen extends StatefulWidget {
  const WeeklyEffortScreen({super.key});

  @override
  State<WeeklyEffortScreen> createState() => _WeeklyEffortScreenState();
}

class _WeeklyEffortScreenState extends State<WeeklyEffortScreen> {
  final _svc = StatsChartsService();
  List<WeeklyEffortPoint> _points = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _svc.getWeeklyEffort(weeks: 12);
      if (!mounted) return;
      setState(() {
        _points = data.reversed.toList();
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
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        title: const Text('Weekly effort'),
        actions: [IconButton(icon: const Icon(AppIcons.refresh), tooltip: 'Refresh', onPressed: _loading ? null : _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(ZveltTokens.s6), child: Text(_error!, style: const TextStyle(color: ZveltTokens.error))))
              : _points.isEmpty
                  ? Center(child: Text('No workout volume yet', style: TextStyle(color: ZveltTokens.text2)))
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH, ZveltTokens.s6, ZveltTokens.screenPaddingH, ZveltTokens.s8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Volume (kg × reps) per week — WORK sets',
                            style: ZType.bodyS,
                          ),
                          const SizedBox(height: ZveltTokens.s5),
                          Expanded(
                            child: Semantics(
                              label:
                                  'Weekly training volume bar chart, ${_points.length} weeks of work-set tonnage',
                            child: BarChart(
                              BarChartData(
                                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: _maxVol() / 4, getDrawingHorizontalLine: (v) => FlLine(color: ZveltTokens.border, strokeWidth: 1)),
                                titlesData: FlTitlesData(
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 44,
                                      getTitlesWidget: (v, m) => Text(
                                        v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toInt().toString(),
                                        style: ZType.num_.copyWith(color: ZveltTokens.text2, fontSize: 11),
                                      ),
                                    ),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (i, m) {
                                        final idx = i.toInt();
                                        if (idx < 0 || idx >= _points.length) return const SizedBox.shrink();
                                        final w = _points[idx].weekStart;
                                        final short = w.length >= 10 ? w.substring(5) : w;
                                        return Padding(
                                          padding: const EdgeInsets.only(top: ZveltTokens.s2),
                                          child: Text(short, style: ZType.num_.copyWith(color: ZveltTokens.text2, fontSize: 11)),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                borderData: FlBorderData(show: false),
                                barGroups: [
                                  for (var i = 0; i < _points.length; i++)
                                    BarChartGroupData(
                                      x: i,
                                      barRods: [
                                        BarChartRodData(
                                          toY: _points[i].volumeKg,
                                          width: 14,
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rSm)),
                                          color: ZveltTokens.brand,
                                        ),
                                      ],
                                    ),
                                ],
                                maxY: _maxVol() * 1.15,
                              ),
                            ),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }

  double _maxVol() {
    if (_points.isEmpty) return 1000;
    return _points.map((p) => p.volumeKg).reduce((a, b) => a > b ? a : b).clamp(100, double.infinity);
  }
}
