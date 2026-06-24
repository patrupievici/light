import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:http/http.dart' as http;

import '../config/api_config.dart' show v1Base;
import '../config/platform_info.dart' show isAndroid, isIos;
import '_crash_reporter.dart';
import 'auth_service.dart';
import 'secure_db.dart';
import 'wearable_provider_client.dart';
import 'workout_service.dart';

class HealthSummary {
  const HealthSummary({
    required this.stepsToday,
    required this.caloriesToday,
    required this.sleepLastNight,
    required this.workoutsThisWeek,
    required this.stepXpToday,
    this.avgHeartRateBpm,
    this.restingHeartRateBpm,
    this.bloodOxygenPercent,
    this.weightKg,
    this.leanBodyMassKg,
    this.bodyFatPercent,
    this.hrvRmssdMs,
    this.hrvBaselineLowMs,
    this.hrvBaselineHighMs,
    this.rhrBaselineLowBpm,
    this.rhrBaselineHighBpm,
    this.estimatedVo2Max,
  });

  final int stepsToday;
  final double caloriesToday;
  final double sleepLastNight;
  final List<HealthWorkout> workoutsThisWeek;
  final int stepXpToday;
  final double? avgHeartRateBpm;
  final double? restingHeartRateBpm;
  final double? bloodOxygenPercent;
  final double? weightKg;
  final double? leanBodyMassKg;
  final double? bodyFatPercent;
  final double? hrvRmssdMs;
  final double? hrvBaselineLowMs;
  final double? hrvBaselineHighMs;
  final double? rhrBaselineLowBpm;
  final double? rhrBaselineHighBpm;
  final double? estimatedVo2Max;

  static const HealthSummary empty = HealthSummary(
    stepsToday: 0,
    caloriesToday: 0,
    sleepLastNight: 0,
    workoutsThisWeek: [],
    stepXpToday: 0,
  );
}

class DailyStepsDatum {
  const DailyStepsDatum({required this.dayStart, required this.steps});
  final DateTime dayStart;
  final int steps;
}

class DailyBurnedCaloriesDatum {
  const DailyBurnedCaloriesDatum({
    required this.dayStart,
    required this.caloriesBurned,
  });
  final DateTime dayStart;
  final double caloriesBurned;
}

class HealthWorkout {
  const HealthWorkout({
    required this.type,
    required this.startTime,
    required this.endTime,
    required this.calories,
  });

  final String type;
  final DateTime startTime;
  final DateTime endTime;
  final double calories;

  Duration get duration => endTime.difference(startTime);
}

class SleepDetails {
  const SleepDetails({
    required this.totalHours,
    this.deepHours = 0,
    this.remHours = 0,
    this.lightHours = 0,
    this.awakeHours = 0,
    this.sessionStart,
    this.sessionEnd,
  });
  final double totalHours;
  final double deepHours;
  final double remHours;
  final double lightHours;
  final double awakeHours;
  final DateTime? sessionStart;
  final DateTime? sessionEnd;

  bool get hasStages => deepHours > 0 || remHours > 0 || lightHours > 0;

  // Sleep time / (sleep time + awake time)
  double get efficiency {
    final total = deepHours + remHours + lightHours + awakeHours;
    if (total <= 0) return 1.0;
    return ((total - awakeHours) / total).clamp(0.0, 1.0);
  }
}

/// Wave 8 — abstracted Health Connect / HealthKit availability state.
/// `notApplicable` is returned on iOS (HealthKit ships with the OS).
enum HealthConnectStatus { notInstalled, updateRequired, ready, notApplicable }

/// Wave 8 — local DB row for a single imported Health Connect / HealthKit
/// sample. Mirrors the columns of `health_imported_records`.
@immutable
class HealthImportedRecord {
  const HealthImportedRecord({
    required this.id,
    required this.uuid,
    required this.type,
    required this.startAt,
    required this.endAt,
    required this.value,
    required this.unit,
    required this.sourceApp,
    required this.sourcePath,
    required this.provider,
    required this.externalId,
    required this.payloadJson,
  });

  final int id;
  final String uuid;
  final String type;
  final DateTime startAt;
  final DateTime endAt;
  final double? value;
  final String unit;
  final String sourceApp;
  final String sourcePath;
  final String provider;
  final String externalId;
  final String payloadJson;

  factory HealthImportedRecord.fromRow(Map<String, Object?> r) =>
      HealthImportedRecord(
        id: r['id'] as int,
        uuid: r['uuid'] as String,
        type: r['type'] as String,
        startAt: DateTime.parse(r['start_at'] as String),
        endAt: DateTime.parse(r['end_at'] as String),
        value: (r['value'] as num?)?.toDouble(),
        unit: (r['unit'] as String?) ?? '',
        sourceApp: (r['source_app'] as String?) ?? '',
        sourcePath: (r['source_path'] as String?) ?? 'health_connect',
        provider: (r['provider'] as String?) ?? '',
        externalId: (r['external_id'] as String?) ?? (r['uuid'] as String),
        payloadJson: (r['payload_json'] as String?) ?? '{}',
      );
}

int stepsToXp(int steps) {
  if (steps >= 10000) return 50;
  if (steps >= 7500) return 35;
  if (steps >= 5000) return 20;
  if (steps >= 2500) return 10;
  return 0;
}

/// Canonical `metricType` string the BACKEND keys on, derived from the locally
/// stored `HealthDataType.name` (e.g. `STEPS`, `RESTING_HEART_RATE`). The server
/// stores/dedups by this normalized type (see `health-dedup.ts` — `steps`,
/// `heart_rate`, `sleep`, `weight`, …), so the push must speak the same
/// vocabulary or every sample would land under a distinct, un-deduped type.
/// Unknown/future types fall back to a lower-cased form so nothing is silently
/// dropped. Pure + side-effect free so it can be unit-tested.
String healthMetricTypeFor(String storedType) {
  switch (storedType) {
    case 'STEPS':
      return 'steps';
    case 'TOTAL_CALORIES_BURNED':
    case 'ACTIVE_ENERGY_BURNED':
    case 'BASAL_ENERGY_BURNED':
      // Collapse the energy variants to one metric; the unit + value stay
      // canonical (kcal) so the server can still tell them apart by window.
      return storedType == 'ACTIVE_ENERGY_BURNED'
          ? 'active_energy'
          : storedType == 'BASAL_ENERGY_BURNED'
              ? 'basal_energy'
              : 'calories';
    case 'HEART_RATE':
      return 'heart_rate';
    case 'RESTING_HEART_RATE':
      return 'resting_heart_rate';
    case 'HEART_RATE_VARIABILITY_RMSSD':
    case 'HEART_RATE_VARIABILITY_SDNN':
      // Both are HRV in ms; one canonical metric, the original sub-type is kept
      // verbatim in the local payload/audit, not in the rolled-up metricType.
      return 'hrv';
    case 'BLOOD_OXYGEN':
      return 'blood_oxygen';
    case 'RESPIRATORY_RATE':
      return 'respiratory_rate';
    case 'WEIGHT':
      return 'weight';
    case 'HEIGHT':
      return 'height';
    case 'LEAN_BODY_MASS':
      return 'lean_body_mass';
    case 'BODY_FAT_PERCENTAGE':
      return 'body_fat';
    case 'FLIGHTS_CLIMBED':
      return 'flights_climbed';
    case 'DISTANCE_DELTA':
    case 'DISTANCE_WALKING_RUNNING':
      return 'distance';
    case 'SLEEP_SESSION':
    case 'SLEEP_ASLEEP':
      return 'sleep';
    default:
      return storedType.toLowerCase();
  }
}

/// Canonical unit string for a server-bound sample. The `health` plugin reports
/// SI/metric values already (kg for weight, bpm for HR, ms for HRV, kcal for
/// energy, metres for distance), so this NORMALIZES the unit LABEL only — it
/// never rescales the value, preserving canonical metric storage. Falls back to
/// the plugin's own unit string lower-cased when unmapped. Pure.
String canonicalHealthUnit(String metricType, String storedUnit) {
  switch (metricType) {
    case 'steps':
    case 'flights_climbed':
      return 'count';
    case 'calories':
    case 'active_energy':
    case 'basal_energy':
      return 'kcal';
    case 'heart_rate':
    case 'resting_heart_rate':
      return 'bpm';
    case 'hrv':
      return 'ms';
    case 'blood_oxygen':
    case 'body_fat':
      return 'percent';
    case 'respiratory_rate':
      return 'breaths_per_min';
    case 'weight':
    case 'lean_body_mass':
      return 'kg';
    case 'height':
      return 'm';
    case 'distance':
      return 'm';
    case 'sleep':
      return 'hours';
    default:
      final u = storedUnit.trim();
      return u.isEmpty ? 'unit' : u.toLowerCase();
  }
}

/// Build the exact JSON-able array POSTed to `POST /v1/me/health/import` from a
/// page of locally cached [records]. Pure (no clock/network/DB) so it can be
/// unit-tested in isolation. Each element is
/// `{metricType, value, unit, startAt, endAt, source, externalId}`:
///  - `metricType` / `unit` are canonicalized so the server dedups correctly,
///  - `startAt` / `endAt` are UTC ISO-8601 (the server parses Dates),
///  - `externalId` is the row's STABLE id so re-pushes upsert (idempotency),
///  - `source` is the on-device path label (`health_connect` / `healthkit`).
/// Null values are kept (the server can store a window-only sample); only rows
/// with no usable `externalId` are skipped, since those can't be deduped.
List<Map<String, Object?>> buildHealthImportRows(
  Iterable<HealthImportedRecord> records, {
  required String source,
}) {
  final out = <Map<String, Object?>>[];
  for (final r in records) {
    final externalId = r.externalId.isNotEmpty ? r.externalId : r.uuid;
    if (externalId.isEmpty) continue; // can't be deduped server-side; skip.
    final metricType = healthMetricTypeFor(r.type);
    out.add(<String, Object?>{
      'metricType': metricType,
      'value': r.value,
      'unit': canonicalHealthUnit(metricType, r.unit),
      'startAt': r.startAt.toUtc().toIso8601String(),
      'endAt': r.endAt.toUtc().toIso8601String(),
      'source': source,
      'externalId': externalId,
    });
  }
  return out;
}

double? _numericFromPoint(HealthDataPoint point) {
  final value = point.value;
  if (value is NumericHealthValue) {
    return value.numericValue.toDouble();
  }
  return null;
}

/// Hours of wall-clock time covered by [points], counting overlapping
/// intervals ONCE. Health Connect aggregates the same sleep night from every
/// installed source (Mi Fitness, Google, etc.), so each night arrives as
/// several overlapping SLEEP_SESSION records — summing their durations raw
/// double/triple-counts (e.g. a real 7h night reported as "27h"). Merging the
/// intervals first makes each minute asleep count once.
double _unionDurationHours(Iterable<HealthDataPoint> points) {
  final ranges = [
    for (final p in points)
      if (p.dateTo.isAfter(p.dateFrom)) (from: p.dateFrom, to: p.dateTo),
  ]..sort((a, b) => a.from.compareTo(b.from));
  if (ranges.isEmpty) return 0;
  var totalMinutes = 0;
  var curFrom = ranges.first.from;
  var curTo = ranges.first.to;
  for (final r in ranges.skip(1)) {
    if (!r.from.isAfter(curTo)) {
      // Overlapping or contiguous → extend the current merged interval.
      if (r.to.isAfter(curTo)) curTo = r.to;
    } else {
      totalMinutes += curTo.difference(curFrom).inMinutes;
      curFrom = r.from;
      curTo = r.to;
    }
  }
  totalMinutes += curTo.difference(curFrom).inMinutes;
  return totalMinutes / 60.0;
}

double? _averageNumeric(Iterable<HealthDataPoint> points) {
  var sum = 0.0;
  var count = 0;
  for (final point in points) {
    final value = _numericFromPoint(point);
    if (value == null) continue;
    sum += value;
    count++;
  }
  return count > 0 ? sum / count : null;
}

double? _latestNumericByTime(Iterable<HealthDataPoint> points) {
  final sorted = points.toList()
    ..sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
  for (final point in sorted) {
    final value = _numericFromPoint(point);
    if (value != null) return value;
  }
  return null;
}

double? _minNumeric(Iterable<HealthDataPoint> points) {
  double? min;
  for (final point in points) {
    final value = _numericFromPoint(point);
    if (value == null) continue;
    min = min == null ? value : (value < min ? value : min);
  }
  return min;
}

double? _maxNumeric(Iterable<HealthDataPoint> points) {
  double? max;
  for (final point in points) {
    final value = _numericFromPoint(point);
    if (value == null) continue;
    max = max == null ? value : (value > max ? value : max);
  }
  return max;
}

/// Value at [fraction] (0..1) of the sorted numeric values — e.g. 0.05 is the
/// 5th percentile. Used to estimate resting HR from instantaneous HEART_RATE
/// samples without a single stray low beat skewing it (a raw min would).
double? _percentileNumeric(Iterable<HealthDataPoint> points, double fraction) {
  final values = <double>[];
  for (final point in points) {
    final value = _numericFromPoint(point);
    if (value != null) values.add(value);
  }
  if (values.isEmpty) return null;
  values.sort();
  final idx =
      (fraction * (values.length - 1)).round().clamp(0, values.length - 1);
  return values[idx];
}

class HealthService {
  HealthService._();
  static final HealthService instance = HealthService._();

  final Health _health = Health();

  /// HRV type the active platform exposes. iOS HealthKit only stores SDNN
  /// (`HEART_RATE_VARIABILITY_SDNN`); Android Health Connect only stores RMSSD
  /// (`HEART_RATE_VARIABILITY_RMSSD`). Requesting the wrong one silently
  /// returns empty — the old code requested RMSSD unconditionally, so iOS HRV
  /// (and thus Recovery on iOS) was always dead. Both are mirrored in the
  /// plugin's `dataTypeKeysIOS` / `dataTypeKeysAndroid`.
  static HealthDataType get _hrvType => isIos
      ? HealthDataType.HEART_RATE_VARIABILITY_SDNN
      : HealthDataType.HEART_RATE_VARIABILITY_RMSSD;

  /// Distance type the active platform exposes. Android Health Connect models
  /// total distance as `DISTANCE_DELTA`; iOS HealthKit as
  /// `DISTANCE_WALKING_RUNNING`. (Both → Android perm `READ_DISTANCE`.)
  static HealthDataType get _distanceType => isIos
      ? HealthDataType.DISTANCE_WALKING_RUNNING
      : HealthDataType.DISTANCE_DELTA;

  /// Sleep-stage types to authorize so Health Connect / HealthKit actually
  /// offer consent for them (read in [getSleepDetails]). All map to the single
  /// already-declared `READ_SLEEP` Android permission. Platform-aware because
  /// `SLEEP_SESSION` / `SLEEP_OUT_OF_BED` / `SLEEP_UNKNOWN` exist only on
  /// Android, while iOS exposes its own stage subset.
  static List<HealthDataType> get _sleepStageTypes => isIos
      ? const [
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.SLEEP_DEEP,
          HealthDataType.SLEEP_REM,
          HealthDataType.SLEEP_LIGHT,
          HealthDataType.SLEEP_AWAKE,
          HealthDataType.SLEEP_AWAKE_IN_BED,
          HealthDataType.SLEEP_IN_BED,
        ]
      : const [
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.SLEEP_DEEP,
          HealthDataType.SLEEP_REM,
          HealthDataType.SLEEP_LIGHT,
          HealthDataType.SLEEP_AWAKE,
          HealthDataType.SLEEP_AWAKE_IN_BED,
          HealthDataType.SLEEP_OUT_OF_BED,
          HealthDataType.SLEEP_UNKNOWN,
        ];

  /// Full set of types we authorize, PLATFORM-AWARE so we never request a type
  /// the plugin can't satisfy on the running platform (that throws on read /
  /// breaks the authorization request). Built additively from a shared base
  /// plus platform-specific entries; [_permissions] is the index-matched
  /// READ/READ_WRITE list. iOS exposes `SLEEP_ASLEEP`-style stages rather than
  /// the Android `SLEEP_SESSION` aggregate, so the sleep aggregate type is
  /// Android-only and iOS leans on the stage list for session totals.
  static List<HealthDataType> get _types {
    final types = <HealthDataType>[
      HealthDataType.STEPS,
      HealthDataType.TOTAL_CALORIES_BURNED,
      HealthDataType.ACTIVE_ENERGY_BURNED,
      HealthDataType.BASAL_ENERGY_BURNED,
      HealthDataType.WORKOUT, // READ_WRITE (Zvelt also writes workouts)
      HealthDataType.HEART_RATE,
      HealthDataType.RESTING_HEART_RATE,
      HealthDataType.BLOOD_OXYGEN,
      _hrvType,
      HealthDataType.RESPIRATORY_RATE,
      HealthDataType.WEIGHT,
      HealthDataType.HEIGHT,
      HealthDataType.LEAN_BODY_MASS,
      HealthDataType.BODY_FAT_PERCENTAGE,
      HealthDataType.FLIGHTS_CLIMBED,
      _distanceType,
      if (isAndroid) HealthDataType.SLEEP_SESSION,
      ..._sleepStageTypes,
    ];
    return types;
  }

  /// READ/READ_WRITE flags, index-matched to [_types]. Only [HealthDataType.WORKOUT]
  /// needs READ_WRITE (Zvelt writes finished workouts back); everything else is
  /// READ-only.
  static List<HealthDataAccess> get _permissions => [
        for (final t in _types)
          t == HealthDataType.WORKOUT
              ? HealthDataAccess.READ_WRITE
              : HealthDataAccess.READ,
      ];

  /// The minimal READ set the app actually needs to be "connected" (steps +
  /// energy + sleep + heart rate drive strain/recovery/vitals). Checked
  /// instead of the full [_types] list because Health Connect grants are
  /// PARTIAL by design: the consent screen may omit niche types the device
  /// doesn't support (LEAN_BODY_MASS, HRV…) and write permissions.
  ///
  /// The old behavior caused the "connected in onboarding, disconnected on
  /// next launch" bug: the plugin's requestAuthorization returns true when
  /// ANY permission is granted, but hasPermissions used containsAll over
  /// all 11 types — so a normal partial grant passed the first check and
  /// failed the second forever.
  static const _coreTypes = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.HEART_RATE,
  ];
  static final _corePermissions =
      List<HealthDataAccess>.filled(_coreTypes.length, HealthDataAccess.READ);

  Future<bool> requestPermissions() async {
    await _health.configure();
    try {
      final granted =
          await _health.requestAuthorization(_types, permissions: _permissions);
      if (!granted) return false;
      // The plugin reports true on ANY grant — confirm the core set so the
      // "Connected" state we show survives the next hasPermissions() probe.
      final ok = await hasPermissions();
      if (ok) {
        // GDPR: record an auditable, verifiable consent the moment the user
        // actually grants OS health access. Fire-and-forget — never block the
        // connect flow on the ledger write.
        unawaited(recordConsent(granted: true));
      }
      return ok;
    } catch (e, st) {
      reportError(e, st, reason: 'health:request-permissions');
      return false;
    }
  }

  /// Persist a verifiable health-data consent decision to the backend ledger
  /// (GDPR Art. 7). Best-effort; failures are reported, never thrown.
  Future<void> recordConsent({required bool granted}) async {
    try {
      final token = await AuthService().getAccessToken();
      if (token == null) return;
      final source = isAndroid ? 'health_connect' : 'healthkit';
      await http
          .post(
            Uri.parse('$v1Base/me/health-consents'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'consents': [
                {'consentType': 'all', 'granted': granted, 'source': source},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e, st) {
      reportError(e, st, reason: 'health:record-consent');
    }
  }

  Future<bool> hasPermissions() async {
    await _health.configure();
    try {
      final result =
          await _health.hasPermissions(_coreTypes, permissions: _corePermissions);
      // Android answers true/false. iOS returns null for READ checks
      // (HealthKit never discloses read grants) — same pre-existing
      // null→false mapping as before, unchanged by this fix.
      return result ?? false;
    } catch (e, st) {
      reportError(e, st, reason: 'health:has-permissions');
      return false;
    }
  }

  /// One guarded read. Health Connect throws SecurityException for any type
  /// the user didn't grant — with PARTIAL grants being the platform norm,
  /// a niche refusal (e.g. body fat) must cost only that one metric, not
  /// the whole summary. (Before this, getSummary was a single try/catch and
  /// one missing grant returned HealthSummary.empty.)
  Future<List<HealthDataPoint>> _readSafe(
    HealthDataType type,
    DateTime start,
    DateTime end,
  ) async {
    try {
      final pts = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: end,
        types: [type],
      );
      debugPrint('[HealthService] read ${type.name} '
          '${start.toIso8601String()}..${end.toIso8601String()} '
          '-> ${pts.length} pts');
      return pts;
    } catch (e) {
      // Distinguish "not granted" (SecurityException) from "no data". Expected
      // for non-granted types — log only (no crash report each call) so device
      // logcat can tell a partial-grant bug apart from genuine sync latency.
      debugPrint('[HealthService] read ${type.name} THREW: $e');
      return const <HealthDataPoint>[];
    }
  }

  Future<HealthSummary> getSummary() async {
    await _health.configure();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(const Duration(days: 7));
    final baselineStart = todayStart.subtract(const Duration(days: 14));
    final monthStart = todayStart.subtract(const Duration(days: 30));

    try {
      final sleepStart = DateTime(now.year, now.month, now.day - 1, 20);
      final sleepEnd = DateTime(now.year, now.month, now.day, 12);

      // Fire all independent reads concurrently; each already swallows its own
      // errors (_readSafe / the steps try-catch below), so Future.wait never
      // rejects. Dependent steps (resting fallback, vo2) run afterwards.
      final stepsFuture = () async {
        try {
          final s = await _health.getTotalStepsInInterval(todayStart, now) ?? 0;
          debugPrint('[HealthService] steps today=$s '
              '(${todayStart.toIso8601String()}..${now.toIso8601String()})');
          return s;
        } catch (e) {
          // Steps not granted — keep 0, the rest of the summary still loads.
          debugPrint('[HealthService] steps read THREW: $e');
          return 0;
        }
      }();
      final caloriePointsFuture =
          _readSafe(HealthDataType.TOTAL_CALORIES_BURNED, todayStart, now);
      final sleepPointsFuture =
          _readSafe(HealthDataType.SLEEP_SESSION, sleepStart, sleepEnd);
      final workoutPointsFuture =
          _readSafe(HealthDataType.WORKOUT, weekStart, now);
      final hrTodayFuture =
          _readSafe(HealthDataType.HEART_RATE, todayStart, now);
      final restingPointsFuture =
          _readSafe(HealthDataType.RESTING_HEART_RATE, baselineStart, now);
      final spo2PointsFuture =
          _readSafe(HealthDataType.BLOOD_OXYGEN, weekStart, now);
      // Platform-aware: SDNN on iOS, RMSSD on Android (see [_hrvType]). The
      // summary field stays named hrvRmssdMs for back-compat, but on iOS it now
      // carries SDNN — both are HRV in ms, which is what Recovery consumes.
      final hrvPointsFuture = _readSafe(_hrvType, baselineStart, now);
      final weightPointsFuture =
          _readSafe(HealthDataType.WEIGHT, monthStart, now);
      final leanMassPointsFuture =
          _readSafe(HealthDataType.LEAN_BODY_MASS, monthStart, now);
      final bodyFatPointsFuture =
          _readSafe(HealthDataType.BODY_FAT_PERCENTAGE, monthStart, now);

      final steps = await stepsFuture;
      final caloriePoints = await caloriePointsFuture;
      final sleepPoints = await sleepPointsFuture;
      final workoutPoints = await workoutPointsFuture;
      final hrToday = await hrTodayFuture;
      final restingPoints = await restingPointsFuture;
      final spo2Points = await spo2PointsFuture;
      final hrvPoints = await hrvPointsFuture;
      final weightPoints = await weightPointsFuture;
      final leanMassPoints = await leanMassPointsFuture;
      final bodyFatPoints = await bodyFatPointsFuture;

      var calories = 0.0;
      for (final point in caloriePoints) {
        final value = _numericFromPoint(point);
        if (value != null) calories += value;
      }

      // Merge overlapping sessions (multiple Health sources write the same
      // night) so we don't double-count — raw summing produced "27h" nights.
      final sleepHours = _unionDurationHours(sleepPoints);

      final workouts = <HealthWorkout>[];
      for (final point in workoutPoints) {
        final value = point.value;
        if (value is! WorkoutHealthValue) continue;
        workouts.add(
          HealthWorkout(
            type: value.workoutActivityType.name,
            startTime: point.dateFrom,
            endTime: point.dateTo,
            calories: value.totalEnergyBurned?.toDouble() ?? 0,
          ),
        );
      }

      final avgHr = _averageNumeric(hrToday);

      var resting = _latestNumericByTime(restingPoints);
      final rhrLow = _minNumeric(restingPoints);
      final rhrHigh = _maxNumeric(restingPoints);

      // Fallback for bands that write instantaneous HEART_RATE but never
      // RESTING_HEART_RATE (Xiaomi/Mi Fitness, many others) — without this the
      // Resting HR tile is permanently empty for those users. Estimate resting
      // HR as the 5th-percentile of the last ~36h of HR samples (≈ overnight
      // rest); a low percentile (not the raw min) ignores stray single beats.
      if (resting == null) {
        final hrSamples = await _readSafe(
            HealthDataType.HEART_RATE, now.subtract(const Duration(hours: 36)), now);
        final est = _percentileNumeric(hrSamples, 0.05);
        if (hrSamples.length >= 10 && est != null && est >= 35 && est <= 110) {
          resting = est;
        }
      }

      final spo2 = _latestNumericByTime(spo2Points);

      final hrvLatest = _latestNumericByTime(hrvPoints);
      final hrvLow = _minNumeric(hrvPoints);
      final hrvHigh = _maxNumeric(hrvPoints);

      final weight = _latestNumericByTime(weightPoints);

      final leanMass = _latestNumericByTime(leanMassPoints);

      final bodyFat = _latestNumericByTime(bodyFatPoints);

      double? vo2Estimate;
      if (resting != null) {
        final trainingBoost = workouts.length.clamp(0, 7) * 1.2;
        final sleepBoost = sleepHours > 0 ? ((sleepHours.clamp(5.0, 9.0) - 5.0) / 4.0) * 3.0 : 0.0;
        final hrvBoost = hrvLatest != null ? ((hrvLatest.clamp(15.0, 110.0) - 15.0) / 95.0) * 6.0 : 0.0;
        final recoveryBase = 52.0 - (resting.clamp(42.0, 90.0) - 42.0) * 0.42;
        vo2Estimate = (recoveryBase + trainingBoost + sleepBoost + hrvBoost).clamp(24.0, 64.0);
      }

      return HealthSummary(
        stepsToday: steps,
        caloriesToday: calories,
        sleepLastNight: sleepHours,
        workoutsThisWeek: workouts,
        stepXpToday: stepsToXp(steps),
        avgHeartRateBpm: avgHr,
        restingHeartRateBpm: resting,
        bloodOxygenPercent: spo2,
        weightKg: weight,
        leanBodyMassKg: leanMass,
        bodyFatPercent: bodyFat,
        hrvRmssdMs: hrvLatest,
        hrvBaselineLowMs: hrvLow,
        hrvBaselineHighMs: hrvHigh,
        rhrBaselineLowBpm: rhrLow,
        rhrBaselineHighBpm: rhrHigh,
        estimatedVo2Max: vo2Estimate,
      );
    } catch (e, st) {
      reportError(e, st, reason: 'health:get-summary');
      return HealthSummary.empty;
    }
  }

  Future<HealthConnectSdkStatus?> getHealthConnectSdkStatus() async {
    if (!isAndroid) return HealthConnectSdkStatus.sdkAvailable;
    await _health.configure();
    return _health.getHealthConnectSdkStatus();
  }

  Future<void> openHealthConnectInStore() async {
    await _health.installHealthConnect();
  }

  Future<List<DailyStepsDatum>> getDailyStepsHistory({int days = 14}) async {
    await _health.configure();
    final totalDays = days.clamp(1, 90);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final output = <DailyStepsDatum>[];
    try {
      // Oldest → newest day starts, preserving the original output order.
      final dayStarts = <DateTime>[
        for (var i = totalDays - 1; i >= 0; i--)
          todayStart.subtract(Duration(days: i)),
      ];
      const chunkSize = 3;
      for (var i = 0; i < dayStarts.length; i += chunkSize) {
        final chunk = dayStarts.skip(i).take(chunkSize).toList();
        final results = await Future.wait(chunk.map((start) async {
          final end = start.add(const Duration(days: 1));
          final steps = await _health.getTotalStepsInInterval(start, end) ?? 0;
          return DailyStepsDatum(dayStart: start, steps: steps);
        }));
        output.addAll(results);
      }
    } catch (e, st) {
      reportError(e, st, reason: 'health:daily-steps-history');
      return <DailyStepsDatum>[];
    }
    return output;
  }

  Future<bool> writeWorkoutToHealth(WorkoutDto workout) async {
    if (workout.endedAt == null) return false;
    await _health.configure();
    try {
      final durationMin = workout.endedAt!.difference(workout.startedAt).inMinutes;
      final estimatedCalories = (durationMin * 5.0).clamp(0, 9999);
      return await _health.writeWorkoutData(
        activityType: HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
        start: workout.startedAt,
        end: workout.endedAt!,
        totalEnergyBurned: estimatedCalories.toInt(),
        totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
      );
    } catch (e, st) {
      reportError(e, st, reason: 'health:write-workout');
      return false;
    }
  }

  Future<List<DailyBurnedCaloriesDatum>> getDailyCaloriesBurnedHistory({int days = 14}) async {
    await _health.configure();
    final totalDays = days.clamp(1, 90);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final output = <DailyBurnedCaloriesDatum>[];
    try {
      for (var i = totalDays - 1; i >= 0; i--) {
        final start = todayStart.subtract(Duration(days: i));
        final end = start.add(const Duration(days: 1));
        final caloriePoints = await _health.getHealthDataFromTypes(
          startTime: start,
          endTime: end,
          types: const [HealthDataType.TOTAL_CALORIES_BURNED],
        );
        var calories = 0.0;
        for (final point in caloriePoints) {
          final value = _numericFromPoint(point);
          if (value != null) calories += value;
        }
        output.add(DailyBurnedCaloriesDatum(dayStart: start, caloriesBurned: calories));
      }
    } catch (e, st) {
      reportError(e, st, reason: 'health:daily-calories-history');
      return <DailyBurnedCaloriesDatum>[];
    }
    return output;
  }

  // ===========================================================================
  // Health import cache — reliable recent backfill + incremental sync.
  // ===========================================================================

  /// Per-network-call ceiling. Health Connect / HealthKit reads on a year-wide
  /// window can stall on cold caches; we never want to hang the worker.
  static const Duration _kCallTimeout = Duration(seconds: 30);

  /// Read-only types iterated by the backfill / incremental sync. Subset of
  /// [_types] minus WORKOUT (already written by Zvelt itself — round-tripping
  /// our own writes would double-count) and minus the per-stage SLEEP_* types
  /// (the SLEEP_SESSION aggregate on Android / SLEEP_ASLEEP on iOS already
  /// captures the night; stage rows would multiply row counts). Platform-aware
  /// for the same reason [_types] is — reading an unavailable type throws.
  static List<HealthDataType> get _historyTypes => [
        HealthDataType.STEPS,
        HealthDataType.TOTAL_CALORIES_BURNED,
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.BASAL_ENERGY_BURNED,
        if (isAndroid)
          HealthDataType.SLEEP_SESSION
        else
          HealthDataType.SLEEP_ASLEEP,
        HealthDataType.HEART_RATE,
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.BLOOD_OXYGEN,
        _hrvType,
        HealthDataType.RESPIRATORY_RATE,
        HealthDataType.WEIGHT,
        HealthDataType.HEIGHT,
        HealthDataType.LEAN_BODY_MASS,
        HealthDataType.BODY_FAT_PERCENTAGE,
        HealthDataType.FLIGHTS_CLIMBED,
        _distanceType,
      ];

  /// Permission-revocation flag observable by the UI (Health tab settings
  /// banner). Set by [appForegrounded] when [hasPermissions] flips to false.
  final ValueNotifier<bool> permissionsRevoked = ValueNotifier<bool>(false);

  // sqflite handle for `health_imported_records`.
  Database? _localDb;

  static const String _kBackfillDoneKey = 'health_backfill_done';
  // v2: bumped from v1 so existing users (who ran the old 7-day backfill) get
  // the wider 90-day historical pull below on next connect.
  static const String _kRecentBackfillDoneKey = 'health_recent_backfill_done_v2';
  static const String _kAnchorPrefix = 'health_anchor_';
  // Last local row id (autoincrement PK) pushed to POST /v1/me/health/import.
  // The cursor only advances on a confirmed 2xx, so a failed/offline push is
  // simply retried next run (offline-tolerant); the stable externalId per row
  // makes the server upsert/ignore re-pushes (idempotent).
  static const String _kPushCursorKey = 'health_push_cursor_id';
  // Rows per network call — keeps each POST small enough for the worker timeout
  // and bounds memory while still draining a fresh backfill in a few rounds.
  static const int _kPushBatchSize = 200;
  // Safety bound on rounds per invocation so a huge first backfill can't spin
  // the worker indefinitely; the leftover drains on subsequent runs.
  static const int _kMaxPushRoundsPerRun = 25;
  static const String _kDbName = 'zvelt_health_records.db';
  static const String _kTable = 'health_imported_records';
  // ~3 months. requestHistoricalAccess() unlocks reads past the Android 14+
  // 30-day cap so this window actually returns historical rows.
  static const Duration kRecentBackfillWindow = Duration(days: 90);

  Future<Database> _openDb() async {
    if (_localDb != null) return _localDb!;
    // Wave 15 — encrypted via SQLCipher. Health data (steps, HR, sleep,
    // weight, body fat) is the most sensitive on-device row set, so this
    // is the headline DB the encryption migration was built for.
    _localDb = await SecureDb.instance.openEncryptedOrRecreate(
      dbName: _kDbName,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_kTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT NOT NULL UNIQUE,
            type TEXT NOT NULL,
            start_at TEXT NOT NULL,
            end_at TEXT NOT NULL,
            value REAL,
            unit TEXT,
            source_app TEXT,
            source_path TEXT NOT NULL DEFAULT 'health_connect',
            provider TEXT,
            external_id TEXT,
            payload_json TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_health_type_end ON $_kTable (type, end_at)',
        );
        await db.execute(
          'CREATE INDEX idx_health_source_type_time ON $_kTable (source_path, provider, type, start_at, end_at)',
        );
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE $_kTable ADD COLUMN source_path TEXT NOT NULL DEFAULT 'health_connect'",
          );
          await db.execute("ALTER TABLE $_kTable ADD COLUMN provider TEXT");
          await db.execute("ALTER TABLE $_kTable ADD COLUMN external_id TEXT");
          await db.execute(
            'CREATE INDEX idx_health_source_type_time ON $_kTable (source_path, provider, type, start_at, end_at)',
          );
        }
      },
    );
    return _localDb!;
  }

  /// Android-only: request the `READ_HEALTH_DATA_HISTORY` Health Connect
  /// permission so reads can return data older than 30 days (mandatory on
  /// Android 14+). Returns true on iOS unconditionally — HealthKit has no
  /// equivalent 30-day cap. Verified against `health: 13.3.1` —
  /// `requestHealthDataHistoryAuthorization()` is the exact method name.
  Future<bool> requestHistoricalAccess() async {
    if (!isAndroid) return true;
    try {
      await _health.configure();
      final already = await _health
          .isHealthDataHistoryAuthorized()
          .timeout(_kCallTimeout, onTimeout: () => false);
      if (already) {
        debugPrint('[HealthService] history already authorized');
        return true;
      }
      final granted = await _health
          .requestHealthDataHistoryAuthorization()
          .timeout(_kCallTimeout, onTimeout: () => false);
      debugPrint('[HealthService] history grant requested -> $granted');
      return granted;
    } catch (e) {
      debugPrint('[HealthService] requestHistoricalAccess error: $e');
      return false;
    }
  }

  /// Map the plugin's [HealthConnectSdkStatus] to our UI-facing enum. iOS
  /// returns [HealthConnectStatus.notApplicable] (HealthKit is always present).
  Future<HealthConnectStatus> checkAvailability() async {
    if (!isAndroid) return HealthConnectStatus.notApplicable;
    try {
      await _health.configure();
      final status = await _health
          .getHealthConnectSdkStatus()
          .timeout(_kCallTimeout, onTimeout: () => null);
      switch (status) {
        case HealthConnectSdkStatus.sdkAvailable:
          return HealthConnectStatus.ready;
        case HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired:
          return HealthConnectStatus.updateRequired;
        case HealthConnectSdkStatus.sdkUnavailable:
        case null:
          return HealthConnectStatus.notInstalled;
      }
    } catch (e) {
      debugPrint('[HealthService] checkAvailability error: $e');
      return HealthConnectStatus.notInstalled;
    }
  }

  /// One-shot historical backfill used immediately after permission grant.
  ///
  /// Pulls [kRecentBackfillWindow] (~90 days) of on-device Health Connect /
  /// HealthKit history. On Android 14+ this first requests
  /// `READ_HEALTH_DATA_HISTORY` (via [requestHistoricalAccess]); without it the
  /// platform silently clips reads to the last 30 days. Per-type anchor
  /// (`health_anchor_<typeName>`) is set to the latest record's `endTime` (or
  /// the window end if no rows came back) so subsequent syncs read only deltas.
  Future<int> backfillRecentOnFirstGrant({
    Duration window = kRecentBackfillWindow,
  }) async {
    // Android 14+ caps Health Connect reads at 30 days unless the app holds
    // READ_HEALTH_DATA_HISTORY. Request it first (advisory — no-op on older
    // Android and on iOS) so the 90-day window below returns real history
    // instead of silently coming back empty.
    await requestHistoricalAccess();
    return _backfillOnce(
      doneKey: _kRecentBackfillDoneKey,
      window: window,
      sourcePath: _onDeviceSourcePath,
    );
  }

  /// Backward-compatible entry point used by older call sites. This used to
  /// attempt 365 days; it now delegates to the reliable recent window. Request
  /// `READ_HEALTH_DATA_HISTORY` explicitly only for a future advanced import.
  Future<void> backfillOnFirstGrant({
    Duration window = kRecentBackfillWindow,
  }) async {
    await _backfillOnce(
      doneKey: _kBackfillDoneKey,
      window: window,
      sourcePath: _onDeviceSourcePath,
    );
  }

  Future<int> _backfillOnce({
    required String doneKey,
    required Duration window,
    required HealthSourcePath sourcePath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(doneKey) == true) return 0;

    try {
      await _health.configure();
    } catch (e) {
      debugPrint('[HealthService] backfill configure error: $e');
      return 0;
    }

    final end = DateTime.now();
    final start = end.subtract(window);
    var inserted = 0;

    const chunkSize = 3;
    for (var i = 0; i < _historyTypes.length; i += chunkSize) {
      final chunk = _historyTypes.skip(i).take(chunkSize).toList();
      final counts = await Future.wait(chunk.map((t) => _fetchAndPersistRange(
            type: t,
            start: start,
            end: end,
            prefs: prefs,
            sourcePath: sourcePath,
          )));
      inserted += counts.fold<int>(0, (a, b) => a + b);
    }

    // Only mark the one-shot backfill "done" once we actually imported
    // something. A first connect that happens BEFORE Samsung Health has synced
    // into Health Connect would otherwise burn the one-shot flag against an
    // empty store and leave the 90-day history permanently blank. Leaving the
    // flag unset lets the next connect/sync retry the backfill.
    if (inserted > 0) {
      await prefs.setBool(doneKey, true);
      debugPrint(
        '[HealthService] recent backfill complete for ${_historyTypes.length} types, inserted=$inserted',
      );
    } else {
      debugPrint(
        '[HealthService] recent backfill imported 0 rows — NOT marking done; '
        'will retry on next connect/sync (likely Samsung not yet synced)',
      );
    }
    return inserted;
  }

  /// Pull anchor → now for every type, dedupe by UUID (INSERT OR IGNORE),
  /// update anchors. Returns the count of newly inserted rows so the caller
  /// (background worker / UI) can decide whether to push a "synced X records"
  /// snackbar.
  Future<int> incrementalSync() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _health.configure();
    } catch (e) {
      debugPrint('[HealthService] incrementalSync configure error: $e');
      return 0;
    }
    // Best-effort: ensure the 30-day no-anchor fallback below isn't clipped to
    // 30 days by the Android 14+ history cap. requestHistoricalAccess()
    // short-circuits (no dialog) when already authorized and is fully guarded,
    // so a background isolate without an Activity simply returns false.
    await requestHistoricalAccess();
    final end = DateTime.now();
    var inserted = 0;
    for (final type in _historyTypes) {
      final anchorKey = '$_kAnchorPrefix${type.name}';
      final anchorStr = prefs.getString(anchorKey);
      // No anchor yet (or a corrupt one) → reach back 30 days so a device that
      // missed periodic syncs (e.g. ColorOS killing background work) still
      // catches up a meaningful window, not just the last 24h.
      final fallback = end.subtract(const Duration(days: 30));
      final start = anchorStr != null
          ? (DateTime.tryParse(anchorStr) ?? fallback)
          : fallback;
      if (!start.isBefore(end)) continue;
      inserted += await _fetchAndPersistRange(
        type: type,
        start: start,
        end: end,
        prefs: prefs,
        sourcePath: _onDeviceSourcePath,
      );
    }
    debugPrint('[HealthService] incrementalSync inserted=$inserted');
    return inserted;
  }

  /// Source label sent to `POST /v1/me/health/import` for on-device samples.
  /// Matches the values [recordConsent] already uses so the backend ties an
  /// import back to the same consent ledger entry.
  String get _onDevicePushSource => isAndroid ? 'health_connect' : 'healthkit';

  /// Push locally cached on-device health samples to the backend so wearable
  /// data reaches the server (today the cache is device-only). Best-effort and
  /// non-throwing: any failure is reported/logged and swallowed so it never
  /// blocks the UI or a background worker.
  ///
  /// Does NOT read the device — it drains rows already imported by
  /// [incrementalSync] / [backfillRecentOnFirstGrant] into the local cache, so
  /// existing on-device read behavior is completely untouched. It is:
  ///  - incremental — a per-device cursor ([_kPushCursorKey], the last pushed
  ///    autoincrement row id) means each run sends only rows added since,
  ///  - idempotent — every row carries a STABLE `externalId`, so the server can
  ///    dedup/upsert re-pushes (a crash between POST-success and cursor-write
  ///    just re-sends already-stored rows),
  ///  - offline-tolerant — the cursor advances only after a confirmed 2xx, so a
  ///    network failure leaves it untouched and the batch retries next run.
  ///
  /// Returns the number of rows the server accepted this invocation.
  Future<int> pushHealthImportsToServer() async {
    try {
      final token = await AuthService().getAccessToken();
      if (token == null) return 0; // signed out — nothing to push, retry later.

      final prefs = await SharedPreferences.getInstance();
      final source = _onDevicePushSource;
      final uri = Uri.parse('$v1Base/me/health/import');
      var cursor = prefs.getInt(_kPushCursorKey) ?? 0;
      var pushed = 0;

      for (var round = 0; round < _kMaxPushRoundsPerRun; round++) {
        final rows = await _readRecordsAfterId(cursor, _kPushBatchSize);
        if (rows.isEmpty) break;

        final body = buildHealthImportRows(rows, source: source);
        // Every row in the page was filtered out (e.g. null value + no
        // external id). Still advance past them so we don't re-scan forever.
        if (body.isEmpty) {
          cursor = rows.last.id;
          await prefs.setInt(_kPushCursorKey, cursor);
          if (rows.length < _kPushBatchSize) break;
          continue;
        }

        final resp = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({'samples': body}),
            )
            .timeout(_kCallTimeout);

        // Only advance the cursor on success; anything else is left for the
        // next run (offline-tolerant). 4xx other than auth is treated as
        // "won't succeed on retry of this exact batch" only if it's a client
        // payload error — but to stay safe and idempotent we simply stop and
        // retry later, since re-pushing is harmless (stable externalId).
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          pushed += body.length;
          cursor = rows.last.id;
          await prefs.setInt(_kPushCursorKey, cursor);
          if (rows.length < _kPushBatchSize) break;
        } else {
          debugPrint(
            '[HealthService] health import push got HTTP ${resp.statusCode} '
            '— leaving cursor at $cursor, will retry next run',
          );
          break;
        }
      }

      if (pushed > 0) {
        debugPrint('[HealthService] pushed $pushed health rows to server '
            '(cursor now $cursor)');
      }
      return pushed;
    } catch (e, st) {
      // Never throw up into the UI / worker — wearable push is best-effort.
      reportError(e, st, reason: 'health:push-imports');
      return 0;
    }
  }

  /// Cached rows with `id > afterId`, oldest id first, capped at [limit]. Drives
  /// the incremental [pushHealthImportsToServer] cursor walk. The autoincrement
  /// id is monotonic for insertion order, so ascending-by-id is a stable cursor
  /// even as new rows arrive mid-sync.
  Future<List<HealthImportedRecord>> _readRecordsAfterId(
    int afterId,
    int limit,
  ) async {
    try {
      final db = await _openDb();
      final rows = await db.query(
        _kTable,
        where: 'id > ?',
        whereArgs: [afterId],
        orderBy: 'id ASC',
        limit: limit,
      );
      return rows.map(HealthImportedRecord.fromRow).toList(growable: false);
    } catch (e) {
      debugPrint('[HealthService] _readRecordsAfterId error: $e');
      return const <HealthImportedRecord>[];
    }
  }

  /// Fetch a single type for [start..end] and write deduped rows to sqflite.
  /// Updates the per-type anchor to the latest `dateTo` seen (or [end] if no
  /// rows). Returns the count of rows actually inserted (after UUID dedup).
  Future<int> _fetchAndPersistRange({
    required HealthDataType type,
    required DateTime start,
    required DateTime end,
    required SharedPreferences prefs,
    required HealthSourcePath sourcePath,
  }) async {
    final anchorKey = '$_kAnchorPrefix${type.name}';
    try {
      final rawRecords = await _health
          .getHealthDataFromTypes(
            startTime: start,
            endTime: end,
            types: [type],
          )
          .timeout(_kCallTimeout, onTimeout: () => const <HealthDataPoint>[]);
      final records = _health.removeDuplicates(rawRecords);

      if (records.isEmpty) {
        await prefs.setString(anchorKey, end.toIso8601String());
        return 0;
      }

      final db = await _openDb();
      var inserted = 0;
      DateTime latest = start;
      await db.transaction((txn) async {
        for (final r in records) {
          final value = _numericFromPoint(r);
          final externalId = _externalIdFor(r, value);
          final provider = _providerFromSourceName(r.sourceName);
          final rowId = await txn.insert(
            _kTable,
            {
              'uuid': externalId,
              'type': r.typeString,
              'start_at': r.dateFrom.toIso8601String(),
              'end_at': r.dateTo.toIso8601String(),
              'value': value,
              'unit': r.unitString,
              'source_app': r.sourceName,
              'source_path': _sourcePathKey(sourcePath),
              'provider': provider,
              'external_id': externalId,
              'payload_json': jsonEncode(r.toJson()),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          if (rowId > 0) inserted++;
          if (r.dateTo.isAfter(latest)) latest = r.dateTo;
        }
      });

      await prefs.setString(anchorKey, latest.toIso8601String());
      return inserted;
    } on TimeoutException catch (_) {
      debugPrint('[HealthService] fetch timeout for ${type.name}');
      return 0;
    } catch (e) {
      debugPrint('[HealthService] fetch error for ${type.name}: $e');
      return 0;
    }
  }

  String _externalIdFor(HealthDataPoint point, double? value) {
    if (point.uuid.isNotEmpty) return point.uuid;
    final stable = [
      _sourcePathKey(_onDeviceSourcePath),
      point.sourceName,
      point.typeString,
      point.dateFrom.toUtc().toIso8601String(),
      point.dateTo.toUtc().toIso8601String(),
      value?.toStringAsFixed(6) ?? '',
      point.unitString,
    ].join('|');
    return 'hc:${base64Url.encode(utf8.encode(stable))}';
  }

  String _sourcePathKey(HealthSourcePath sourcePath) {
    switch (sourcePath) {
      case HealthSourcePath.appleHealth:
        return 'apple_health';
      case HealthSourcePath.healthConnect:
        return 'health_connect';
      case HealthSourcePath.aggregator:
        return 'aggregator';
      case HealthSourcePath.huaweiHealthKit:
        return 'huawei_health_kit';
      case HealthSourcePath.manualBridge:
        return 'manual_bridge';
      case HealthSourcePath.manualEntry:
        return 'manual_entry';
    }
  }

  HealthSourcePath get _onDeviceSourcePath =>
      isAndroid ? HealthSourcePath.healthConnect : HealthSourcePath.appleHealth;

  String _providerFromSourceName(String sourceName) {
    final s = sourceName.toLowerCase();
    if (s.contains('samsung')) return 'samsung_health';
    if (s.contains('garmin')) return 'garmin';
    if (s.contains('fitbit')) return 'fitbit';
    if (s.contains('google')) return 'google_health';
    if (s.contains('oura')) return 'oura';
    if (s.contains('polar')) return 'polar';
    if (s.contains('coros')) return 'coros';
    if (s.contains('whoop')) return 'whoop';
    if (s.contains('suunto')) return 'suunto';
    if (s.contains('withings')) return 'withings';
    if (s.contains('zepp') || s.contains('amazfit')) return 'amazfit';
    if (s.contains('huawei')) return 'huawei_health';
    if (s.trim().isEmpty) return 'unknown';
    return s.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'_+$'), '');
  }

  /// Page in the imported records cache (newest end_at first). Convenience for
  /// the Health tab's "Imported history" detail screen (no UI changes here).
  Future<List<HealthImportedRecord>> readImportedRecords({
    HealthDataType? type,
    int limit = 200,
    int offset = 0,
  }) async {
    try {
      final db = await _openDb();
      final rows = await db.query(
        _kTable,
        where: type != null ? 'type = ?' : null,
        whereArgs: type != null ? [type.name] : null,
        orderBy: 'end_at DESC',
        limit: limit,
        offset: offset,
      );
      return rows.map(HealthImportedRecord.fromRow).toList(growable: false);
    } catch (e) {
      debugPrint('[HealthService] readImportedRecords error: $e');
      return const <HealthImportedRecord>[];
    }
  }

  /// Call from `AppLifecycleState.resumed`. Detects silent revocation in
  /// Settings → Apps → Health Connect, surfacing it through
  /// [permissionsRevoked] so the UI can prompt the user to reconnect.
  Future<void> appForegrounded() async {
    try {
      final ok = await hasPermissions().timeout(
        _kCallTimeout,
        onTimeout: () => true, // don't false-alarm on slow probes
      );
      permissionsRevoked.value = !ok;
    } catch (e) {
      debugPrint('[HealthService] appForegrounded error: $e');
    }
  }

  Future<SleepDetails?> getSleepDetails() async {
    await _health.configure();
    final now = DateTime.now();
    final sleepStart = DateTime(now.year, now.month, now.day - 1, 18);
    final sleepEnd = DateTime(now.year, now.month, now.day, 14);
    try {
      final sessionPoints = await _health.getHealthDataFromTypes(
        startTime: sleepStart,
        endTime: sleepEnd,
        types: const [HealthDataType.SLEEP_SESSION],
      );
      if (sessionPoints.isEmpty) return null;
      // Merge overlapping sessions from multiple Health sources (raw summing
      // reported impossible totals like 27h). Window span uses min/max.
      final totalHours = _unionDurationHours(sessionPoints);
      DateTime? earliest, latest;
      for (final p in sessionPoints) {
        if (earliest == null || p.dateFrom.isBefore(earliest)) earliest = p.dateFrom;
        if (latest == null || p.dateTo.isAfter(latest)) latest = p.dateTo;
      }
      if (totalHours <= 0) return null;
      var deepH = 0.0, remH = 0.0, lightH = 0.0, awakeH = 0.0;
      try {
        // Read the full platform-aware stage set ([_sleepStageTypes]); both
        // SLEEP_AWAKE and SLEEP_AWAKE_IN_BED count as awake time.
        final stagePoints = await _health.getHealthDataFromTypes(
          startTime: sleepStart,
          endTime: sleepEnd,
          types: _sleepStageTypes,
        );
        for (final p in stagePoints) {
          final h = p.dateTo.difference(p.dateFrom).inMinutes / 60.0;
          if (p.type == HealthDataType.SLEEP_DEEP) {
            deepH += h;
          } else if (p.type == HealthDataType.SLEEP_REM) {
            remH += h;
          } else if (p.type == HealthDataType.SLEEP_LIGHT) {
            lightH += h;
          } else if (p.type == HealthDataType.SLEEP_AWAKE ||
              p.type == HealthDataType.SLEEP_AWAKE_IN_BED) {
            awakeH += h;
          }
        }
      } catch (e, st) {
        reportError(e, st, reason: 'health:sleep-stages');
      }
      return SleepDetails(
        totalHours: totalHours,
        deepHours: deepH,
        remHours: remH,
        lightHours: lightH,
        awakeHours: awakeH,
        sessionStart: earliest,
        sessionEnd: latest,
      );
    } catch (e, st) {
      reportError(e, st, reason: 'health:get-sleep-details');
      return null;
    }
  }
}
