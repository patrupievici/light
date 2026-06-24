import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/body_metrics_service.dart';
import 'package:zvelt_app/services/health_service.dart';

HealthSummary _summary({
  int steps = 0,
  double calories = 0,
  double sleep = 0,
  List<HealthWorkout> workouts = const [],
  double? hrv,
  double? rhr,
}) {
  return HealthSummary(
    stepsToday: steps,
    caloriesToday: calories,
    sleepLastNight: sleep,
    workoutsThisWeek: workouts,
    stepXpToday: 0,
    hrvRmssdMs: hrv,
    restingHeartRateBpm: rhr,
  );
}

void main() {
  final now = DateTime(2026, 6, 12, 18); // fixed clock for strain math

  group('Recovery', () {
    test('no overnight signals → null score, honest headline + coach line', () {
      final m = BodyMetricsService.compute(_summary(steps: 4000), now: now);
      expect(m.recovery, isNull);
      expect(m.sleep, isNull);
      expect(m.headline, 'No recovery data yet');
      expect(m.coachLine, contains('Wear your tracker'));
    });

    test('full signals → weighted score (HRV 40 / Sleep 40 / RHR 20)', () {
      // hrv 80→q1.0 · sleep 8→q1.0 · rhr 40→q1.0  ⇒ 100%
      final m = BodyMetricsService.compute(
        _summary(sleep: 8, hrv: 80, rhr: 40),
        now: now,
      );
      expect(m.recovery!.pct, 100);
      expect(m.headline, 'Primed');
      expect(m.recovery!.inputs, hasLength(3));
    });

    test('missing HRV re-weights to Sleep + RHR instead of capping', () {
      // sleep 8 (q1.0, w40) + rhr 40 (q1.0, w20) → 60/60 = 100%
      final m = BodyMetricsService.compute(
        _summary(sleep: 8, rhr: 40),
        now: now,
      );
      expect(m.recovery!.pct, 100);
      expect(m.recovery!.inputs.map((i) => i.label),
          isNot(contains('HRV')));
    });

    test('thresholds: <50 Low · 50-75 Fair · >75 Primed', () {
      // Sleep-only score = sleep/8 → easy to dial exact percentages.
      expect(
        BodyMetricsService.compute(_summary(sleep: 3.2), now: now).headline,
        'Low recovery', // 40%
      );
      expect(
        BodyMetricsService.compute(_summary(sleep: 4.8), now: now).headline,
        'Fair recovery', // 60%
      );
      expect(
        BodyMetricsService.compute(_summary(sleep: 8), now: now).headline,
        'Primed', // 100%
      );
    });
  });

  group('Sleep', () {
    test('7h12m of 8h target → 90%', () {
      final m = BodyMetricsService.compute(_summary(sleep: 7.2), now: now);
      expect(m.sleep!.pct, 90);
      expect(m.sleep!.inputs.single.value, '7h 12m');
    });

    test('oversleep clamps to 100', () {
      final m = BodyMetricsService.compute(_summary(sleep: 10), now: now);
      expect(m.sleep!.pct, 100);
    });
  });

  group('Strain (transparent daily-load proxy)', () {
    test('zero activity → 0% (an honest statement, not missing data)', () {
      final m = BodyMetricsService.compute(_summary(), now: now);
      expect(m.strain, isNotNull);
      expect(m.strain!.pct, 0);
      expect(m.strain!.insight, contains('No training load'));
    });

    test('full targets hit → 100% (60min workout + 600kcal + 10k steps)', () {
      final m = BodyMetricsService.compute(
        _summary(
          steps: 10000,
          calories: 600,
          workouts: [
            HealthWorkout(
              type: 'strength',
              startTime: DateTime(2026, 6, 12, 7),
              endTime: DateTime(2026, 6, 12, 8),
              calories: 400,
            ),
          ],
        ),
        now: now,
      );
      expect(m.strain!.pct, 100);
    });

    test("yesterday's workouts don't count toward today's strain", () {
      final m = BodyMetricsService.compute(
        _summary(
          workouts: [
            HealthWorkout(
              type: 'run',
              startTime: DateTime(2026, 6, 11, 7),
              endTime: DateTime(2026, 6, 11, 8),
              calories: 500,
            ),
          ],
        ),
        now: now,
      );
      expect(m.strain!.pct, 0);
    });

    test('weights: workout 50 · energy 35 · steps 15', () {
      // 30min workout (q0.5→25) + 300kcal (q0.5→17.5) + 5k steps (q0.5→7.5) = 50
      final m = BodyMetricsService.compute(
        _summary(
          steps: 5000,
          calories: 300,
          workouts: [
            HealthWorkout(
              type: 'strength',
              startTime: DateTime(2026, 6, 12, 7),
              endTime: DateTime(2026, 6, 12, 7, 30),
              calories: 200,
            ),
          ],
        ),
        now: now,
      );
      expect(m.strain!.pct, 50);
    });
  });

  group('Coach line (recovery × strain)', () {
    test('primed + low strain → push', () {
      final m = BodyMetricsService.compute(_summary(sleep: 8), now: now);
      expect(m.coachLine, contains('Green light'));
    });

    test('fair recovery → moderate session, 50-80% strain target', () {
      final m = BodyMetricsService.compute(_summary(sleep: 4.8), now: now);
      expect(m.coachLine, contains('50–80% strain'));
    });

    test('low recovery → keep strain under 50%', () {
      final m = BodyMetricsService.compute(_summary(sleep: 3.2), now: now);
      expect(m.coachLine, contains('under 50%'));
    });

    test('primed but big load already banked → wrap-up message', () {
      final m = BodyMetricsService.compute(
        _summary(
          sleep: 8,
          steps: 10000,
          calories: 600,
          workouts: [
            HealthWorkout(
              type: 'strength',
              startTime: DateTime(2026, 6, 12, 7),
              endTime: DateTime(2026, 6, 12, 8, 30),
              calories: 600,
            ),
          ],
        ),
        now: now,
      );
      expect(m.strain!.pct, greaterThanOrEqualTo(80));
      expect(m.coachLine, contains('earned the rest'));
    });
  });
}
