# QA_BACKLOG — Zvelt App Play-Submission Readiness

**Generated:** 2026-05-26
**Audit scope:** `E:\razvanluna\app\lib` (Flutter) + `E:\razvanluna\app\android` (native config)
**Build target:** Google Play release AAB
**Format:** `severity | file:line | finding | proposed fix`

---

## 🔴 P0 — BLOCKERS (must fix before Play upload)

### P0.1 — "Photo Progress" card advertises unimplemented feature
- **File:** `lib/screens/analytics/progress_hub_screen.dart:1158`
- **Finding:** Card displays `COMING SOON` badge in shipped UI
- **Why blocker:** Play reviewers flag "advertising features that don't exist". User-facing dead end.
- **Fix:** Either remove the card entirely or implement photo comparison tracking end-to-end (client camera + crop + storage upload + `/v1/photo-progress` backend endpoint). **Default decision: REMOVE for v1.0; move to FEATURE_SUGGESTIONS.**

### P0.2 — Elevation profile shipping with hardcoded zeros
- **File:** `lib/screens/activity/activity_summary_screen.dart:193`
- **Finding:** `_extractElevations()` always returns `List.generate(..., 0.0)` because `latlong2` LatLng has no altitude field. Comment: "return placeholder".
- **Why blocker:** Every cardio summary will show a flat elevation chart — visibly broken on screen.
- **Fix:** Backend must include `altitude_m` in `route_points` JSON. Parser must read `altitude_m` from each point. If altitude is unavailable for a workout, hide the elevation card instead of showing flat zeros.

### P0.3 — Visible "Not shown yet — no demo data" string in rest analytics
- **File:** `lib/widgets/charts/rest_time_trend.dart:82`
- **Finding:** Card literally renders the text *"Rest analytics need timed rests synced per workout from the server. Not shown yet — no demo data."*
- **Why blocker:** Production users see internal dev copy. Instant Play rejection signal.
- **Fix:** Implement timed rest logging at the set level (server stores `rest_started_at`, `rest_ended_at` per `workout_set`) and chart real data. Until backend is ready, **HIDE the entire card** (don't render placeholder copy).

### P0.4 — `READ_HEALTH_DATA_HISTORY` permission missing
- **File:** `android/app/src/main/AndroidManifest.xml` (insert after current health permissions, ~line 19)
- **Finding:** Health Connect permissions present but the historical-read permission required for >30-day data on Android 14+ is NOT declared.
- **Why blocker:** Per Rule 3 of the directive AND Play policy — historical data extraction requires this permission. Without it, the app cannot backfill 12 months on first connect.
- **Fix:** Add `<uses-permission android:name="android.permission.health.READ_HEALTH_DATA_HISTORY" />`. Then update `lib/services/health_service.dart` to also request `HealthDataAccess.READ_HISTORY` (or the `health` plugin's equivalent) and run a one-shot 365-day backfill on first Health Connect grant.

### P0.5 — No data backup config on `<application>`
- **File:** `android/app/src/main/AndroidManifest.xml` (`<application>` tag, ~line 21)
- **Finding:** Neither `android:allowBackup` nor `android:dataExtractionRules` is set.
- **Why blocker:** Play requires an explicit choice. Default behavior is to allow auto-backup of all user data including auth tokens — a security issue.
- **Fix:** Add `android:allowBackup="false"` to the application tag. If user-data cloud backup is desired later, create `res/xml/data_extraction_rules.xml` excluding `auth_tokens`, `health_cache` directories and reference via `android:dataExtractionRules`.

### P0.6 — Firebase Crashlytics not integrated
- **File:** `android/app/build.gradle.kts` (dependencies block, ~line 73-82) + `pubspec.yaml`
- **Finding:** `firebase_messaging` is present but `firebase_crashlytics` is not. No crash reporting in release.
- **Why blocker:** Directive Rule 4. Crash-free sessions ≥99.5% SLO from CLAUDE.md cannot be measured without it.
- **Fix:** Add Flutter dep `firebase_crashlytics: ^4.x.x` to `pubspec.yaml`. Add native dep `implementation("com.google.firebase:firebase-crashlytics")` and plugin `id("com.google.firebase.crashlytics")` to `build.gradle.kts`. Initialize in `main.dart` with `FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;` and `PlatformDispatcher.instance.onError`. Set `isCrashlyticsCollectionEnabled = !kDebugMode`.

### P0.7 — R8/ProGuard minification disabled for release
- **File:** `android/app/build.gradle.kts` (buildTypes block, ~line 58-66)
- **Finding:** Release build has no `isMinifyEnabled = true` nor `isShrinkResources = true` nor ProGuard rules file.
- **Why blocker:** Without minification: (a) APK is bloated (84.4 MB current — could be ~30-40 MB minified), (b) reflective Firebase / Health Connect models will break in release if obfuscation is later enabled with wrong keeps, (c) reverse-engineering risk for the auth flow.
- **Fix:** Add to `release { }`:
  ```kotlin
  isMinifyEnabled = true
  isShrinkResources = true
  proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
  ```
  Create `android/app/proguard-rules.pro` with keeps for:
  - `-keep class androidx.health.** { *; }`
  - `-keep class com.google.firebase.** { *; }`
  - `-keep class com.android.billingclient.** { *; }`
  - All model classes used with `json_serializable` / Gson (use `@Keep` or wildcard their package)
  - Kotlin metadata: `-keep class kotlin.Metadata { *; }`

### P0.8 — `local.properties` committed to repo
- **File:** `android/local.properties` (currently in git)
- **Finding:** File contains absolute SDK paths from the developer's machine. Shouldn't be in version control.
- **Why blocker:** Not a Play rejection but is a security/hygiene issue and breaks reproducible builds.
- **Fix:** Add to `.gitignore`. Run `git rm --cached android/local.properties`.

### P0.9 — Account deletion flow missing
- **File:** `lib/screens/settings/` (need to verify) + `lib/services/auth_service.dart`
- **Finding:** Audit did not surface a clear in-app account deletion screen. Play requires it for any app with accounts.
- **Why blocker:** Hard Play policy requirement since 2023.
- **Fix:** Add Settings → Account → Delete Account screen with confirmation. Calls `DELETE /v1/me/account` (backend must implement hard-delete + audit log per CLAUDE.md GDPR section). Show 30-day grace period notice. On success: clear local DB, logout, navigate to Welcome.

### P0.10 — Privacy Policy URL is placeholder
- **File:** Likely `pubspec.yaml` / `AndroidManifest.xml` / store listing (verify location)
- **Finding:** No real privacy policy URL identified.
- **Why blocker:** Play submission form requires real URL.
- **Fix:** **Human owner action** — host privacy policy at e.g. `https://zvelt.app/privacy`. Then update store-listing form. Flag this in `PLAY_STORE_SUBMISSION.md`.

---

## 🟡 P1 — REAL-DATA / WIRING (feature works but not backed by real data/backend)

### P1.1 — Outdoor GPS session not saved to backend
- **File:** `lib/screens/outdoor/outdoor_track_screen.dart`
- **Finding:** Live GPS tracking + map render works (Geolocator + flutter_map). Session end button does NOT POST the route to backend. User must manually re-log as a Workout in another tab.
- **Fix:** On session end, POST to `/v1/activities/outdoor` with `route_points` (lat,lng,altitude,timestamp), `duration_s`, `distance_m`, `avg_pace`. Treat as a Workout (workout_type=cardio_outdoor).

### P1.2 — Calendar is local-only (sqflite)
- **File:** `lib/services/activity_calendar_store.dart` + `lib/screens/calendar/activity_calendar_screen.dart`
- **Finding:** Workout dates rendered on calendar come from local sqflite only. No server sync.
- **Fix:** Add `GET /v1/me/workouts/calendar?from=YYYY-MM-DD&to=YYYY-MM-DD` (lightweight: just dates + workout types). Sync once per session and cache in sqflite as before. Local sqflite stays for offline.

### P1.3 — Profile editing stubbed
- **File:** `lib/screens/profile/` (account_settings screen referenced but PATCH not verified)
- **Finding:** Profile read from `/v1/me` works. Editing bio / display name / profile pic → not wired to `PATCH /v1/me/profile`.
- **Fix:** Wire form save to `PATCH /v1/me/profile`. Image upload uses existing storage flow (verify); on success update local cache.

### P1.4 — Social feed has no pagination
- **File:** `lib/services/social_feed_service.dart`
- **Finding:** Feed loads `limit=20, page=1` only. Infinite scroll doesn't load more.
- **Fix:** Implement cursor-based pagination per CLAUDE.md API conventions. Add `loadMore()` triggered at 80% scroll depth. Use `next_cursor` from response.

### P1.5 — `social_feed_service.dart` silent error
- **File:** `lib/services/social_feed_service.dart:24`
- **Finding:** Returns empty list on HTTP != 200; no user-facing error message.
- **Fix:** Throw typed error; UI shows "Failed to load — Retry" button. Log to Crashlytics.

### P1.6 — AI chat timeout missing
- **File:** `lib/services/ai_chat_service.dart:30` + `lib/screens/ai/ai_chat_screen.dart:39-80`
- **Finding:** `.withAiTimeout()` extension referenced but not consistently applied; if backend hangs, UI is stuck.
- **Fix:** Enforce 30s timeout on AI calls; show typing-dots if pending; show "AI is taking a moment, try again" on timeout.

### P1.7 — FCM token not re-sent after refresh
- **File:** `lib/services/push_messaging_service.dart`
- **Finding:** Initial token POST works on first login. Need to verify `onTokenRefresh` handler is wired to re-POST.
- **Fix:** Subscribe to `FirebaseMessaging.instance.onTokenRefresh` and POST again to `/v1/me/push-token`.

### P1.8 — Health Connect: no background sync
- **File:** `lib/services/health_service.dart`
- **Finding:** Data fetched only when user opens health tab. Not background-synced.
- **Fix:** Use `workmanager` or `flutter_background_service` to run a periodic (15min) sync of NEW health records since last anchor. Persist anchor in SharedPreferences.

### P1.9 — Friend streaks load with no timeout
- **File:** `lib/screens/social/circle_screen.dart:52-80`
- **Finding:** Parallel fetch of friend streaks; if backend hangs entire list hangs.
- **Fix:** 10s timeout on each, render available + show skeleton for pending. Failed ones show "—".

### P1.10 — Set weight/reps not validated on submit
- **File:** `lib/screens/workouts/workout_tracker_screen.dart` (referenced)
- **Finding:** Per CLAUDE.md: weight_kg ∈ [0, 500], reps ∈ [1, 50]. No client validation.
- **Fix:** Validate on every set save; surface inline error.

### P1.11 — Workout draft auto-save missing
- **File:** `lib/screens/workouts/workout_tracker_screen.dart`
- **Finding:** If app is killed mid-workout, client state is lost (workout draft persists server-side but client can't resume cleanly).
- **Fix:** On every set save, persist workout_id locally. On app start, check for in-flight workout → offer "Resume workout?" dialog.

### P1.12 — Achievements error handling poor
- **File:** `lib/screens/profile/achievements_screen.dart:48-60`
- **Finding:** 403 / 500 shows only "Could not load" without retry or detail.
- **Fix:** Inline retry button; log to Crashlytics; distinguish auth vs server error.

### P1.13 — Heatmap data source unclear
- **File:** `lib/screens/profile/` (heatmap component)
- **Finding:** Git-style calendar of workout days exists but data source not identified — may be empty.
- **Fix:** Wire to `GET /v1/me/workouts/heatmap?year=YYYY` returning array of dates with count.

### P1.14 — Camera permission declared but no clear usage
- **File:** `android/app/src/main/AndroidManifest.xml:10`
- **Finding:** `READ_MEDIA_IMAGES` declared. Camera usage for what? Profile pic? Photo progress (removed in P0.1)?
- **Fix:** Audit usage: if only profile pic, restrict to `READ_MEDIA_IMAGES` (already correct); add rationale string in `strings.xml`. If unused, remove.

### P1.15 — Settings privacy toggles not verified to sync
- **File:** `lib/screens/settings/settings_screen.dart`
- **Finding:** Toggle UI works against SharedPreferences; server sync via `PATCH /v1/me/settings` not verified.
- **Fix:** Verify wiring. Add server sync. On failure, revert UI toggle.

---

## 🔵 P2 — POLISH / TODOs

### P2.1 — `// TODO: navigate to post composer with pre-filled activity`
- **File:** `lib/screens/activity/activity_summary_screen.dart:186`
- **Current:** Shows SnackBar "Opening post composer…" but doesn't navigate.
- **Fix:** Implement deep link to `PostComposerScreen(workoutId: ...)`.

### P2.2 — `// TODO: navigate to home/feed`
- **File:** `lib/screens/activity/activity_summary_screen.dart:720`
- **Fix:** Wire to `Navigator.pushNamedAndRemoveUntil` to home.

### P2.3 — HR zones algorithm marked "temporary"
- **File:** `lib/screens/analytics/strava_labs_tab.dart:131`
- **Finding:** Comment: "Derived from resting/average heart rate as a temporary model".
- **Fix:** Document as "beta" in release notes; long-term: implement Karvonen formula or use HR reserve method properly.

### P2.4 — `emailHint = 'you@example.com'`
- **File:** `lib/l10n/app_strings.dart:9`
- **Finding:** Form placeholder; minor.
- **Fix:** Acceptable as-is.

### P2.5 — Hardcoded quick-reply phrases in Race Hub
- **File:** `lib/screens/social/race_hub_screen.dart:589`
- **Finding:** `_quickReplies = ['140KG?', 'TOO SLOW!', 'KEEP DREAMING']`.
- **Fix:** Move to backend-served list with locale support, or curate final list.

### P2.6 — Page cache doesn't auto-refresh on tab revisit
- **File:** `lib/screens/main_screen.dart:32-49`
- **Finding:** `List<Widget?>.filled(4, null)` cache; data goes stale.
- **Fix:** Add `RefreshIndicator` to each tab + invalidate cache after N seconds (e.g., 5 min) or on push notification.

### P2.7 — USDA API key handling
- **File:** `lib/services/usda_fdc_client.dart:68-77`
- **Finding:** Direct USDA call if `--dart-define USDA_API_KEY` set; else proxy. Key could leak in release.
- **Fix:** **Disable direct mode in release** (`assert(kDebugMode)` around the dart-define path). Always proxy in release.

### P2.8 — `// Cardio mock animation` (intentional)
- **File:** `lib/screens/workouts/quick_launch_sheet.dart:665`, `:1555` (`_routePoints`), `:1624` ("Street labels (mock)")
- **Finding:** Animated demo route + fake street labels in the quick-launch sheet.
- **Decision needed:** Is this onboarding-only or shown in production? If production, label clearly as "Preview" or replace with real map tiles. **Default: confirm with owner.**

### P2.9 — Strava OAuth exchange service missing
- **File:** `lib/services/` (no `integrations_service.dart` for Strava found)
- **Finding:** CLAUDE.md spec includes `POST /v1/integrations/strava/exchange` but no client wrapper.
- **Fix:** Implement `IntegrationsService.exchangeStravaCode(code)`; wire to Settings → Integrations → Strava button.

### P2.10 — Biology tab UI-only skeleton
- **File:** `lib/screens/biology/biology_tab.dart`
- **Finding:** Tab exists but has no real layout — defers to `HealthService.getSummary()` which works but UI to display is stubbed.
- **Fix:** Either implement the biology tab UI (VO₂, HRV, sleep, weight trends) using the existing HealthService data, OR remove the tab from main shell. **Decision needed from owner.**

### P2.11 — Journal tab is empty
- **File:** `lib/screens/journal/journal_tab.dart`
- **Finding:** Placeholder; no journal service exists.
- **Fix:** Per CLAUDE.md roadmap this is post-launch. Hide tab for v1.0 OR keep as "Coming soon" only if minor. **Default decision: HIDE for v1.0** (matches Rule 1 + P0.1).

### P2.12 — RevenueCat / Pro tier not integrated
- **File:** `pubspec.yaml` (no `purchases_flutter`)
- **Finding:** Monetization not implemented. Pro paywall in onboarding (Step 23) is visual only.
- **Fix:** **Decision needed.** Ship v1.0 free-only and add Pro post-launch? Or block submission until Pro integrated? Recommend free-only for v1.0 (faster to ship). → Move to `FEATURE_SUGGESTIONS.md`.

---

## OUT OF SCOPE (Rule 1 — appended to `FEATURE_SUGGESTIONS.md`)

- Photo progress comparison (was P0.1)
- Biology tab full UI
- Journal feature
- RevenueCat / Pro tier
- Outdoor → Workouts unified flow
- Server-side rest-time tracking

---

## SUMMARY

| Severity | Count |
|----------|-------|
| P0 BLOCKER | 10 |
| P1 REAL-DATA | 15 |
| P2 POLISH | 12 |
| **TOTAL** | **37** |

**Estimated effort to address all P0 + P1:** 5-8 working days for a single mid-senior dev.
**P2 polish:** 2-3 additional days.

**Minimum-viable-Play-submit set:** P0.1 through P0.10 = ~3 working days.
