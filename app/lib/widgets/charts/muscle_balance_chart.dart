import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../theme/zvelt_tokens.dart';
import '../../services/stats_charts_service.dart';

/// Muscle Balance Chart - horizontal bars showing training distribution
class MuscleBalanceChart extends StatefulWidget {
  const MuscleBalanceChart({super.key});

  @override
  State<MuscleBalanceChart> createState() => _MuscleBalanceChartState();
}

class _MuscleBalanceChartState extends State<MuscleBalanceChart> {
  final _stats = StatsChartsService();
  bool _loading = true;

  /// Piață implicită — nu lasă map gol după erori (reduce pe [] → Bad state: No element).
  static Map<String, double> _zeroedCategories() => {
        'Push': 0.0,
        'Pull': 0.0,
        'Legs': 0.0,
        'Core': 0.0,
      };

  Map<String, double> _muscleBalance = _zeroedCategories();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final topExercises = await _stats.getTopExercises(days: 30, limit: 20);
      
      // Categorize exercises by muscle group
      final categories = {
        'Push': 0.0,
        'Pull': 0.0,
        'Legs': 0.0,
        'Core': 0.0,
      };

      for (final exercise in topExercises) {
        final name = exercise.name.toLowerCase();
        final volume = exercise.volumeKg;

        // Check LEG-specific patterns FIRST: 'leg press' contains 'press', so
        // testing Push first mislabeled it as a push movement.
        if (name.contains('squat') ||
            name.contains('lunge') ||
            name.contains('leg') || // leg press / leg curl / leg extension
            name.contains('calf') ||
            name.contains('hip thrust') ||
            name.contains('glute') ||
            name.contains('hamstring')) {
          categories['Legs'] = categories['Legs']! + volume;
        } else if (name.contains('bench') ||
            name.contains('press') || // overhead/db/incline press
            name.contains('fly') ||
            name.contains('pushup') ||
            name.contains('dip') ||
            name.contains('lateral') ||
            name.contains('tricep')) {
          categories['Push'] = categories['Push']! + volume;
        } else if (name.contains('row') ||
            name.contains('pull') ||
            name.contains('chin') ||
            name.contains('curl') ||
            name.contains('rear') ||
            name.contains('deadlift')) {
          categories['Pull'] = categories['Pull']! + volume;
        } else if (name.contains('plank') ||
            name.contains('crunch') ||
            name.contains('ab') ||
            name.contains('core') ||
            name.contains('sit')) {
          categories['Core'] = categories['Core']! + volume;
        }
      }

      if (mounted) {
        setState(() {
          _muscleBalance = categories;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _muscleBalance = _zeroedCategories();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildLoading();
    }

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

  Widget _buildChart() {
    final values = _muscleBalance.values.toList();
    if (values.isEmpty) return _buildEmpty();
    final maxValue = values.reduce((a, b) => a > b ? a : b);

    if (maxValue == 0) {
      return _buildEmpty();
    }

    final labels = ['Push', 'Pull', 'Legs', 'Core'];
    // Single orange signal across all four bars (design-system conformance).
    const colors = [
      ZveltTokens.brand,
      ZveltTokens.brand,
      ZveltTokens.brand,
      ZveltTokens.brand,
    ];

    // Pre-computed percentages for the Semantics label.
    final pushPct = ((_muscleBalance['Push'] ?? 0) / maxValue * 100).toInt();
    final pullPct = ((_muscleBalance['Pull'] ?? 0) / maxValue * 100).toInt();
    final legsPct = ((_muscleBalance['Legs'] ?? 0) / maxValue * 100).toInt();
    final corePct = ((_muscleBalance['Core'] ?? 0) / maxValue * 100).toInt();

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
            children: [
              Icon(AppIcons.chart_line_up, color: ZveltTokens.text2),
              const SizedBox(width: ZveltTokens.s2),
              Text(
                'Muscle Group Balance',
                style: ZType.h4.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: ZveltTokens.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            'Last 30 days volume distribution',
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
          ),
          const SizedBox(height: ZveltTokens.s5),
          
          // Horizontal bars
          Semantics(
            label:
                'Muscle balance: $pushPct% push, $pullPct% pull, $legsPct% legs, $corePct% core',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(4, (index) {
                final label = labels[index];
                final value = _muscleBalance[label] ?? 0;
                final percentage = (value / maxValue * 100).toInt();
                final color = colors[index];

                return Padding(
                  padding: const EdgeInsets.only(bottom: ZveltTokens.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            label,
                            style: ZType.bodyS.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ZveltTokens.text,
                            ),
                          ),
                          Text(
                            '$percentage%',
                            style: ZType.num_.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: ZveltTokens.text2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: ZveltTokens.s2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: ZveltTokens.surface3,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                          minHeight: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          
          const SizedBox(height: ZveltTokens.s2),

          // Balance summary
          _buildBalanceSummary(),
        ],
      ),
    );
  }

  Widget _buildBalanceSummary() {
    final nonZero = _muscleBalance.values.where((v) => v > 0).toList();
    
    if (nonZero.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(ZveltTokens.s3),
        decoration: BoxDecoration(
          color: ZveltTokens.warn.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
        ),
        child: Text(
          'Log some workouts to see your muscle balance',
          textAlign: TextAlign.center,
          style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
        ),
      );
    }

    // Check if at least 3 groups are trained
    final isBalanced = nonZero.length >= 3;

    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s3),
      decoration: BoxDecoration(
        color: isBalanced
            ? ZveltTokens.success.withValues(alpha: 0.1)
            : ZveltTokens.warn.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
      ),
      child: Text(
        isBalanced
            ? '✓ Well-balanced training! Keep it up!'
            : '⚠️ Try to train all muscle groups for optimal development',
        textAlign: TextAlign.center,
        style: ZType.bodyS.copyWith(
          color: isBalanced ? ZveltTokens.success : ZveltTokens.warn,
          fontWeight: FontWeight.w600,
        ),
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
          const SizedBox(height: ZveltTokens.s3),
          Text(
            'No training data yet',
            style: ZType.h4.copyWith(
              color: ZveltTokens.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            'Complete workouts to see your muscle balance',
            textAlign: TextAlign.center,
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
          ),
        ],
      ),
    );
  }
}
