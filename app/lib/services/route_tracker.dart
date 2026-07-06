import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Shared GPS route accumulator with noise filtering, used by every live
/// outdoor tracking screen so distance math stays identical everywhere.
///
/// Raw position streams inflate distance: standing still, the fix jitters
/// ±3–10 m and each wiggle used to be summed into the total. Filters applied
/// here, in order:
///  1. Accuracy gate — fixes with a reported error radius >25 m are dropped.
///  2. Stationary speed gate — when the device reports a trustworthy speed
///     below a slow walk (~0.5 m/s), the fix is dropped. This is the primary
///     defence against "counting while sitting still": position jitter can
///     exceed any distance threshold, but the device's own speed estimate is
///     ~0 when you aren't moving. Only applied when the platform provides a
///     positive, confident speed (speed==0 is treated as "unknown" so devices
///     without a speed sensor never have every fix rejected).
///  3. Movement arming — a session starts at 0 m and stays there until GPS
///     proves real movement. Unknown-speed fixes need sustained displacement at
///     a plausible walking/running speed; this blocks the common "starts at
///     9 m while I am still standing still" drift.
///  4. Minimum displacement — a floor of ≥8 m (rising with the fix's error
///     radius) so sub-accuracy drift isn't summed as travel. Real movement
///     still accumulates exactly: the anchor only advances once a fix clears
///     the floor, so walking/running distance batches without loss.
///  5. Teleport guard — a jump implying an impossible speed (>12 m/s run,
///     >30 m/s bike) rebases the anchor without counting the jump distance
///     (GPS relocation after a tunnel/signal loss, not real travel).
///
/// Elevation gain uses a 3 m hysteresis: altitude must rise ≥3 m above the
/// rolling baseline before any gain is counted, and the baseline follows the
/// lowest recent altitude, so barometric/GPS altitude noise doesn't add up.
class RouteTracker {
  RouteTracker({this.isBike = false});

  final bool isBike;

  static const double _kMaxAccuracyM = 25.0;

  /// Below a slow walk → treated as stationary (2.5 km/h ≈ 0.5 m/s wouldn't be
  /// counted; a real walk is ~1.1–1.4 m/s so it's never wrongly dropped).
  static const double _kMinMovingSpeedMs = 0.5;

  /// Minimum displacement (m) before distance is counted — GPS drift while
  /// stationary commonly wanders 5–10 m even with a "good" fix.
  static const double _kMinStepFloorM = 8.0;
  static const double _kMaxStepFloorM = 20.0;
  static const double _kStartDistanceFloorM = 12.0;
  static const double _kUnknownStartMinSpeedMs = 0.6;
  static const double _kElevHysteresisM = 3.0;

  /// Accepted route points (what the polyline should draw).
  final List<LatLng> points = [];

  /// Timestamps parallel to [points] (for route export).
  final List<DateTime> pointTs = [];

  /// Total filtered distance in meters.
  double meters = 0;

  /// Total elevation gain in meters (3 m hysteresis).
  double elevGainM = 0;

  LatLng? _last;
  DateTime? _lastTs;
  LatLng? _pendingUnknownSpeed;
  DateTime? _pendingUnknownSpeedTs;
  double? _altBase;
  bool _movementArmed = false;

  double get _maxSpeedMs => isBike ? 30.0 : 12.0;

  LatLng? get lastPoint => _last;

  void reset() {
    points.clear();
    pointTs.clear();
    meters = 0;
    elevGainM = 0;
    _last = null;
    _lastTs = null;
    _pendingUnknownSpeed = null;
    _pendingUnknownSpeedTs = null;
    _altBase = null;
    _movementArmed = false;
  }

  /// Feed a raw GPS fix. Returns true if it was accepted (route/distance
  /// updated) — rejected fixes should not move the marker or the camera.
  bool add(Position pos) {
    // 1. Accuracy gate (0 = unknown on some platforms; let those through).
    if (pos.accuracy > _kMaxAccuracyM) return false;

    // 2. Stationary speed gate. When the platform reports a positive, confident
    // speed below a slow walk, you're standing still — drop the fix so GPS
    // jitter isn't accumulated (the couch-drift bug). speed==0 is treated as
    // "unknown" (some devices report 0 with no speed sensor), so this can never
    // reject every fix; those devices fall through to the displacement floor.
    final ll = LatLng(pos.latitude, pos.longitude);
    final ts = pos.timestamp;

    if (_last == null) {
      _accept(ll, ts, pos);
      return true;
    }

    if (_isStationary(pos)) {
      _clearPendingUnknownSpeed();
      return false;
    }

    final delta = Geolocator.distanceBetween(
      _last!.latitude,
      _last!.longitude,
      ll.latitude,
      ll.longitude,
    );

    // 3. Minimum displacement — a floor of ≥8 m (rising with the fix's error
    // radius). The anchor only advances once a fix clears the floor, so real
    // walking/running distance still accumulates exactly (it batches), while
    // sub-accuracy stationary drift never crosses it.
    final minStep = (pos.accuracy > 0 ? pos.accuracy : _kMinStepFloorM)
        .clamp(_kMinStepFloorM, _kMaxStepFloorM);
    if (delta < minStep) {
      _clearPendingUnknownSpeed();
      return false;
    }

    // 3. Teleport guard — rebase the anchor without counting the jump and
    // without appending to the polyline, so the drawn line doesn't streak
    // across the gap (e.g. GPS relocation after a tunnel/signal loss).
    final dtS = ts.difference(_lastTs!).inMilliseconds / 1000.0;
    if (dtS > 0 && delta / dtS > _maxSpeedMs) {
      _last = ll;
      _lastTs = ts;
      _clearPendingUnknownSpeed();
      return true;
    }

    if (!_movementArmed) {
      if (!_confirmMovementStart(pos, ll, ts, delta, minStep)) {
        return false;
      }
      _movementArmed = true;
      _clearPendingUnknownSpeed();
    }

    meters += delta;
    _accept(ll, ts, pos);
    return true;
  }

  /// True when the platform is confident you're moving slower than a slow walk.
  /// Requires a positive speed AND a positive, tight speedAccuracy so a device
  /// that reports 0/unknown speed never has every fix dropped (it falls back to
  /// the displacement floor instead).
  bool _isStationary(Position pos) {
    return _hasTrustedSpeed(pos) && pos.speed < _kMinMovingSpeedMs;
  }

  bool _hasTrustedSpeed(Position pos) {
    final s = pos.speed;
    final sa = pos.speedAccuracy;
    return s.isFinite &&
        s > 0 &&
        sa.isFinite &&
        sa > 0 &&
        sa < 2.0; // uncertainty tighter than ~7 km/h
  }

  bool _confirmMovementStart(
    Position pos,
    LatLng ll,
    DateTime ts,
    double deltaFromAnchor,
    double minStep,
  ) {
    if (_hasTrustedSpeed(pos)) {
      return pos.speed >= _kMinMovingSpeedMs;
    }

    final startDistance = _maxDouble(minStep * 1.5, _kStartDistanceFloorM);
    if (deltaFromAnchor < startDistance) {
      _clearPendingUnknownSpeed();
      return false;
    }

    final elapsedFromAnchor = ts.difference(_lastTs!).inMilliseconds / 1000.0;
    if (elapsedFromAnchor <= 0 ||
        deltaFromAnchor / elapsedFromAnchor < _kUnknownStartMinSpeedMs) {
      _pendingUnknownSpeed = ll;
      _pendingUnknownSpeedTs = ts;
      return false;
    }

    return _confirmUnknownSpeedMovement(ll, ts, deltaFromAnchor, minStep);
  }

  bool _confirmUnknownSpeedMovement(
    LatLng ll,
    DateTime ts,
    double deltaFromAnchor,
    double minStep,
  ) {
    final pending = _pendingUnknownSpeed;
    final pendingTs = _pendingUnknownSpeedTs;
    if (pending == null || pendingTs == null) {
      _pendingUnknownSpeed = ll;
      _pendingUnknownSpeedTs = ts;
      return false;
    }

    final pendingFromAnchor = Geolocator.distanceBetween(
      _last!.latitude,
      _last!.longitude,
      pending.latitude,
      pending.longitude,
    );
    final progressedAway =
        deltaFromAnchor > pendingFromAnchor + (minStep * 0.25);
    final progressedAfterCandidate =
        ts.difference(pendingTs).inMilliseconds > 0;
    if (!progressedAway || !progressedAfterCandidate) {
      _pendingUnknownSpeed = ll;
      _pendingUnknownSpeedTs = ts;
      return false;
    }
    _clearPendingUnknownSpeed();
    return true;
  }

  void _clearPendingUnknownSpeed() {
    _pendingUnknownSpeed = null;
    _pendingUnknownSpeedTs = null;
  }

  double _maxDouble(double a, double b) => a > b ? a : b;

  void _accept(LatLng ll, DateTime ts, Position pos) {
    points.add(ll);
    pointTs.add(ts);
    _last = ll;
    _lastTs = ts;

    // Elevation gain (altitude 0 usually means "no data" — skip it).
    final alt = pos.altitude;
    if (alt.isFinite && alt != 0) {
      if (_altBase == null || alt < _altBase!) {
        _altBase = alt;
      } else if (alt - _altBase! >= _kElevHysteresisM) {
        elevGainM += alt - _altBase!;
        _altBase = alt;
      }
    }
  }
}
