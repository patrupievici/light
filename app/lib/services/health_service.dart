import 'package:flutter/foundation.dart';

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

  double get efficiency {
    final total = deepHours + remHours + lightHours + awakeHours;
    if (total <= 0) return 1.0;
    return ((total - awakeHours) / total).clamp(0.0, 1.0);
  }
}

enum HealthConnectStatus { notInstalled, updateRequired, ready, notApplicable }

enum HealthConnectSdkStatus {
  sdkAvailable,
  sdkUnavailableProviderUpdateRequired,
  sdkUnavailable,
}

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

String healthMetricTypeFor(String storedType) {
  switch (storedType) {
    case 'STEPS':
      return 'steps';
    case 'TOTAL_CALORIES_BURNED':
    case 'ACTIVE_ENERGY_BURNED':
    case 'BASAL_ENERGY_BURNED':
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
      final unit = storedUnit.trim();
      return unit.isEmpty ? 'unit' : unit.toLowerCase();
  }
}

List<Map<String, Object?>> buildHealthImportRows(
  Iterable<HealthImportedRecord> records, {
  required String source,
}) {
  final out = <Map<String, Object?>>[];
  for (final r in records) {
    final externalId = r.externalId.isNotEmpty ? r.externalId : r.uuid;
    if (externalId.isEmpty) continue;
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

class HealthService {
  HealthService._();

  static final HealthService instance = HealthService._();
  static const Duration kRecentBackfillWindow = Duration(days: 90);

  final ValueNotifier<bool> permissionsRevoked = ValueNotifier<bool>(false);

  Future<bool> requestPermissions() async => false;

  Future<void> recordConsent({required bool granted}) async {}

  Future<bool> hasPermissions() async => false;

  Future<HealthSummary> getSummary() async => HealthSummary.empty;

  Future<HealthConnectSdkStatus?> getHealthConnectSdkStatus() async =>
      HealthConnectSdkStatus.sdkUnavailable;

  Future<void> openHealthConnectInStore() async {}

  Future<List<DailyStepsDatum>> getDailyStepsHistory({int days = 14}) async =>
      const <DailyStepsDatum>[];

  Future<bool> writeWorkoutToHealth(WorkoutDto workout) async => false;

  Future<List<DailyBurnedCaloriesDatum>> getDailyCaloriesBurnedHistory({
    int days = 14,
  }) async =>
      const <DailyBurnedCaloriesDatum>[];

  Future<bool> requestHistoricalAccess() async => false;

  Future<HealthConnectStatus> checkAvailability() async =>
      HealthConnectStatus.notApplicable;

  Future<int> backfillRecentOnFirstGrant({
    Duration window = kRecentBackfillWindow,
  }) async =>
      0;

  Future<void> backfillOnFirstGrant({
    Duration window = kRecentBackfillWindow,
  }) async {}

  Future<int> incrementalSync() async => 0;

  Future<int> pushHealthImportsToServer() async => 0;

  Future<List<HealthImportedRecord>> readImportedRecords({
    Object? type,
    int limit = 200,
    int offset = 0,
  }) async =>
      const <HealthImportedRecord>[];

  Future<void> appForegrounded() async {
    permissionsRevoked.value = false;
  }

  Future<SleepDetails?> getSleepDetails() async => null;
}
