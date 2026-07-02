import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:zvelt_app/services/route_tracker.dart';

/// ~degrees of latitude per meter (1 deg lat ≈ 111_320 m).
const _degPerMeter = 1 / 111320.0;

Position _fix({
  required double lat,
  required double lng,
  required DateTime ts,
  double accuracy = 5,
  double altitude = 100,
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: ts,
    accuracy: accuracy,
    altitude: altitude,
    altitudeAccuracy: 3,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  final t0 = DateTime.utc(2026, 6, 11, 10);

  group('RouteTracker distance filtering', () {
    test('sub-meter GPS jitter does not accumulate distance', () {
      final tracker = RouteTracker();
      // Anchor fix, then 60s of ±0.5 m wiggles — below the 1 m step floor.
      // (The floor is intentionally fine for meter-by-meter distance; the
      // accuracy gate is the main defense against larger GPS jitter.)
      tracker.add(_fix(lat: 51.5, lng: -0.12, ts: t0));
      for (var i = 1; i <= 60; i++) {
        final wiggle = (i.isEven ? 0.5 : -0.5) * _degPerMeter;
        tracker.add(_fix(lat: 51.5 + wiggle, lng: -0.12, ts: t0.add(Duration(seconds: i))));
      }
      expect(tracker.meters, 0);
    });

    test('steady running accumulates ~correct distance', () {
      final tracker = RouteTracker();
      // 3 m/s due north for 100 s = 300 m.
      for (var i = 0; i <= 100; i++) {
        tracker.add(_fix(
          lat: 51.5 + i * 3 * _degPerMeter,
          lng: -0.12,
          ts: t0.add(Duration(seconds: i)),
        ));
      }
      expect(tracker.meters, closeTo(300, 5));
    });

    test('low-accuracy fixes are dropped entirely', () {
      final tracker = RouteTracker();
      tracker.add(_fix(lat: 51.5, lng: -0.12, ts: t0));
      // A 50 m-error fix 30 m away must not count or become the anchor.
      final accepted = tracker.add(_fix(
        lat: 51.5 + 30 * _degPerMeter,
        lng: -0.12,
        ts: t0.add(const Duration(seconds: 1)),
        accuracy: 50,
      ));
      expect(accepted, isFalse);
      expect(tracker.meters, 0);
      expect(tracker.points.length, 1);
    });

    test('teleport jump rebases anchor without counting the jump', () {
      final tracker = RouteTracker();
      tracker.add(_fix(lat: 51.5, lng: -0.12, ts: t0));
      // 500 m in 1 s — impossible for a runner; rebase, don't count.
      tracker.add(_fix(
        lat: 51.5 + 500 * _degPerMeter,
        lng: -0.12,
        ts: t0.add(const Duration(seconds: 1)),
      ));
      expect(tracker.meters, 0);
      // Movement after the rebase counts normally from the new anchor.
      tracker.add(_fix(
        lat: 51.5 + 510 * _degPerMeter,
        lng: -0.12,
        ts: t0.add(const Duration(seconds: 5)),
      ));
      expect(tracker.meters, closeTo(10, 1));
    });

    test('bike mode allows higher speeds than run mode', () {
      // 20 m/s (72 km/h downhill sprint) — plausible on a bike, not on foot.
      final run = RouteTracker();
      final bike = RouteTracker(isBike: true);
      for (final tracker in [run, bike]) {
        tracker.add(_fix(lat: 51.5, lng: -0.12, ts: t0));
        tracker.add(_fix(
          lat: 51.5 + 20 * _degPerMeter,
          lng: -0.12,
          ts: t0.add(const Duration(seconds: 1)),
        ));
      }
      expect(run.meters, 0); // rebased as a teleport
      expect(bike.meters, closeTo(20, 1));
    });

    test('sub-1m moves are ignored as jitter', () {
      final tracker = RouteTracker();
      tracker.add(_fix(lat: 51.5, lng: -0.12, ts: t0));
      final accepted = tracker.add(_fix(
        lat: 51.5 + 0.5 * _degPerMeter,
        lng: -0.12,
        ts: t0.add(const Duration(seconds: 1)),
      ));
      expect(accepted, isFalse);
      expect(tracker.meters, 0);
    });

    test('a precise fix moving 1m+ is counted (meter-by-meter granularity)', () {
      final tracker = RouteTracker();
      // accuracy 2 m → floor clamps to 1 m, so a 1.5 m move counts.
      tracker.add(_fix(lat: 51.5, lng: -0.12, ts: t0, accuracy: 2));
      final accepted = tracker.add(_fix(
        lat: 51.5 + 1.5 * _degPerMeter,
        lng: -0.12,
        ts: t0.add(const Duration(seconds: 1)),
        accuracy: 2,
      ));
      expect(accepted, isTrue);
      expect(tracker.meters, closeTo(1.5, 0.5));
    });

    test('stationary drift with mediocre accuracy does not accumulate', () {
      final tracker = RouteTracker();
      // accuracy 10 m → floor rises to 5 m, so ±3 m rest-drift is rejected.
      tracker.add(_fix(lat: 51.5, lng: -0.12, ts: t0, accuracy: 10));
      for (var i = 1; i <= 60; i++) {
        final wiggle = (i.isEven ? 3 : -3) * _degPerMeter;
        tracker.add(_fix(
          lat: 51.5 + wiggle,
          lng: -0.12,
          ts: t0.add(Duration(seconds: i)),
          accuracy: 10,
        ));
      }
      expect(tracker.meters, 0);
    });
  });

  group('RouteTracker elevation gain', () {
    test('noise below 3m hysteresis is not counted; real climbs are', () {
      final tracker = RouteTracker();
      var lat = 51.5;
      var i = 0;
      void step(double altitude) {
        lat += 10 * _degPerMeter; // keep moving so fixes are accepted
        tracker.add(_fix(
          lat: lat,
          lng: -0.12,
          ts: t0.add(Duration(seconds: ++i * 5)),
          altitude: altitude,
        ));
      }

      step(100);
      step(101); // +1 noise — below hysteresis
      step(100); // back down
      expect(tracker.elevGainM, 0);

      step(104); // +4 real climb from the 100 baseline
      step(110); // +6 more
      expect(tracker.elevGainM, closeTo(10, 0.01));
    });
  });

  group('RouteTracker reset', () {
    test('reset clears everything', () {
      final tracker = RouteTracker();
      tracker.add(_fix(lat: 51.5, lng: -0.12, ts: t0));
      tracker.add(_fix(
        lat: 51.5 + 10 * _degPerMeter,
        lng: -0.12,
        ts: t0.add(const Duration(seconds: 5)),
      ));
      expect(tracker.meters, greaterThan(0));
      tracker.reset();
      expect(tracker.meters, 0);
      expect(tracker.elevGainM, 0);
      expect(tracker.points, isEmpty);
      expect(tracker.pointTs, isEmpty);
      expect(tracker.lastPoint, isNull);
    });
  });
}
