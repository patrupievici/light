import 'package:flutter/material.dart';

import '../../models/activity_kind.dart';
import '../../services/activity_calendar_store.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';

/// CARDIO HISTORY — 1:1 with the ZVELT handoff prototype (`screenCardioHist`,
/// HTML 908–945): totals row, "Distance by session" bar chart (last 7),
/// ALL ACTIVITIES session rows. Data = the real manual-cardio store the Home
/// weekly card reads (`ActivityCalendarStore.loadManualSessions`).
class CardioHistoryScreen extends StatefulWidget {
  const CardioHistoryScreen({super.key});

  @override
  State<CardioHistoryScreen> createState() => _CardioHistoryScreenState();
}

class _CardioSession {
  const _CardioSession({
    required this.day,
    required this.kind,
    this.distanceKm,
    this.durationMin,
  });

  final DateTime day;
  final ActivityKind kind;
  final double? distanceKm;
  final int? durationMin;

  bool get isRide => kind == ActivityKind.cycle;

  String get typeLabel {
    switch (kind) {
      case ActivityKind.cycle:
        return 'Cycling';
      case ActivityKind.swim:
        return 'Swimming';
      case ActivityKind.walk:
        return 'Walking';
      case ActivityKind.run:
      case ActivityKind.gym:
      case ActivityKind.other:
        return 'Running';
    }
  }

  /// Same MET estimate the outdoor tracker shows (~70 kg default bodyweight).
  int get kcalEstimate {
    final mins = durationMin;
    if (mins == null || mins <= 0) return 0;
    final double met;
    switch (kind) {
      case ActivityKind.cycle:
        met = 6.0;
      case ActivityKind.swim:
        met = 7.0;
      case ActivityKind.walk:
        met = 4.0;
      case ActivityKind.run:
      case ActivityKind.gym:
      case ActivityKind.other:
        met = 9.0;
    }
    return (met * 70 * (mins / 60)).round();
  }

  /// Pace (`m:ss /km`) for foot sports, speed (`km/h`) for rides — the
  /// prototype's `metric` field.
  String get metric {
    final km = distanceKm ?? 0;
    final mins = durationMin ?? 0;
    if (km <= 0.02 || mins <= 0) return '--';
    if (isRide) {
      final kmh = km / (mins / 60);
      return '${kmh.toStringAsFixed(1)} km/h';
    }
    final paceMin = mins / km;
    var pm = paceMin.floor();
    var ps = ((paceMin - pm) * 60).round();
    if (ps == 60) {
      pm += 1;
      ps = 0;
    }
    return '$pm:${ps.toString().padLeft(2, '0')} /km';
  }

  String get durLabel {
    final mins = durationMin ?? 0;
    if (mins <= 0) return '--';
    final h = mins ~/ 60;
    final m = mins % 60;
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:00' : '$m:00';
  }

  String get dateLabel {
    final today = DateUtils.dateOnly(DateTime.now());
    final d = DateUtils.dateOnly(day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const mo = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${mo[d.month - 1]} ${d.day}';
  }
}

class _CardioHistoryScreenState extends State<CardioHistoryScreen> {
  bool _loading = true;
  List<_CardioSession> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final byDay = await ActivityCalendarStore().loadManualSessions();
      final all = <_CardioSession>[];
      byDay.forEach((dayKey, sessions) {
        final day = DateTime.tryParse(dayKey);
        if (day == null) return;
        for (final s in sessions) {
          all.add(_CardioSession(
            day: day,
            kind: s.kind,
            distanceKm: s.distanceKm,
            durationMin: s.durationMin,
          ));
        }
      });
      all.sort((a, b) => b.day.compareTo(a.day));
      if (!mounted) return;
      setState(() {
        _sessions = all;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  double get _totalKm =>
      _sessions.fold<double>(0, (a, s) => a + (s.distanceKm ?? 0));

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: Column(
        children: [
          // Header — back circle + title (HTML 910–913)
          Padding(
            padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 12),
            child: Row(
              children: [
                _CircleButton(
                  icon: AppIcons.angle_small_left,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 12),
                Text('Cardio history',
                    style: ZType.h2.copyWith(
                        fontSize: 22, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: ZveltTokens.brand))
                : _sessions.isEmpty
                    ? _emptyState()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                        children: [
                          _totalsRow(),
                          const SizedBox(height: 16),
                          _chartCard(),
                          const SizedBox(height: 18),
                          Text('ALL ACTIVITIES',
                              style: ZType.eyebrow.copyWith(fontSize: 11)),
                          const SizedBox(height: 11),
                          for (var i = 0; i < _sessions.length; i++) ...[
                            _sessionRow(_sessions[i]),
                            if (i < _sessions.length - 1)
                              const SizedBox(height: 9),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ZveltTokens.chip,
                shape: BoxShape.circle,
                border: Border.all(color: ZveltTokens.border),
              ),
              child:
                  Icon(AppIcons.running, size: 26, color: ZveltTokens.text2),
            ),
            const SizedBox(height: 14),
            Text('No cardio sessions yet',
                style: ZType.bodyL.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Run or Ride from Home — finished sessions land here.',
              textAlign: TextAlign.center,
              style: ZType.bodyS,
            ),
          ],
        ),
      ),
    );
  }

  // Totals row (HTML 915–918)
  Widget _totalsRow() {
    Widget tile(String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              gradient: ZveltTokens.surfaceGrad,
              borderRadius: BorderRadius.circular(ZveltTokens.rBox),
              border: Border.all(color: ZveltTokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: ZType.stat.copyWith(fontSize: 26)),
                const SizedBox(height: 2),
                Text(label,
                    style: ZType.bodyS.copyWith(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        tile(_totalKm.toStringAsFixed(1), 'Total km'),
        const SizedBox(width: 10),
        tile('${_sessions.length}', 'Activities'),
      ],
    );
  }

  // "Distance by session" chart — last 7 sessions, oldest → newest
  // (HTML 919–930; bar height = max(8, km/maxKm*96), ride bars gold).
  Widget _chartCard() {
    final chart = _sessions.take(7).toList().reversed.toList();
    final maxKm = chart.fold<double>(
        1, (a, s) => (s.distanceKm ?? 0) > a ? s.distanceKm! : a);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: ZveltTokens.surfaceGrad,
        borderRadius: BorderRadius.circular(ZveltTokens.rCard),
        border: Border.all(color: ZveltTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Distance by session',
              style: ZType.bodyM.copyWith(
                  fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < chart.length; i++) ...[
                  Expanded(child: _chartBar(chart[i], maxKm)),
                  if (i < chart.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartBar(_CardioSession s, double maxKm) {
    final km = s.distanceKm ?? 0;
    final h = (km / maxKm * 96).clamp(8.0, 96.0);
    return InkWell(
      onTap: () => _openDetail(s),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(km.toStringAsFixed(1),
              style: ZType.monoXS.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: ZveltTokens.text2)),
          const SizedBox(height: 7),
          Container(
            width: double.infinity,
            height: h,
            decoration: BoxDecoration(
              color: s.isRide ? ZveltTokens.cardioGold : ZveltTokens.brand,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(7),
                bottom: Radius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(s.dateLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZType.monoXS.copyWith(
                  fontSize: 10.5, color: ZveltTokens.text3)),
        ],
      ),
    );
  }

  // Session row (HTML 933–940)
  Widget _sessionRow(_CardioSession s) {
    final dist = s.distanceKm;
    return InkWell(
      onTap: () => _openDetail(s),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: ZveltTokens.surface2Grad,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ZveltTokens.chip,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(s.kind.icon, size: 21, color: ZveltTokens.brand),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dist == null
                        ? s.typeLabel
                        : '${s.typeLabel} · ${dist.toStringAsFixed(1)} km',
                    style: ZType.bodyL.copyWith(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text('${s.dateLabel} · ${s.durLabel} · ${s.metric}',
                      style: ZType.bodyS.copyWith(
                          fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (s.kcalEstimate > 0) ...[
              const SizedBox(width: 8),
              Text('${s.kcalEstimate} kcal',
                  style: ZType.bodyS.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ZveltTokens.brand)),
            ],
            const SizedBox(width: 4),
            Icon(AppIcons.angle_small_right,
                size: 17, color: ZveltTokens.text3),
          ],
        ),
      ),
    );
  }

  /// Compact real-stats detail (the prototype's activity-detail overlay needs
  /// per-km splits the manual store doesn't record — this shows every stat we
  /// truly have).
  void _openDetail(_CardioSession s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, MediaQuery.paddingOf(context).bottom + 24),
        decoration: BoxDecoration(
          gradient: ZveltTokens.sheetGrad,
          color: ZveltTokens.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ZveltTokens.rSheet)),
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ZveltTokens.track,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ZveltTokens.chip,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child:
                      Icon(s.kind.icon, size: 21, color: ZveltTokens.brand),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.typeLabel,
                        style:
                            ZType.bodyL.copyWith(fontWeight: FontWeight.w800)),
                    Text(s.dateLabel, style: ZType.bodyS),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _detailStat(
                    s.distanceKm == null
                        ? '--'
                        : s.distanceKm!.toStringAsFixed(1),
                    'km'),
                _detailStat(s.durLabel, 'time'),
                _detailStat(s.metric, s.isRide ? 'speed' : 'pace'),
                _detailStat(
                    s.kcalEstimate > 0 ? '${s.kcalEstimate}' : '--', 'kcal'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailStat(String value, String label) => Expanded(
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: ZType.stat.copyWith(fontSize: 20)),
            ),
            const SizedBox(height: 3),
            Text(label, style: ZType.monoXS),
          ],
        ),
      );
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ZveltTokens.chip,
          border: Border.all(color: ZveltTokens.border),
        ),
        child: Icon(icon, size: 18, color: ZveltTokens.text),
      ),
    );
  }
}
