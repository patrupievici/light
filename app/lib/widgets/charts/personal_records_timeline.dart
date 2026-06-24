import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../theme/zvelt_tokens.dart';
import '../../services/workout_service.dart';

/// Personal Records Timeline — milestone-uri e1RM din istoricul contului (`GET /v1/ranks/me/history`).
class PersonalRecordsTimeline extends StatefulWidget {
  const PersonalRecordsTimeline({super.key});

  @override
  State<PersonalRecordsTimeline> createState() => _PersonalRecordsTimelineState();
}

class _PersonalRecordsTimelineState extends State<PersonalRecordsTimeline> {
  final _workouts = WorkoutService();

  bool _loading = true;
  String? _error;
  List<PersonalRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final progressions = await _workouts.getMyProgressionHistory();
      final prs = _prMilestonesFromProgressions(progressions);
      if (mounted) {
        setState(() {
          _records = prs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _records = [];
          _loading = false;
        });
      }
    }
  }

  /// Moment în care e1RM depășește maximul anterior pentru acel exercițiu (din workouts loggate).
  static List<PersonalRecord> _prMilestonesFromProgressions(List<ExerciseProgressionDto> list) {
    final rows = <PersonalRecord>[];
    for (final ex in list) {
      final pts = List<ProgressionPointDto>.from(ex.dataPoints)
        ..sort((a, b) => a.date.compareTo(b.date));
      var peak = -1.0;
      for (final p in pts) {
        if (p.e1rmKg <= peak + 1e-6) continue;
        peak = p.e1rmKg;
        DateTime d;
        try {
          final ds = p.date.length >= 10 ? p.date.substring(0, 10) : p.date;
          d = DateTime.parse(ds);
        } catch (e) {
          debugPrint('[PRTimeline] date parse best-effort skip: $e');
          continue;
        }
        final wStr =
            (p.weightKg % 1).abs() < 1e-6 ? p.weightKg.round().toString() : p.weightKg.toString();
        rows.add(PersonalRecord(
          exerciseName: ex.exerciseName,
          value: '$wStr kg × ${p.reps} reps',
          date: d,
        ));
      }
    }
    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows.take(25).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildLoading();
    }

    if (_error != null) {
      return _buildError();
    }

    if (_records.isEmpty) {
      return _buildEmpty();
    }

    return _buildTimeline();
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

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s5),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3),
          child: Text(
            _error ?? 'Failed to load PRs',
            textAlign: TextAlign.center,
            style: ZType.bodyS.copyWith(color: ZveltTokens.error),
          ),
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
          Icon(AppIcons.trophy, size: 48, color: ZveltTokens.brand.withValues(alpha: 0.5)),
          const SizedBox(height: ZveltTokens.s3),
          Text(
            'No personal records yet',
            style: ZType.h4.copyWith(
              color: ZveltTokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            'Complete ranked strength workouts — milestones show when your best set e1RM improves.',
            textAlign: TextAlign.center,
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    // Sort by date descending
    final sorted = List.from(_records)..sort((a, b) => b.date.compareTo(a.date));
    
    // Take last 20 PRs
    final recentPRs = sorted.take(20).toList().reversed.toList();

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
              const Icon(AppIcons.trophy, color: ZveltTokens.brand),
              const SizedBox(width: ZveltTokens.s2),
              Text(
                'Personal Records',
                style: ZType.h4.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ZveltTokens.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s1),
          Text(
            '${_records.length} PR milestones (e1RM improved)',
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
          ),
          const SizedBox(height: ZveltTokens.s4),
          
          // Timeline list
          SizedBox(
            height: 300,
            child: Semantics(
              label: '${_records.length} personal record milestones',
              child: ListView.builder(
              itemCount: recentPRs.length,
              itemBuilder: (context, index) {
                final pr = recentPRs[index];
                final isLast = index == recentPRs.length - 1;
                
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timeline line
                    Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: ZveltTokens.brand,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ZveltTokens.surface,
                              width: 2,
                            ),
                          ),
                        ),
                        if (!isLast)
                          Container(
                            width: 2,
                            height: 50,
                            color: ZveltTokens.brand.withValues(alpha: 0.3),
                          ),
                      ],
                    ),
                    const SizedBox(width: ZveltTokens.s3),

                    // PR details
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: ZveltTokens.s2),
                        padding: const EdgeInsets.all(ZveltTokens.s3),
                        decoration: BoxDecoration(
                          color: ZveltTokens.surface,
                          borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                          boxShadow: ZveltTokens.shadowCard,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    pr.exerciseName,
                                    style: ZType.bodyM.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: ZveltTokens.text,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatDate(pr.date),
                                  style: ZType.bodyS.copyWith(
                                    color: ZveltTokens.text2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: ZveltTokens.s1),
                            Text(
                              pr.value,
                              style: ZType.num_.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: ZveltTokens.brand,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class PersonalRecord {
  final String exerciseName;
  final String value;
  final DateTime date;

  PersonalRecord({
    required this.exerciseName,
    required this.value,
    required this.date,
  });
}
