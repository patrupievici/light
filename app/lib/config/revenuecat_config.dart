import 'package:flutter/foundation.dart';

/// Store-facing RevenueCat identifiers. Public SDK keys are supplied at build
/// time so no environment-specific value is committed to the repository.
abstract final class RevenueCatConfig {
  static const String androidApiKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_API_KEY',
  );
  static const String iosApiKey = String.fromEnvironment(
    'REVENUECAT_IOS_API_KEY',
  );

  static const String entitlementId = String.fromEnvironment(
    'REVENUECAT_ENTITLEMENT_ID',
    defaultValue: 'pro',
  );
  static const String monthlyProductId = String.fromEnvironment(
    'REVENUECAT_MONTHLY_PRODUCT_ID',
    defaultValue: 'zvelt_pro_monthly',
  );
  static const String annualProductId = String.fromEnvironment(
    'REVENUECAT_ANNUAL_PRODUCT_ID',
    defaultValue: 'zvelt_pro_annual',
  );

  static bool get supportsCurrentPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get currentApiKey {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return androidApiKey;
      case TargetPlatform.iOS:
        return iosApiKey;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return '';
    }
  }

  static bool get isConfiguredForCurrentPlatform =>
      supportsCurrentPlatform &&
      isValidPublicSdkKey(currentApiKey, defaultTargetPlatform);

  @visibleForTesting
  static bool isValidPublicSdkKey(String key, TargetPlatform platform) {
    final value = key.trim();
    if (value.startsWith('test_')) return value.length > 8;
    return switch (platform) {
      TargetPlatform.android => value.startsWith('goog_') && value.length > 9,
      TargetPlatform.iOS => value.startsWith('appl_') && value.length > 9,
      _ => false,
    };
  }
}
