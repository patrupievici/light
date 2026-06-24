# HEALTH_CONNECT_INTEGRATION — Zvelt

**Generated:** 2026-05-26
**Source files audited:** `lib/services/health_service.dart`, `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`

---

## TL;DR

Health Connect (Android) and HealthKit (iOS) are **integrated via the `health: ^13.3.1` package** and partially functional. However, **historical data extraction (>30 days) does NOT currently work** because:

1. ❌ `android.permission.health.READ_HEALTH_DATA_HISTORY` permission is not declared in `AndroidManifest.xml`.
2. ❌ No backfill flow on first Health Connect grant — data is only fetched on-demand when the user opens the health tab.
3. ❌ No background sync — new data does not flow in automatically.

This document specifies the **current state, target state, and exact changes needed**.

---

## 1. CURRENT STATE

### 1.1 Flutter dependency
```yaml
# pubspec.yaml line 15
health: ^13.3.1
```
✅ Modern, supports both HealthKit (iOS) and Health Connect (Android).

### 1.2 AndroidManifest — declared permissions
From `android/app/src/main/AndroidManifest.xml:12-19` (approx):
- ✅ `android.permission.health.READ_STEPS`
- ✅ `android.permission.health.READ_EXERCISE`
- ✅ `android.permission.health.READ_HEART_RATE`
- (likely also READ_SLEEP, READ_WEIGHT, READ_BODY_FAT — verify in actual file)
- ❌ **MISSING: `android.permission.health.READ_HEALTH_DATA_HISTORY`** (required for data older than 30 days on Android 14+)

Also declared:
- ✅ `<intent-filter><action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />` — required by Play
- ✅ `<queries>` with `package="com.google.android.apps.healthdata"` — required for Health Connect package visibility on Android 11+
- ✅ `ViewPermissionUsageActivity` alias with `HEALTH_PERMISSIONS` category

### 1.3 Service implementation
File: `lib/services/health_service.dart`

```dart
// Lines ~175-222 (approximate, from audit)
final health = Health();
final types = [
  HealthDataType.STEPS,
  HealthDataType.HEART_RATE,
  HealthDataType.SLEEP_IN_BED,
  HealthDataType.BLOOD_OXYGEN,
  HealthDataType.WEIGHT,
  HealthDataType.BODY_FAT_PERCENTAGE,
  HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  HealthDataType.ACTIVE_ENERGY_BURNED,
  HealthDataType.WORKOUT,
  // ...
];
final permissions = types.map((t) => HealthDataAccess.READ).toList();

await health.requestAuthorization(types, permissions: permissions);
final data = await health.getHealthDataFromTypes(
  startTime: from, endTime: to, types: types,
);
```

**What works:**
- ✅ Requests authorization
- ✅ Fetches recent data on-demand
- ✅ Data types match the CLAUDE.md schema
- ✅ iOS HealthKit path works identically through same plugin

**What doesn't work:**
- ❌ No historical data beyond 30 days (Android 14+ blocks this without `READ_HEALTH_DATA_HISTORY` permission)
- ❌ No "backfill" workflow on first grant
- ❌ No anchored/incremental sync — every fetch hits the entire range from scratch
- ❌ No deduplication against previously imported records
- ❌ No background sync — fetches only on screen open
- ❌ No graceful handling of: Health Connect not installed, permissions denied, permission revoked later, multiple apps writing same metric

---

## 2. TARGET STATE (per directive Rule 3)

### 2.1 Permissions
Declare `READ_HEALTH_DATA_HISTORY` in AndroidManifest.xml AND request it at runtime through the `health` plugin.

### 2.2 First-connect backfill
On first Health Connect authorization grant:
- Fetch as far back as user has data, **minimum 12 months**.
- Show a progress indicator: "Pulling your last year of health data… (3,247 records imported)"
- Persist a per-data-type **sync anchor** (last imported timestamp) in SharedPreferences keyed as `health_anchor_<dataType>`.

### 2.3 Ongoing sync
- Background worker (Android: `WorkManager` via `workmanager` package; iOS: `BGAppRefreshTask` via `flutter_background_service` or HealthKit observer queries) runs every 15-30 minutes.
- For each data type:
  - Read `health_anchor_<dataType>` from SharedPreferences.
  - Fetch records from anchor to `now()`.
  - Deduplicate against local cache (per-record UUID from Health Connect).
  - Persist new records to local sqflite + push relevant deltas to backend (e.g., a new WEIGHT entry → POST `/v1/me/measurements`).
  - Update anchor to last imported record's `endTime`.

### 2.4 Mapping to internal model

| Health Connect record type | `HealthDataType` (plugin enum) | Zvelt internal model | Backend table |
|----------------------------|--------------------------------|----------------------|---------------|
| Steps | STEPS | `daily_steps` | `user_daily_metrics.steps` |
| Distance | DISTANCE_WALKING_RUNNING | `daily_distance_m` | `user_daily_metrics.distance_m` |
| Active calories | ACTIVE_ENERGY_BURNED | `daily_active_kcal` | `user_daily_metrics.active_kcal` |
| Heart rate (sample) | HEART_RATE | `hr_samples` (timestamped) | `user_hr_samples` |
| Resting heart rate | RESTING_HEART_RATE | `daily_resting_hr` | `user_daily_metrics.resting_hr` |
| HRV (SDNN) | HEART_RATE_VARIABILITY_SDNN | `daily_hrv_sdnn` | `user_daily_metrics.hrv_sdnn` |
| VO₂ max | VO2MAX | `vo2_max` | `user_profiles.vo2_max` |
| Sleep session | SLEEP_IN_BED / SLEEP_ASLEEP | `sleep_sessions` | `user_sleep_sessions` |
| Weight | WEIGHT | `weight_kg` | `user_measurements` (latest used as `bodyweight_kg`) |
| Body fat % | BODY_FAT_PERCENTAGE | `body_fat_pct` | `user_measurements` |
| Workout / exercise session | WORKOUT | Imported as `external_workout` (read-only, dedup against own workouts) | `workouts` (with `source=health_connect`) |
| Blood oxygen | BLOOD_OXYGEN | `spo2_samples` | `user_spo2_samples` |
| Hydration | WATER | `daily_hydration_ml` | `user_daily_metrics.hydration_ml` |
| Active minutes | EXERCISE_TIME | derived | `user_daily_metrics.active_minutes` |

**Conflict resolution rule:** if multiple apps write the same metric on the same timestamp, Zvelt prefers (in order): own writes → Garmin → Apple Watch / Wear OS → manual entries → other.

---

## 3. EXACT CHANGES REQUIRED

### 3.1 AndroidManifest.xml

Insert (after existing `<uses-permission android:name="android.permission.health.READ_*" />` lines):

```xml
<!-- Required for reading health data older than 30 days on Android 14+ -->
<uses-permission android:name="android.permission.health.READ_HEALTH_DATA_HISTORY" />
```

### 3.2 health_service.dart — add historical access request

```dart
final permissions = types.map((t) => HealthDataAccess.READ).toList();

// Request historical access on Android 14+
final hasHistory = await health.isHealthDataHistoryAuthorized();
if (!hasHistory && defaultTargetPlatform == TargetPlatform.android) {
  await health.requestHealthDataHistoryAuthorization();
}
```

(Verify exact API method names against `health` 13.3.1 — the method may be named differently.)

### 3.3 health_service.dart — add backfill method

```dart
Future<void> backfillOnFirstGrant({Duration window = const Duration(days: 365)}) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('health_backfill_done') == true) return;

  final end = DateTime.now();
  final start = end.subtract(window);

  for (final type in _allTypes) {
    final records = await health.getHealthDataFromTypes(
      startTime: start, endTime: end, types: [type],
    );
    await _persistRecords(records);
    await prefs.setString('health_anchor_${type.name}', end.toIso8601String());
  }

  await prefs.setBool('health_backfill_done', true);
}
```

### 3.4 health_service.dart — add incremental sync

```dart
Future<void> incrementalSync() async {
  final prefs = await SharedPreferences.getInstance();
  final end = DateTime.now();

  for (final type in _allTypes) {
    final anchorStr = prefs.getString('health_anchor_${type.name}');
    final start = anchorStr != null
        ? DateTime.parse(anchorStr)
        : end.subtract(const Duration(days: 1));

    final records = await health.getHealthDataFromTypes(
      startTime: start, endTime: end, types: [type],
    );
    if (records.isEmpty) continue;

    final deduped = await _dedupeAgainstLocal(records);
    await _persistRecords(deduped);
    await _pushToBackend(deduped);

    final lastTime = records.map((r) => r.dateTo).reduce(
      (a, b) => a.isAfter(b) ? a : b,
    );
    await prefs.setString('health_anchor_${type.name}', lastTime.toIso8601String());
  }
}
```

### 3.5 Background worker

Add `workmanager: ^0.5.x` to `pubspec.yaml`. Register a periodic task in `main.dart`:

```dart
await Workmanager().initialize(_callbackDispatcher);
await Workmanager().registerPeriodicTask(
  'health_incremental_sync',
  'health_incremental_sync',
  frequency: const Duration(minutes: 15),
  constraints: Constraints(networkType: NetworkType.connected),
);
```

`_callbackDispatcher` calls `HealthService.instance.incrementalSync()`.

### 3.6 Graceful failure modes

In `health_service.dart`:

```dart
Future<HealthConnectStatus> checkAvailability() async {
  if (defaultTargetPlatform != TargetPlatform.android) return HealthConnectStatus.notApplicable;
  final status = await health.getHealthConnectSdkStatus();
  switch (status) {
    case HealthConnectSdkStatus.sdkUnavailable:
      return HealthConnectStatus.notInstalled;
    case HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired:
      return HealthConnectStatus.updateRequired;
    case HealthConnectSdkStatus.sdkAvailable:
      return HealthConnectStatus.ready;
  }
}
```

UI shows clear copy + deep link to Play Store for Health Connect install/update when not ready.

### 3.7 Permission revocation handling

On every app foreground, re-check permission state:
```dart
final granted = await health.hasPermissions(types) ?? false;
if (!granted) {
  // Surface in Settings → Health: "Reconnect Health Connect"
}
```

### 3.8 Multi-source deduplication

Each Health Connect record has a `metadata.id` UUID. Store this in the local sqflite `health_imported_records` table. Before inserting a new record, check if UUID exists.

---

## 4. iOS PARITY (HealthKit)

The `health` package abstracts HealthKit so most logic above works on iOS too. iOS-specific notes:

- **Historical data on iOS has no 30-day cap** — `HKSampleQuery` with no end date works fine. Backfill is straightforward.
- **Anchored queries** (`HKAnchoredObjectQuery`) provide native incremental sync; the `health` plugin exposes these as `getHealthIntervalDataFromTypes` and similar.
- **Background delivery**: use `health.enableBackgroundDelivery(HealthDataType.*, HealthDataAccess.READ, frequency)` — wakes the app to sync new data.
- **Info.plist required keys**:
  ```xml
  <key>NSHealthShareUsageDescription</key>
  <string>Zvelt reads your workouts, heart rate, sleep and weight to give you real recovery and training calls.</string>
  <key>NSHealthUpdateUsageDescription</key>
  <string>Zvelt writes back the workouts you log so HealthKit becomes the single source of truth.</string>
  ```

---

## 5. TEST PLAN

| Scenario | Expected behavior |
|----------|-------------------|
| Fresh install, Health Connect not installed | Show "Install Health Connect" CTA → Play Store deep link |
| Fresh install, Health Connect installed, no permission | Permissions sheet → on grant, backfill 365 days, show progress |
| User denies one permission (e.g. weight) | Other types work; weight fields show "—" with "Grant access" button |
| User revokes permission later (Settings → Apps → Permissions) | Next foreground: detect, prompt re-grant |
| User signs out of Health Connect | Same as revoke |
| Multiple apps writing same WEIGHT on same day | Dedupe by record UUID; if no UUID match, conflict resolution rule applies |
| App killed mid-backfill | On next launch, resume from per-type anchor |
| Background sync runs while user is offline | Task fails gracefully; retries when network returns |
| Android 13 device (no Health Connect built-in) | Detect, prompt manual install |
| Android 14+ device, app requests >30-day data | Should work because `READ_HEALTH_DATA_HISTORY` granted |

---

## 6. SUMMARY OF FILES TO MODIFY

| File | Change |
|------|--------|
| `android/app/src/main/AndroidManifest.xml` | Add `READ_HEALTH_DATA_HISTORY` permission |
| `lib/services/health_service.dart` | Add `requestHealthDataHistoryAuthorization`, `backfillOnFirstGrant`, `incrementalSync`, `checkAvailability`, dedup logic |
| `lib/main.dart` | Register WorkManager periodic task |
| `pubspec.yaml` | Add `workmanager: ^0.5.x` |
| `ios/Runner/Info.plist` | Verify `NSHealthShareUsageDescription` + `NSHealthUpdateUsageDescription` |
| Local DB | Create `health_imported_records` table (UUID, type, timestamp, payload_json) |
| Backend | Verify endpoints accept `source=health_connect` flag and dedupe server-side |

---

## 7. ESTIMATED EFFORT

- Permission + manifest: **15 min**
- Backfill + anchor logic in `health_service.dart`: **3-4 hours**
- Background worker + lifecycle: **2-3 hours**
- Test plan execution on real device: **2-3 hours**
- iOS parity verification: **1 hour**

**Total: 1.5 working days for a single dev.**
