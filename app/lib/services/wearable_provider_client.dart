enum HealthMetricKind {
  steps,
  distance,
  activeEnergy,
  heartRate,
  restingHeartRate,
  hrv,
  sleep,
  workout,
  bloodOxygen,
  weight,
  bodyFat,
  leanBodyMass,
}

/// V1 keeps wearable/Health integrations out of the native build. This tiny
/// shape preserves provider abstractions for future wiring without pulling the
/// Android Health plugin into app startup.
class HealthDataPoint {
  const HealthDataPoint();
}

enum HealthSourcePath {
  appleHealth,
  healthConnect,
  aggregator,
  huaweiHealthKit,
  manualBridge,
  manualEntry,
}

enum WearableProvider {
  appleHealth,
  healthConnect,
  samsungHealth,
  garmin,
  fitbit,
  googleFit,
  oura,
  polar,
  coros,
  whoop,
  suunto,
  withings,
  amazfit,
  huaweiHealth,
  strava,
  wahoo,
}

enum ProviderAvailabilityState {
  available,
  needsInstall,
  needsUpdate,
  needsConfiguration,
  unsupported,
}

class ProviderAvailability {
  const ProviderAvailability({
    required this.state,
    required this.sourcePath,
    required this.message,
    this.provider,
  });

  final ProviderAvailabilityState state;
  final HealthSourcePath sourcePath;
  final String message;
  final WearableProvider? provider;

  bool get canRequestPermissions =>
      state == ProviderAvailabilityState.available;
}

class HealthBackfillBatch {
  const HealthBackfillBatch({
    required this.sourcePath,
    required this.metric,
    required this.from,
    required this.to,
    required this.points,
    this.provider,
  });

  final HealthSourcePath sourcePath;
  final WearableProvider? provider;
  final HealthMetricKind metric;
  final DateTime from;
  final DateTime to;
  final List<HealthDataPoint> points;
}

abstract class WearableProviderClient {
  HealthSourcePath get sourcePath;

  Future<ProviderAvailability> checkAvailability();

  Future<bool> requestPermissions(Set<HealthMetricKind> metrics);

  Future<List<HealthBackfillBatch>> backfill({
    required DateTime from,
    required DateTime to,
    required Set<HealthMetricKind> metrics,
  });

  Future<List<HealthBackfillBatch>> syncDelta({
    required DateTime since,
    required Set<HealthMetricKind> metrics,
  });
}

class WearableProviderInfo {
  const WearableProviderInfo({
    required this.provider,
    required this.label,
    required this.preferredSourcePath,
    required this.requiresCloudForBestResults,
    required this.notes,
  });

  final WearableProvider provider;
  final String label;
  final HealthSourcePath preferredSourcePath;
  final bool requiresCloudForBestResults;
  final String notes;
}

class WearableProviderCatalog {
  const WearableProviderCatalog._();

  static const providers = <WearableProviderInfo>[
    WearableProviderInfo(
      provider: WearableProvider.samsungHealth,
      label: 'Samsung Health / Galaxy Watch',
      preferredSourcePath: HealthSourcePath.healthConnect,
      requiresCloudForBestResults: false,
      notes: 'Samsung Health can write Galaxy Watch data into Health Connect.',
    ),
    WearableProviderInfo(
      provider: WearableProvider.garmin,
      label: 'Garmin Connect',
      preferredSourcePath: HealthSourcePath.aggregator,
      requiresCloudForBestResults: true,
      notes:
          'Use Health Connect for recent data when available; aggregator for deep history.',
    ),
    WearableProviderInfo(
      provider: WearableProvider.fitbit,
      label: 'Fitbit / Pixel Watch',
      preferredSourcePath: HealthSourcePath.aggregator,
      requiresCloudForBestResults: true,
      notes:
          'Health Connect can cover recent Android data; cloud link improves reliability.',
    ),
    WearableProviderInfo(
      provider: WearableProvider.oura,
      label: 'Oura',
      preferredSourcePath: HealthSourcePath.aggregator,
      requiresCloudForBestResults: true,
      notes: 'Aggregator usually exposes richer sleep and recovery history.',
    ),
    WearableProviderInfo(
      provider: WearableProvider.polar,
      label: 'Polar Flow',
      preferredSourcePath: HealthSourcePath.aggregator,
      requiresCloudForBestResults: true,
      notes:
          'Health Connect may cover recent data; cloud link is the durable path.',
    ),
    WearableProviderInfo(
      provider: WearableProvider.coros,
      label: 'COROS',
      preferredSourcePath: HealthSourcePath.aggregator,
      requiresCloudForBestResults: true,
      notes: 'Use aggregator for supported historical import windows.',
    ),
    WearableProviderInfo(
      provider: WearableProvider.whoop,
      label: 'WHOOP',
      preferredSourcePath: HealthSourcePath.aggregator,
      requiresCloudForBestResults: true,
      notes: 'Cloud OAuth is the expected path for reliable WHOOP data.',
    ),
    WearableProviderInfo(
      provider: WearableProvider.suunto,
      label: 'Suunto',
      preferredSourcePath: HealthSourcePath.aggregator,
      requiresCloudForBestResults: true,
      notes: 'Health Connect can help when the source app writes there.',
    ),
    WearableProviderInfo(
      provider: WearableProvider.withings,
      label: 'Withings',
      preferredSourcePath: HealthSourcePath.aggregator,
      requiresCloudForBestResults: true,
      notes: 'Cloud link is useful for scales, sleep, and historical data.',
    ),
    WearableProviderInfo(
      provider: WearableProvider.amazfit,
      label: 'Amazfit / Zepp',
      preferredSourcePath: HealthSourcePath.aggregator,
      requiresCloudForBestResults: true,
      notes:
          'Use Health Connect if Zepp writes there; otherwise cloud or bridge path.',
    ),
    WearableProviderInfo(
      provider: WearableProvider.huaweiHealth,
      label: 'Huawei Health',
      preferredSourcePath: HealthSourcePath.aggregator,
      requiresCloudForBestResults: true,
      notes:
          'Huawei needs aggregator support, Health Sync bridge, or a future HMS module.',
    ),
  ];

  static WearableProviderInfo? byProvider(WearableProvider provider) {
    for (final info in providers) {
      if (info.provider == provider) return info;
    }
    return null;
  }
}
