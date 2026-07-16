import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/revenuecat_config.dart';

class RevenueCatState {
  const RevenueCatState({
    required this.isSupported,
    required this.isConfigured,
    this.isLoading = false,
    this.isBusy = false,
    this.isPro = false,
    this.monthlyPackage,
    this.annualPackage,
    this.message,
  });

  factory RevenueCatState.initial() {
    final supported = RevenueCatConfig.supportsCurrentPlatform;
    final configured = RevenueCatConfig.isConfiguredForCurrentPlatform;
    return RevenueCatState(
      isSupported: supported,
      isConfigured: configured,
      isLoading: configured,
      message: supported
          ? configured
              ? null
              : 'Subscriptions are not configured for this build.'
          : 'Subscriptions are available on iOS and Android only.',
    );
  }

  final bool isSupported;
  final bool isConfigured;
  final bool isLoading;
  final bool isBusy;
  final bool isPro;
  final Package? monthlyPackage;
  final Package? annualPackage;
  final String? message;

  bool get hasProducts => monthlyPackage != null || annualPackage != null;

  int? get annualSavingsPercent {
    final monthly = monthlyPackage?.storeProduct.price;
    final annual = annualPackage?.storeProduct.price;
    if (monthly == null || annual == null || monthly <= 0 || annual <= 0) {
      return null;
    }
    final percent = ((1 - annual / (monthly * 12)) * 100).round();
    return percent > 0 && percent < 100 ? percent : null;
  }

  RevenueCatState copyWith({
    bool? isLoading,
    bool? isBusy,
    bool? isPro,
    Package? monthlyPackage,
    Package? annualPackage,
    String? message,
    bool clearMessage = false,
  }) {
    return RevenueCatState(
      isSupported: isSupported,
      isConfigured: isConfigured,
      isLoading: isLoading ?? this.isLoading,
      isBusy: isBusy ?? this.isBusy,
      isPro: isPro ?? this.isPro,
      monthlyPackage: monthlyPackage ?? this.monthlyPackage,
      annualPackage: annualPackage ?? this.annualPackage,
      message: clearMessage ? null : message ?? this.message,
    );
  }
}

class RevenueCatActionResult {
  const RevenueCatActionResult._({
    required this.succeeded,
    required this.cancelled,
    required this.message,
  });

  const RevenueCatActionResult.success(String message)
      : this._(succeeded: true, cancelled: false, message: message);

  const RevenueCatActionResult.cancelled()
      : this._(
          succeeded: false,
          cancelled: true,
          message: 'Purchase cancelled.',
        );

  const RevenueCatActionResult.failure(String message)
      : this._(succeeded: false, cancelled: false, message: message);

  final bool succeeded;
  final bool cancelled;
  final String message;
}

class RevenueCatService {
  RevenueCatService._();

  static final RevenueCatService instance = RevenueCatService._();

  final ValueNotifier<RevenueCatState> state =
      ValueNotifier<RevenueCatState>(RevenueCatState.initial());

  bool _listenerAttached = false;
  String? _identifiedUserId;
  Future<void>? _initializing;

  Future<void> identify(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty || !state.value.isConfigured) return;

    final activeInitialization = _initializing;
    if (activeInitialization != null) {
      await activeInitialization;
      if (_identifiedUserId == normalizedUserId) return;
    }

    final operation = _identifyInternal(normalizedUserId);
    _initializing = operation;
    try {
      await operation;
    } finally {
      if (identical(_initializing, operation)) _initializing = null;
    }
  }

  Future<void> _identifyInternal(String userId) async {
    state.value = state.value.copyWith(
      isLoading: true,
      clearMessage: true,
    );
    try {
      final alreadyConfigured = await Purchases.isConfigured;
      CustomerInfo? customerInfo;
      if (!alreadyConfigured) {
        final configuration =
            PurchasesConfiguration(RevenueCatConfig.currentApiKey)
              ..appUserID = userId;
        await Purchases.configure(configuration);
      } else if (_identifiedUserId != userId) {
        customerInfo = (await Purchases.logIn(userId)).customerInfo;
      }

      _identifiedUserId = userId;
      _attachListener();
      if (customerInfo != null) _applyCustomerInfo(customerInfo);
      await refresh();
    } catch (error, stackTrace) {
      debugPrint('[revenuecat] initialization failed: $error\n$stackTrace');
      state.value = state.value.copyWith(
        isLoading: false,
        message: _friendlyError(error),
      );
    }
  }

  void _attachListener() {
    if (_listenerAttached) return;
    Purchases.addCustomerInfoUpdateListener(_applyCustomerInfo);
    _listenerAttached = true;
  }

  Future<void> refresh() async {
    if (!state.value.isConfigured || _identifiedUserId == null) return;
    state.value = state.value.copyWith(isLoading: true, clearMessage: true);
    try {
      final results = await Future.wait<Object>([
        Purchases.getCustomerInfo(),
        Purchases.getOfferings(),
      ]);
      final customerInfo = results[0] as CustomerInfo;
      final offerings = results[1] as Offerings;
      final packages =
          offerings.current?.availablePackages ?? const <Package>[];
      final monthly = _selectPackage(
        packages,
        PackageType.monthly,
        RevenueCatConfig.monthlyProductId,
      );
      final annual = _selectPackage(
        packages,
        PackageType.annual,
        RevenueCatConfig.annualProductId,
      );

      final previous = state.value;
      state.value = RevenueCatState(
        isSupported: previous.isSupported,
        isConfigured: previous.isConfigured,
        isLoading: false,
        isBusy: previous.isBusy,
        isPro: _hasProEntitlement(customerInfo),
        monthlyPackage: monthly,
        annualPackage: annual,
        message: monthly == null && annual == null
            ? 'No subscription products are available for this store account.'
            : null,
      );
    } catch (error, stackTrace) {
      debugPrint('[revenuecat] refresh failed: $error\n$stackTrace');
      state.value = state.value.copyWith(
        isLoading: false,
        message: _friendlyError(error),
      );
    }
  }

  Future<RevenueCatActionResult> purchase({required bool annual}) async {
    final package =
        annual ? state.value.annualPackage : state.value.monthlyPackage;
    if (!state.value.isConfigured) {
      return const RevenueCatActionResult.failure(
        'Subscriptions are not configured for this build.',
      );
    }
    if (package == null) {
      return const RevenueCatActionResult.failure(
        'This subscription is not available for the current store account.',
      );
    }

    state.value = state.value.copyWith(isBusy: true, clearMessage: true);
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _applyCustomerInfo(result.customerInfo);
      state.value = state.value.copyWith(isBusy: false);
      if (_hasProEntitlement(result.customerInfo)) {
        return const RevenueCatActionResult.success('ZVELT Premium is active.');
      }
      return const RevenueCatActionResult.failure(
        'The store accepted the purchase, but Premium is still pending.',
      );
    } on PlatformException catch (error, stackTrace) {
      final code = _purchasesErrorCode(error);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        state.value = state.value.copyWith(isBusy: false);
        return const RevenueCatActionResult.cancelled();
      }
      debugPrint('[revenuecat] purchase failed: $error\n$stackTrace');
      final message = _friendlyError(error);
      state.value = state.value.copyWith(isBusy: false, message: message);
      return RevenueCatActionResult.failure(message);
    } catch (error, stackTrace) {
      debugPrint('[revenuecat] purchase failed: $error\n$stackTrace');
      final message = _friendlyError(error);
      state.value = state.value.copyWith(isBusy: false, message: message);
      return RevenueCatActionResult.failure(message);
    }
  }

  Future<RevenueCatActionResult> restore() async {
    if (!state.value.isConfigured) {
      return const RevenueCatActionResult.failure(
        'Subscriptions are not configured for this build.',
      );
    }
    state.value = state.value.copyWith(isBusy: true, clearMessage: true);
    try {
      final customerInfo = await Purchases.restorePurchases();
      _applyCustomerInfo(customerInfo);
      state.value = state.value.copyWith(isBusy: false);
      return _hasProEntitlement(customerInfo)
          ? const RevenueCatActionResult.success(
              'Your Premium subscription was restored.',
            )
          : const RevenueCatActionResult.failure(
              'No active Premium subscription was found for this store account.',
            );
    } catch (error, stackTrace) {
      debugPrint('[revenuecat] restore failed: $error\n$stackTrace');
      final message = _friendlyError(error);
      state.value = state.value.copyWith(isBusy: false, message: message);
      return RevenueCatActionResult.failure(message);
    }
  }

  Future<void> logOut() async {
    final wasIdentified = _identifiedUserId != null;
    _identifiedUserId = null;
    if (!state.value.isConfigured || !wasIdentified) {
      state.value = RevenueCatState.initial();
      return;
    }
    try {
      await Purchases.logOut();
    } catch (error, stackTrace) {
      debugPrint('[revenuecat] logout failed: $error\n$stackTrace');
    } finally {
      state.value = RevenueCatState.initial();
    }
  }

  void _applyCustomerInfo(CustomerInfo customerInfo) {
    state.value = state.value.copyWith(
      isPro: _hasProEntitlement(customerInfo),
      clearMessage: true,
    );
  }

  static Package? _selectPackage(
    List<Package> packages,
    PackageType type,
    String fallbackProductId,
  ) {
    for (final package in packages) {
      if (package.packageType == type) return package;
    }
    for (final package in packages) {
      if (package.storeProduct.identifier == fallbackProductId) return package;
    }
    return null;
  }

  static bool _hasProEntitlement(CustomerInfo customerInfo) =>
      customerInfo.entitlements.active
          .containsKey(RevenueCatConfig.entitlementId);

  static PurchasesErrorCode? _purchasesErrorCode(PlatformException error) {
    try {
      return PurchasesErrorHelper.getErrorCode(error);
    } catch (_) {
      return null;
    }
  }

  static String _friendlyError(Object error) {
    if (error is PlatformException) {
      return switch (_purchasesErrorCode(error)) {
        PurchasesErrorCode.offlineConnectionError ||
        PurchasesErrorCode.networkError =>
          'The store could not be reached. Check your connection and try again.',
        PurchasesErrorCode.purchaseNotAllowedError ||
        PurchasesErrorCode.insufficientPermissionsError =>
          'Purchases are not allowed for this store account.',
        PurchasesErrorCode.productNotAvailableForPurchaseError =>
          'This subscription is not available in the current store.',
        PurchasesErrorCode.paymentPendingError =>
          'Payment is pending approval. Premium will activate automatically.',
        PurchasesErrorCode.configurationError ||
        PurchasesErrorCode.invalidCredentialsError =>
          'Subscriptions are not configured correctly for this build.',
        _ => 'The purchase service is temporarily unavailable. Try again.',
      };
    }
    return 'The purchase service is temporarily unavailable. Try again.';
  }
}
