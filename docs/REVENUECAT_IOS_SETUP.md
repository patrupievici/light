# RevenueCat and iOS release setup

The client integration is complete, but store purchases cannot become live from
repository code alone. The Apple/Google/RevenueCat accounts must contain the
matching products and public SDK keys.

## RevenueCat dashboard

1. Create or select the ZVELT project.
2. Add the iOS app with bundle ID `com.lunaoscar.zvelt`.
3. Add the Android app with package `com.lunaoscar.zvelt`.
4. Create entitlement `pro`.
5. Attach products `zvelt_pro_monthly` and `zvelt_pro_annual` to `pro`.
6. Create a current offering with `$rc_monthly` and `$rc_annual` packages.
7. Copy only the public iOS (`appl_...`) and Android (`goog_...`) SDK keys.

Build with the public keys (these are not RevenueCat secret API keys):

```powershell
flutter build appbundle --release `
  --dart-define=REVENUECAT_ANDROID_API_KEY=goog_xxx
```

```bash
flutter build ipa --release \
  --dart-define=REVENUECAT_IOS_API_KEY=appl_xxx \
  --dart-define=FIREBASE_IOS_API_KEY=xxx \
  --dart-define=FIREBASE_IOS_APP_ID=1:715817017339:ios:xxx
```

The identifiers can be overridden only if the dashboard uses different names:

```text
REVENUECAT_ENTITLEMENT_ID=pro
REVENUECAT_MONTHLY_PRODUCT_ID=zvelt_pro_monthly
REVENUECAT_ANNUAL_PRODUCT_ID=zvelt_pro_annual
```

Without a valid platform key, the Premium screen deliberately remains disabled
and does not call a native billing API.

## App Store Connect and Xcode

1. Accept Paid Applications agreements and complete banking/tax information.
2. Create the two auto-renewable subscriptions in one subscription group.
3. Add localised names, prices, review screenshots and required metadata.
4. In Xcode, select the Apple team and enable **In-App Purchase** and
   **Push Notifications** for Runner and the App ID.
5. Register `com.lunaoscar.zvelt` in Firebase, add
   `GoogleService-Info.plist` to the Runner target, and run
   `flutterfire configure` on macOS.
6. Upload an APNs authentication key to Firebase and RevenueCat where needed.
7. Archive `ios/Runner.xcworkspace`, upload to TestFlight, then test purchase,
   cancellation, pending payment and restore with an Apple sandbox account.

The current Windows machine cannot compile, sign, archive or validate an iOS
binary. A successful Android build does not validate StoreKit.

## Google Play

1. Create matching subscription products and activate their base plans.
2. Link the Google Play service account in RevenueCat.
3. Upload a signed AAB to an internal testing track before testing billing.
4. Add tester accounts and verify monthly, annual, cancellation and restore.

Google Play Billing normally returns products only for an installed,
store-distributed build whose package, signature and active products match.

## Acceptance checks

- Premium prices come from the current store locale, never hard-coded values.
- Purchase activates entitlement `pro` for the backend user UUID.
- Restore activates the same entitlement after reinstall/sign-in.
- Cancelling a store sheet is silent and does not show a failure.
- Offline/store errors are recoverable and do not block sign-in or profile.
- Sign-out detaches the RevenueCat customer before the next account signs in.
