import 'health_service.dart';

/// Pure, on-device computation behind the "Today's body" card and the
/// per-metric detail screens (Strain / Recovery / Sleep).
///
/// Design constraints (non-negotiable):
///  - NO fabricated numbers. Every score is derived from real HealthSummary
///    signals; a metric with no signals is `null` and the UI says so.
///  - Explainable. Each score carries its [MetricInput] breakdown (the real
///    values + how much they weigh), rendered verbatim on the detail screen.
///
/// "Strain" here is NOT Whoop's proprietary cardiovascular strain — there is
/// no licensed source for that. It is an honest, transparent daily-load
/// proxy: how much of a typical training day's load you've accumulated so
/// far, from three observable signals:
///    workout time (target 60 min)   → 50%
///    active energy (target 600 kcal) → 35%
///    steps (target 10,000)           → 15%
/// Zero in the morning is a TRUE statement (no load yet), so strain is
/// non-null whenever a health summary loaded at all.
class BodyMetricsService {
  BodyMetricsService._();

  // Strain targets — "100% strain" ≈ a full training day's load.
  static const double kStrainWorkoutTargetMin = 60;
  static const double kStrainEnergyTargetKcal = 600;
  static const double kStrainStepsTarget = 10000;

  // Recovery weights — identical to the long-standing home-tab math so the
  // number can never disagree with what users saw before. Missing signals
  // re-weight the rest (Xiaomi/Amazfit bands often don't write HRV).
  static const double kHrvWeight = 40;
  static const double kSleepWeight = 40;
  static const double kRhrWeight = 20;

  static const double kSleepTargetHours = 8;

  /// Card state when Health permissions aren't granted (or no summary has
  /// loaded yet): all three metrics null — the card renders dimmed '–'
  /// rings and the coach line points at connecting a wearable. The card is
  /// ALWAYS visible (per the design); only its numbers are gated on data.
  static BodyMetrics empty() => const BodyMetrics(
        strain: null,
        recovery: null,
        sleep: null,
        headline: 'No body data yet',
        coachLine:
            'Connect a wearable (sleep, heart rate, steps) and this card '
            'comes alive with your real readiness.',
      );

  /// Compute all three metrics + the card copy from a loaded summary.
  /// [now] is injectable for tests.
  static BodyMetrics compute(HealthSummary s, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final sleep = _sleep(s);
    final recovery = _recovery(s);
    final strain = _strain(s, clock);

    final headline = _headline(recovery);
    final coachLine = _coachLine(recovery: recovery, strain: strain);

    return BodyMetrics(
      strain: strain,
      recovery: recovery,
      sleep: sleep,
      headline: headline,
      coachLine: coachLine,
    );
  }

  // ── Sleep ───────────────────────────────────────────────────────────────

  static MetricScore? _sleep(HealthSummary s) {
    final h = s.sleepLastNight;
    if (h <= 0) return null;
    final pct = (h / kSleepTargetHours * 100).round().clamp(0, 100);
    final String insight;
    if (pct >= 95) {
      insight = 'A full night. Your body had the time it needed to repair.';
    } else if (pct >= 75) {
      insight = 'Solid sleep. You should feel close to your normal self.';
    } else if (pct >= 50) {
      insight =
          'A short night. Expect slightly lower output — warm up longer.';
    } else {
      insight =
          'Very little sleep. Heavy training today carries extra injury risk.';
    }
    return MetricScore(
      pct: pct,
      insight: insight,
      inputs: [
        MetricInput(
          label: 'Time asleep',
          value: _hoursLabel(h),
          detail: 'of your ${kSleepTargetHours.toInt()}h target',
          quality: (h / kSleepTargetHours).clamp(0.0, 1.0),
        ),
      ],
    );
  }

  // ── Recovery ────────────────────────────────────────────────────────────

  static MetricScore? _recovery(HealthSummary s) {
    final hrv = s.hrvRmssdMs ?? 0.0;
    final sleep = s.sleepLastNight;
    final rhr = s.restingHeartRateBpm ?? 0.0;

    double weight = 0, acc = 0;
    final inputs = <MetricInput>[];

    void add(double w, double quality, MetricInput input) {
      weight += w;
      acc += w * quality.clamp(0.0, 1.0);
      inputs.add(input);
    }

    if (hrv > 0) {
      final q = hrv / 80.0;
      final baseline = (s.hrvBaselineLowMs != null && s.hrvBaselineHighMs != null)
          ? ' · your baseline ${s.hrvBaselineLowMs!.round()}–${s.hrvBaselineHighMs!.round()} ms'
          : '';
      add(
        kHrvWeight,
        q,
        MetricInput(
          label: 'HRV',
          value: '${hrv.round()} ms',
          detail: 'heart-rate variability$baseline',
          quality: q.clamp(0.0, 1.0),
        ),
      );
    }
    if (sleep > 0) {
      final q = sleep / kSleepTargetHours;
      add(
        kSleepWeight,
        q,
        MetricInput(
          label: 'Sleep',
          value: _hoursLabel(sleep),
          detail: 'last night, of ${kSleepTargetHours.toInt()}h',
          quality: q.clamp(0.0, 1.0),
        ),
      );
    }
    if (rhr > 0) {
      final q = (100.0 - rhr) / 60.0;
      final baseline = (s.rhrBaselineLowBpm != null && s.rhrBaselineHighBpm != null)
          ? ' · your baseline ${s.rhrBaselineLowBpm!.round()}–${s.rhrBaselineHighBpm!.round()} bpm'
          : '';
      add(
        kRhrWeight,
        q,
        MetricInput(
          label: 'Resting HR',
          value: '${rhr.round()} bpm',
          detail: 'lower is better$baseline',
          quality: q.clamp(0.0, 1.0),
        ),
      );
    }

    if (weight <= 0) return null; // zero signals → no score, no guessing

    final pct = (acc / weight * 100).round().clamp(0, 100);
    final String insight;
    if (pct > 75) {
      insight = 'Your body absorbed the recent load well. Green light to push.';
    } else if (pct >= 50) {
      insight =
          'Partially recovered. A moderate session helps more than a max effort.';
    } else {
      insight =
          'Your signals point to fatigue. An easy day now buys a better week.';
    }
    return MetricScore(pct: pct, insight: insight, inputs: inputs);
  }

  // ── Strain (transparent daily-load proxy) ───────────────────────────────

  static MetricScore? _strain(HealthSummary s, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    double workoutMin = 0;
    for (final w in s.workoutsThisWeek) {
      if (!w.startTime.isBefore(today)) {
        workoutMin += w.duration.inMinutes.toDouble();
      }
    }
    final kcal = s.caloriesToday;
    final steps = s.stepsToday.toDouble();

    final wQ = (workoutMin / kStrainWorkoutTargetMin).clamp(0.0, 1.0);
    final eQ = (kcal / kStrainEnergyTargetKcal).clamp(0.0, 1.0);
    final sQ = (steps / kStrainStepsTarget).clamp(0.0, 1.0);

    final pct = (wQ * 50 + eQ * 35 + sQ * 15).round().clamp(0, 100);

    final String insight;
    if (pct >= 80) {
      insight = "A big day — you've taken on a full training load already.";
    } else if (pct >= 50) {
      insight = 'A moderate load so far. Room left if recovery allows.';
    } else if (pct > 0) {
      insight = 'Light load so far today.';
    } else {
      insight = 'No training load yet today.';
    }

    return MetricScore(
      pct: pct,
      insight: insight,
      inputs: [
        MetricInput(
          label: 'Workout time',
          value: '${workoutMin.round()} min',
          detail: 'today, of ${kStrainWorkoutTargetMin.toInt()} min · 50% of strain',
          quality: wQ,
        ),
        MetricInput(
          label: 'Active energy',
          value: '${kcal.round()} kcal',
          detail: 'today, of ${kStrainEnergyTargetKcal.toInt()} kcal · 35% of strain',
          quality: eQ,
        ),
        MetricInput(
          label: 'Steps',
          value: '${s.stepsToday}',
          detail: 'today, of ${kStrainStepsTarget.toInt()} · 15% of strain',
          quality: sQ,
        ),
      ],
    );
  }

  // ── Card copy ───────────────────────────────────────────────────────────

  static String _headline(MetricScore? recovery) {
    if (recovery == null) return 'No recovery data yet';
    if (recovery.pct > 75) return 'Primed';
    if (recovery.pct >= 50) return 'Fair recovery';
    return 'Low recovery';
  }

  static String _coachLine({MetricScore? recovery, MetricScore? strain}) {
    if (recovery == null) {
      return 'Wear your tracker tonight (sleep, HRV, resting HR) to unlock a '
          'recovery-based plan.';
    }
    final strained = (strain?.pct ?? 0) >= 80;
    if (recovery.pct > 75) {
      return strained
          ? "Big load already banked today — you've earned the rest."
          : 'Green light — push a hard session, aim 80%+ strain.';
    }
    if (recovery.pct >= 50) {
      return strained
          ? "You've already hit a solid load — wrap it up and recover."
          : 'Moderate session today — aim 50–80% strain.';
    }
    return 'Prioritize recovery — keep strain under 50% today.';
  }

  static String _hoursLabel(double h) {
    final hh = h.floor();
    final mm = ((h - hh) * 60).round();
    return '${hh}h ${mm.toString().padLeft(2, '0')}m';
  }
}

/// One real input signal behind a score — rendered verbatim in the
/// detail screen's breakdown (explainability principle).
class MetricInput {
  const MetricInput({
    required this.label,
    required this.value,
    required this.detail,
    required this.quality,
  });

  final String label;
  final String value;
  final String detail;

  /// 0..1 — how 'full' this signal is vs its target/baseline; drives the
  /// breakdown bar.
  final double quality;
}

class MetricScore {
  const MetricScore({
    required this.pct,
    required this.inputs,
    required this.insight,
  });

  /// 0–100.
  final int pct;
  final List<MetricInput> inputs;
  final String insight;
}

class BodyMetrics {
  const BodyMetrics({
    required this.strain,
    required this.recovery,
    required this.sleep,
    required this.headline,
    required this.coachLine,
  });

  /// null = not enough real signals for that metric.
  final MetricScore? strain;
  final MetricScore? recovery;
  final MetricScore? sleep;

  /// Card title state — derived from recovery (e.g. 'Fair recovery').
  final String headline;

  /// Coach footer line — derived from recovery × strain.
  final String coachLine;
}
