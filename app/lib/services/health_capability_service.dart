import 'package:flutter/foundation.dart';

import '../config/platform_info.dart' show isAndroid, isIos;
import 'health_service.dart';
import 'wearable_provider_client.dart';

enum HealthRouteKind {
  appleHealth,
  healthConnectReady,
  healthConnectInstall,
  healthConnectUpdate,
  cloudAggregatorRecommended,
  unsupported,
}

class HealthRouteRecommendation {
  const HealthRouteRecommendation({
    required this.kind,
    required this.primarySourcePath,
    required this.title,
    required this.message,
    required this.canUseOnDeviceHealth,
    required this.shouldOfferCloudAggregator,
  });

  final HealthRouteKind kind;
  final HealthSourcePath primarySourcePath;
  final String title;
  final String message;
  final bool canUseOnDeviceHealth;
  final bool shouldOfferCloudAggregator;
}

class HealthCapabilityService {
  HealthCapabilityService({HealthService? health})
      : _health = health ?? HealthService.instance;

  final HealthService _health;

  Future<HealthRouteRecommendation> resolvePrimaryRoute() async {
    if (kIsWeb) {
      return const HealthRouteRecommendation(
        kind: HealthRouteKind.unsupported,
        primarySourcePath: HealthSourcePath.manualEntry,
        title: 'Mobile health only',
        message: 'Health data import is available from the mobile app.',
        canUseOnDeviceHealth: false,
        shouldOfferCloudAggregator: false,
      );
    }

    if (isIos) {
      return const HealthRouteRecommendation(
        kind: HealthRouteKind.appleHealth,
        primarySourcePath: HealthSourcePath.appleHealth,
        title: 'Apple Health',
        message: 'Use Apple Health for on-device health and wearable data.',
        canUseOnDeviceHealth: true,
        shouldOfferCloudAggregator: true,
      );
    }

    if (!isAndroid) {
      return const HealthRouteRecommendation(
        kind: HealthRouteKind.unsupported,
        primarySourcePath: HealthSourcePath.manualEntry,
        title: 'Unsupported platform',
        message: 'This platform does not expose a supported health data API.',
        canUseOnDeviceHealth: false,
        shouldOfferCloudAggregator: false,
      );
    }

    final status = await _health.checkAvailability();
    switch (status) {
      case HealthConnectStatus.ready:
        return const HealthRouteRecommendation(
          kind: HealthRouteKind.healthConnectReady,
          primarySourcePath: HealthSourcePath.healthConnect,
          title: 'Health Connect ready',
          message: 'Use Health Connect for the first foreground backfill.',
          canUseOnDeviceHealth: true,
          shouldOfferCloudAggregator: true,
        );
      case HealthConnectStatus.updateRequired:
        return const HealthRouteRecommendation(
          kind: HealthRouteKind.healthConnectUpdate,
          primarySourcePath: HealthSourcePath.healthConnect,
          title: 'Update Health Connect',
          message:
              'Update Health Connect, then use cloud wearable linking for reliability.',
          canUseOnDeviceHealth: false,
          shouldOfferCloudAggregator: true,
        );
      case HealthConnectStatus.notInstalled:
        return const HealthRouteRecommendation(
          kind: HealthRouteKind.healthConnectInstall,
          primarySourcePath: HealthSourcePath.aggregator,
          title: 'Health Connect unavailable',
          message:
              'Install Health Connect when possible, or use a cloud wearable link. Huawei phones without Google services need the cloud/HMS path.',
          canUseOnDeviceHealth: false,
          shouldOfferCloudAggregator: true,
        );
      case HealthConnectStatus.notApplicable:
        return const HealthRouteRecommendation(
          kind: HealthRouteKind.unsupported,
          primarySourcePath: HealthSourcePath.manualEntry,
          title: 'Health route unavailable',
          message: 'No on-device health route is available.',
          canUseOnDeviceHealth: false,
          shouldOfferCloudAggregator: true,
        );
    }
  }
}
