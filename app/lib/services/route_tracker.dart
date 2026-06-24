import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Shared GPS route accumulator with noise filtering, used by every live
/// outdoor tracking screen so distance math stays identical everywhere.
///
/// Raw position streams inflate distance: standing still, the fix jitters
/// ±3–10 m and each wiggle used to be summed into the total. Filters applied
/// here, in order:
///  1. Accuracy gate — fixes with a reported error radius >25 m are dropped.
///  2. Minimum displacement — moves shorter than 5 m from the last accepted
///     point are ignored (jitter, not travel).
///  3. Teleport guard — a jump implying an impossible speed (>12 m/s run,
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
  static const double _kMinStepM = 5.0;
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
  double? _altBase;

  double get _maxSpeedMs => isBike ? 30.0 : 12.0;

  LatLng? get lastPoint => _last;

  void reset() {
    points.clear();
    pointTs.clear();
    meters = 0;
    elevGainM = 0;
    _last = null;
    _lastTs = null;
    _altBase = null;
  }

  /// Feed a raw GPS fix. Returns true if it was accepted (route/distance
  /// updated) — rejected fixes should not move the marker or the camera.
  bool add(Position pos) {
    // 1. Accuracy gate (0 = unknown on some platforms; let those through).
    if (pos.accuracy > _kMaxAccuracyM) return false;

    final ll = LatLng(pos.latitude, pos.longitude);
    final ts = pos.timestamp;

    if (_last == null) {
      _accept(ll, ts, pos);
      return true;
    }

    final delta = Geolocator.distanceBetween(
      _last!.latitude,
      _last!.longitude,
      ll.latitude,
      ll.longitude,
    );

    // 2. Minimum displacement — jitter, not travel.
    if (delta < _kMinStepM) return false;

    // 3. Teleport guard — rebase the anchor without counting the jump and
    // without appending to the polyline, so the drawn line doesn't streak
    // across the gap (e.g. GPS relocation after a tunnel/signal loss).
    final dtS = ts.difference(_lastTs!).inMilliseconds / 1000.0;
    if (dtS > 0 && delta / dtS > _maxSpeedMs) {
      _last = ll;
      _lastTs = ts;
      return true;
    }

    meters += delta;
    _accept(ll, ts, pos);
    return true;
  }

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
