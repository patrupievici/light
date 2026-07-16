import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/config/revenuecat_config.dart';

void main() {
  group('RevenueCatConfig.isValidPublicSdkKey', () {
    test('accepts platform public keys and RevenueCat test keys', () {
      expect(
        RevenueCatConfig.isValidPublicSdkKey(
          'goog_1234567890',
          TargetPlatform.android,
        ),
        isTrue,
      );
      expect(
        RevenueCatConfig.isValidPublicSdkKey(
          'appl_1234567890',
          TargetPlatform.iOS,
        ),
        isTrue,
      );
      expect(
        RevenueCatConfig.isValidPublicSdkKey(
          'test_1234567890',
          TargetPlatform.android,
        ),
        isTrue,
      );
    });

    test('rejects blank, placeholder and cross-platform keys', () {
      expect(
        RevenueCatConfig.isValidPublicSdkKey('', TargetPlatform.android),
        isFalse,
      );
      expect(
        RevenueCatConfig.isValidPublicSdkKey(
          'REVENUECAT_ANDROID_API_KEY',
          TargetPlatform.android,
        ),
        isFalse,
      );
      expect(
        RevenueCatConfig.isValidPublicSdkKey(
          'appl_1234567890',
          TargetPlatform.android,
        ),
        isFalse,
      );
    });
  });
}
