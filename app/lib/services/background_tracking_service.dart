import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../config/api_config.dart' show v1Base;
import 'auth_service.dart';
import 'http_client.dart';
import 'location_service.dart';
import 'secure_db.dart';

// ─── Public data class ────────────────────────────────────────────────────────

class TrackingStats {
  const TrackingStats({
    required this.sessionId,
    required this.elapsed,
    required this.distanceM,
    required this.speedKmh,
    required this.calories,
    required this.pointCount,
    required this.isTracking,
    this.isSynced = false,
  });

  final String sessionId;
  final Duration elapsed;
  final double distanceM;
  final double speedKmh;
  final int calories;
  final int pointCount;
  final bool isTracking;
  final bool isSynced;

  double get distanceKm => distanceM / 1000;

  String get distanceLabel => distanceM >= 1000
      ? '${distanceKm.toStringAsFixed(2)} km'
      : '${distanceM.round()} m';

  String get durationLabel {
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String get speedLabel => '${speedKmh.toStringAsFixed(1)} km/h';

  @override
  String toString() =>
      'TrackingStats(session=$sessionId, dist=$distanceLabel, '
      'dur=$durationLabel, pts=$pointCount, synced=$isSynced)';
}

// ─── Singleton service ────────────────────────────────────────────────────────

/// Background GPS activity tracking service.
///
/// Architecture:
/// - GPS via [LocationService] (geolocator foreground service on Android,
///   always-on location on iOS via Info.plist UIBackgroundModes=location)
/// - Local persistence: SQLite (zvelt_tracking.db) — every point saved in real-time
/// - Notification: flutter_local_notifications, updated every [_kNotifIntervalSec]s
/// - Stationary auto-stop: no movement (speed < 0.5 m/s) for [_kStationaryMinutes]
/// - Sync: POST /v1/activities on stop; pending sessions retried on next start
///
/// Usage:
/// ```dart
/// await BackgroundTrackingService.instance.startTracking();
/// final stats = BackgroundTrackingService.instance.getCurrentStats();
/// final finalStats = await BackgroundTrackingService.instance.stopTracking();
/// ```
class BackgroundTrackingService {
  BackgroundTrackingService._();
  static final BackgroundTrackingService instance = BackgroundTrackingService._();

  // ── Config ──────────────────────────────────────────────────────────────────
  static const _kDbName = 'zvelt_tracking.db';
  static const _kPointsTable = 'tracking_points';
  static const _kSessionsTable = 'tracking_sessions';
  static const _kNotifId = 9001;
  static const _kNotifChannelId = 'zvelt_bg_tracking';
  static const _kNotifChannelName = 'Activity Tracking';
  static const _kNotifIntervalSec = 5;
  static const _kStationaryCheckSec = 60;
  static const _kStationaryMinutes = 10;
  static const _kStationarySpeedThreshold = 0.5; // m/s (~1.8 km/h)

  // ── State ───────────────────────────────────────────────────────────────────
  bool _isTracking = false;
  String? _sessionId;
  DateTime? _startedAt;
  double _totalDistanceM = 0;
  double _currentSpeedKmh = 0;
  int _calories = 0;
  int _pointCount = 0;
  Position? _lastPos;
  DateTime? _lastMovementAt; // last time speed exceeded threshold

  Duration get _elapsed => _startedAt != null
      ? DateTime.now().toUtc().difference(_startedAt!)
      : Duration.zero;

  // ── Services ─────────────────────────────────────────────────────────────────
  final _auth = AuthService();
  final _notifications = FlutterLocalNotificationsPlugin();
  Database? _db;
  bool _notifReady = false;

  // ── Subscriptions / timers ──────────────────────────────────────────────────
  StreamSubscription<Position>? _posSub;
  Timer? _notifTimer;
  Timer? _stationaryTimer;

  // ── Public stream ──────────────────────────────────────────────────────────
  final StreamController<TrackingStats> _statsCtrl =
      StreamController<TrackingStats>.broadcast();

  /// Broadcast stream of live stats; emit every [_kNotifIntervalSec] seconds.
  Stream<TrackingStats> get statsStream => _statsCtrl.stream;

  bool get isTracking => _isTracking;

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Starts a new tracking session.
  ///
  /// - Checks/requests GPS permission via [LocationService].
  /// - Retries any pending unsynced sessions from previous runs.
  /// - Starts GPS stream, notification, stationary watcher.
  ///
  /// Throws [StateError] if already tracking.
  /// Throws [Exception] if GPS permission not granted.
  Future<void> startTracking() async {
    if (_isTracking) throw StateError('Already tracking');

    // Ensure GPS permission
    final status =
        await LocationService.instance.checkAndRequestPermission();
    if (!status.isGranted) {
      throw Exception(status.message);
    }

    await _initDb();
    await _initNotifications();

    // Sync any sessions that failed to upload previously
    _syncPendingSessions().ignore();

    // New session
    _sessionId = 'session_${DateTime.now().millisecondsSinceEpoch}';
    _startedAt = DateTime.now().toUtc();
    _totalDistanceM = 0;
    _currentSpeedKmh = 0;
    _calories = 0;
    _pointCount = 0;
    _lastPos = null;
    _lastMovementAt = _startedAt;

    await _createSession(_sessionId!);

    // Start GPS via LocationService (manages foreground service on Android)
    final stream = LocationService.instance.startTracking(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
    _posSub = stream.listen(
      _onPosition,
      onError: (Object e) => debugPrint('[BGTracking] GPS error: $e'),
      cancelOnError: false,
    );

    _isTracking = true;

    // Notification: update every N seconds
    _notifTimer = Timer.periodic(
      const Duration(seconds: _kNotifIntervalSec),
      (_) {
        _updateNotification();
        _emitStats();
      },
    );

    // Stationary detection: check every minute
    _stationaryTimer = Timer.periodic(
      const Duration(seconds: _kStationaryCheckSec),
      (_) => _checkStationary(),
    );

    _updateNotification();
    debugPrint('[BGTracking] Started session $_sessionId');
  }

  /// Stops the current session.
  ///
  /// Saves final data, cancels all subscriptions, dismisses notification,
  /// attempts backend sync.
  ///
  /// Returns [TrackingStats] with the final session data,
  /// or `null` if not currently tracking.
  Future<TrackingStats?> stopTracking() async {
    if (!_isTracking || _sessionId == null) return null;

    final sessionId = _sessionId!;
    final elapsed = _elapsed;
    final distanceM = _totalDistanceM;
    final calories = _calories;
    final pointCount = _pointCount;

    _posSub?.cancel();
    _posSub = null;
    _notifTimer?.cancel();
    _notifTimer = null;
    _stationaryTimer?.cancel();
    _stationaryTimer = null;

    LocationService.instance.stopTracking();

    _isTracking = false;
    _sessionId = null;

    await _finalizeSession(
      sessionId: sessionId,
      distanceM: distanceM,
      durationS: elapsed.inSeconds,
      calories: calories,
    );

    await _dismissNotification();

    final synced = await _syncSession(sessionId);

    final stats = TrackingStats(
      sessionId: sessionId,
      elapsed: elapsed,
      distanceM: distanceM,
      speedKmh: 0,
      calories: calories,
      pointCount: pointCount,
      isTracking: false,
      isSynced: synced,
    );

    if (!_statsCtrl.isClosed) _statsCtrl.add(stats);
    debugPrint('[BGTracking] Stopped session $sessionId — synced=$synced');
    return stats;
  }

  /// Returns an in-memory snapshot of the current session stats.
  /// Safe to call at any time; returns zeroed stats if not tracking.
  TrackingStats getCurrentStats() {
    return TrackingStats(
      sessionId: _sessionId ?? '',
      elapsed: _elapsed,
      distanceM: _totalDistanceM,
      speedKmh: _currentSpeedKmh,
      calories: _calories,
      pointCount: _pointCount,
      isTracking: _isTracking,
    );
  }

  /// Releases DB and stream resources. Call only on full app shutdown.
  Future<void> dispose() async {
    await stopTracking();
    await _db?.close();
    _db = null;
    await _statsCtrl.close();
  }

  // ─── GPS handler ─────────────────────────────────────────────────────────────

  void _onPosition(Position pos) {
    if (!_isTracking) return;

    // Accumulate distance
    if (_lastPos != null) {
      final delta = Geolocator.distanceBetween(
        _lastPos!.latitude, _lastPos!.longitude,
        pos.latitude, pos.longitude,
      );
      // Ignore GPS jumps > 200 m in a single 5 m filtered update (noise)
      if (delta < 200) {
        _totalDistanceM += delta;
      }
    }
    _lastPos = pos;

    // Speed
    _currentSpeedKmh =
        (pos.speed.isFinite && pos.speed > 0) ? pos.speed * 3.6 : 0;

    // Stationary tracking
    if (pos.speed > _kStationarySpeedThreshold) {
      _lastMovementAt = DateTime.now();
    }

    // Calories: 70 kcal/km (70 kg mixed activity)
    _calories = (_totalDistanceM / 1000 * 70).round();
    _pointCount++;

    // Persist to SQLite
    _insertPoint(_sessionId!, pos).ignore();
  }

  // ─── Stationary detection ─────────────────────────────────────────────────────

  void _checkStationary() {
    if (!_isTracking || _lastMovementAt == null) return;
    final idle =
        DateTime.now().difference(_lastMovementAt!).inMinutes;
    if (idle >= _kStationaryMinutes) {
      debugPrint(
          '[BGTracking] Stationary $idle min — auto-stopping session');
      stopTracking();
    }
  }

  // ─── Stats emit ──────────────────────────────────────────────────────────────

  void _emitStats() {
    if (_statsCtrl.isClosed) return;
    _statsCtrl.add(getCurrentStats());
  }

  // ─── Database ────────────────────────────────────────────────────────────────

  Future<Database> _openDb() async {
    // Wave 15 — encrypted via SQLCipher. GPS tracks are sensitive location
    // history; encrypting prevents `adb backup` leakage on debug builds.
    return SecureDb.instance.openEncryptedOrRecreate(
      dbName: _kDbName,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_kSessionsTable (
            session_id TEXT PRIMARY KEY,
            started_at TEXT NOT NULL,
            stopped_at TEXT,
            distance_m REAL NOT NULL DEFAULT 0,
            duration_s INTEGER NOT NULL DEFAULT 0,
            calories INTEGER NOT NULL DEFAULT 0,
            is_synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE $_kPointsTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            lat REAL NOT NULL,
            lng REAL NOT NULL,
            accuracy REAL,
            speed REAL,
            altitude REAL,
            heading REAL,
            recorded_at TEXT NOT NULL,
            FOREIGN KEY (session_id) REFERENCES $_kSessionsTable (session_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_points_session ON $_kPointsTable (session_id)',
        );
      },
    );
  }

  Future<void> _initDb() async {
    _db ??= await _openDb();
  }

  Future<void> _createSession(String sessionId) async {
    await _db!.insert(_kSessionsTable, {
      'session_id': sessionId,
      'started_at': _startedAt!.toIso8601String(),
      'distance_m': 0.0,
      'duration_s': 0,
      'calories': 0,
      'is_synced': 0,
    });
  }

  Future<void> _insertPoint(String sessionId, Position pos) async {
    if (_db == null) return;
    try {
      await _db!.insert(_kPointsTable, {
        'session_id': sessionId,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'speed': pos.speed,
        'altitude': pos.altitude,
        'heading': pos.heading,
        'recorded_at': DateTime.fromMillisecondsSinceEpoch(
          pos.timestamp.millisecondsSinceEpoch,
          isUtc: true,
        ).toIso8601String(),
      });
    } catch (e) {
      debugPrint('[BGTracking] DB insert error: $e');
    }
  }

  Future<void> _finalizeSession({
    required String sessionId,
    required double distanceM,
    required int durationS,
    required int calories,
  }) async {
    if (_db == null) return;
    await _db!.update(
      _kSessionsTable,
      {
        'stopped_at': DateTime.now().toUtc().toIso8601String(),
        'distance_m': distanceM,
        'duration_s': durationS,
        'calories': calories,
      },
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<Map<String, Object?>>> _getSessionPoints(
      String sessionId) async {
    if (_db == null) return [];
    return _db!.query(
      _kPointsTable,
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
  }

  Future<List<Map<String, Object?>>> _getUnsyncedSessions() async {
    if (_db == null) return [];
    return _db!.query(
      _kSessionsTable,
      where: 'is_synced = 0 AND stopped_at IS NOT NULL',
      orderBy: 'started_at ASC',
      limit: 10,
    );
  }

  Future<void> _markSynced(String sessionId) async {
    if (_db == null) return;
    await _db!.update(
      _kSessionsTable,
      {'is_synced': 1},
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  // ─── Backend sync ─────────────────────────────────────────────────────────────

  /// Tries to upload [sessionId] to the backend.
  /// Returns `true` on success; `false` on any error (session stays in DB).
  Future<bool> _syncSession(String sessionId) async {
    try {
      if (_db == null) await _initDb();

      final rows = await _db!.query(
        _kSessionsTable,
        where: 'session_id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final session = rows.first;
      if (session['stopped_at'] == null) return false;

      final points = await _getSessionPoints(sessionId);

      final token = await _auth.getAccessToken();
      if (token == null) return false;

      final res = await http
          .post(
            Uri.parse('$v1Base/activities'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'route_points': points
                  .map((r) => {'lat': r['lat'], 'lng': r['lng']})
                  .toList(),
              'distance_m': (session['distance_m'] as num?)?.toInt() ?? 0,
              'duration_s': session['duration_s'] ?? 0,
              'calories': session['calories'] ?? 0,
              'started_at': session['started_at'],
              'ended_at': session['stopped_at'],
            }),
          )
          .withTimeout();

      if (res.statusCode == 200 || res.statusCode == 201) {
        await _markSynced(sessionId);
        debugPrint('[BGTracking] Synced session $sessionId');
        return true;
      } else {
        debugPrint(
            '[BGTracking] Sync failed ${res.statusCode}: ${res.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[BGTracking] Sync error for $sessionId: $e');
      return false;
    }
  }

  /// Syncs all unsynced completed sessions in background.
  Future<void> _syncPendingSessions() async {
    if (_db == null) return;
    try {
      final unsynced = await _getUnsyncedSessions();
      for (final session in unsynced) {
        final id = session['session_id'] as String;
        await _syncSession(id);
      }
    } catch (e) {
      debugPrint('[BGTracking] Pending sync error: $e');
    }
  }

  // ─── Notifications ─────────────────────────────────────────────────────────────

  Future<void> _initNotifications() async {
    if (_notifReady) return;
    if (kIsWeb) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notifications.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );

    // Create the Android notification channel (idempotent)
    if (Platform.isAndroid) {
      final androidPlugin =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kNotifChannelId,
          _kNotifChannelName,
          description: 'Live distance and duration while recording.',
          importance: Importance.low, // silent — no sound or heads-up
        ),
      );
    }

    _notifReady = true;
  }

  void _updateNotification() {
    if (!_notifReady || kIsWeb) return;
    final km = (_totalDistanceM / 1000).toStringAsFixed(2);
    final dur = getCurrentStats().durationLabel;
    _showNotification(
      title: 'ZVELT tracking activ • $km km',
      body: '$dur · ${_currentSpeedKmh.toStringAsFixed(1)} km/h',
    );
  }

  void _showNotification({required String title, required String body}) {
    _notifications
        .show(
          id: _kNotifId,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _kNotifChannelId,
              _kNotifChannelName,
              channelDescription: 'Live distance and duration while recording.',
              importance: Importance.low,
              priority: Priority.low,
              ongoing: true,
              autoCancel: false,
              showWhen: false,
              icon: '@mipmap/ic_launcher',
              color: Color(0xFFC8F53C),
              colorized: false,
              category: AndroidNotificationCategory.service,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: false,
              presentBadge: false,
              presentSound: false,
            ),
          ),
        )
        .ignore();
  }

  Future<void> _dismissNotification() async {
    if (!_notifReady || kIsWeb) return;
    await _notifications.cancel(id: _kNotifId);
  }
}

