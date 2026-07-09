import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Singleton that owns the app's GPS tracking lifecycle.
///
/// Usage:
/// ```dart
/// final ok = await LocationService.instance.checkAndRequestPermission();
/// if (ok) {
///   LocationService.instance.startTracking().listen((pos) { ... });
/// }
/// // When done:
/// LocationService.instance.stopTracking();
/// ```
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  // Broadcast so multiple listeners (map, stats, logger) can subscribe.
  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();

  StreamSubscription<Position>? _subscription;
  bool _isTracking = false;

  /// Live position updates during an active tracking session.
  Stream<Position> get positionStream => _controller.stream;

  bool get isTracking => _isTracking;

  // ─── Permission ─────────────────────────────────────────────────────────────

  /// Checks location service availability and permission status.
  /// Requests permission if not yet granted.
  ///
  /// Returns `true` when at least [LocationPermission.whileInUse] is granted
  /// and the device location service is on.
  Future<LocationPermissionStatus> checkAndRequestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionStatus.serviceDisabled;
    }

    LocationPermission perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    switch (perm) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;
      default:
        return LocationPermissionStatus.denied;
    }
  }

  /// `true` if at least whileInUse permission is held (no prompt shown).
  Future<bool> hasPermission() async {
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  /// Opens the OS location settings page (use after [deniedForever]).
  Future<void> openSettings() => Geolocator.openLocationSettings();

  // ─── One-shot ────────────────────────────────────────────────────────────────

  /// Returns the current position once. Returns `null` on permission error.
  Future<Position?> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    final status = await checkAndRequestPermission();
    if (status != LocationPermissionStatus.granted) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: accuracy),
      );
    } catch (e) {
      debugPrint('LocationService.getCurrentPosition: $e');
      return null;
    }
  }

  // ─── Continuous tracking ─────────────────────────────────────────────────────

  /// Starts continuous GPS updates and returns the broadcast stream.
  ///
  /// [distanceFilter] — minimum metres between updates (default 5 m).
  /// [accuracy] — GPS accuracy (default [LocationAccuracy.high]).
  ///
  /// Safe to call multiple times; ignores subsequent calls while active.
  Stream<Position> startTracking({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 5,
  }) {
    if (_isTracking) return positionStream;

    final settings = _buildSettings(accuracy: accuracy, distanceFilter: distanceFilter);

    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      _controller.add,
      onError: _controller.addError,
      cancelOnError: false,
    );

    _isTracking = true;
    debugPrint('LocationService: tracking started');
    return positionStream;
  }

  /// Stops GPS updates. The [positionStream] stays open for the next session.
  void stopTracking() {
    _subscription?.cancel();
    _subscription = null;
    _isTracking = false;
    debugPrint('LocationService: tracking stopped');
  }

  /// Distance in metres between two positions (Vincenty formula via geolocator).
  double distanceBetween(Position a, Position b) => Geolocator.distanceBetween(
        a.latitude, a.longitude,
        b.latitude, b.longitude,
      );

  /// Bearing in degrees from [a] to [b].
  double bearingBetween(Position a, Position b) => Geolocator.bearingBetween(
        a.latitude, a.longitude,
        b.latitude, b.longitude,
      );

  // ─── Private ─────────────────────────────────────────────────────────────────

  LocationSettings _buildSettings({
    required LocationAccuracy accuracy,
    required int distanceFilter,
  }) {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        // Keeps tracking when screen is off (Info.plist has UIBackgroundModes=location).
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }
    return LocationSettings(accuracy: accuracy, distanceFilter: distanceFilter);
  }
}

// ─── Status enum ─────────────────────────────────────────────────────────────

enum LocationPermissionStatus {
  /// At least whileInUse permission granted and service enabled.
  granted,

  /// User denied; can ask again.
  denied,

  /// User chose "Never" — must send to OS settings.
  deniedForever,

  /// Device GPS/location service is off — ask user to enable it.
  serviceDisabled,
}

extension LocationPermissionStatusX on LocationPermissionStatus {
  bool get isGranted => this == LocationPermissionStatus.granted;

  /// Human-readable message to show in a dialog or snackbar.
  String get message {
    switch (this) {
      case LocationPermissionStatus.granted:
        return 'Location access granted.';
      case LocationPermissionStatus.denied:
        return 'Location permission denied. Please allow access to track your workout.';
      case LocationPermissionStatus.deniedForever:
        return 'Location is permanently blocked. Open Settings and enable it for Zvelt.';
      case LocationPermissionStatus.serviceDisabled:
        return 'Location services are off. Enable them in device settings.';
    }
  }
}
