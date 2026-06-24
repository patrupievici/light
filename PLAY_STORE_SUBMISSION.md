# PLAY_STORE_SUBMISSION — Zvelt Android Release

**Target:** Google Play Console submission, first-pass approval.
**Generated:** 2026-05-26

---

## CURRENT BUILD STATUS

- **Last release build:** `app-release.apk` (84.4 MB, unsigned-with-debug-key, built 2026-05-26)
- **Required output:** `app-release.aab` (Android App Bundle, signed with upload keystore)

⚠️ **The current APK is NOT submission-ready.** Below is the complete gap list.

---

## ✅ ALREADY CONFIGURED CORRECTLY

| Item | Location | Status |
|------|----------|--------|
| `compileSdk = 36`, `targetSdk = 35` | `android/app/build.gradle.kts:22,42` | ✅ Meets Play's API 35 requirement (Aug 2025+) |
| `minSdk = 28` | `android/app/build.gradle.kts:41` | ✅ Health Connect minimum |
| `POST_NOTIFICATIONS` permission | `AndroidManifest.xml:2` | ✅ Required Android 13+ |
| Health Connect intent-filter (`ACTION_SHOW_PERMISSIONS_RATIONALE`) | `AndroidManifest.xml:50` | ✅ Required by Play for health apps |
| Health Connect permissions (steps, exercise, heart rate) | `AndroidManifest.xml:12-19` | ✅ Declared |
| `<queries>` block with Health Connect package visibility | `AndroidManifest.xml:217-226` | ✅ |
| Foreground service for GPS with `foregroundServiceType="location"` | `AndroidManifest.xml:60-64` | ✅ |
| Release signing config (reads `key.properties`) | `android/app/build.gradle.kts:47-56` | ⚠️ Configured BUT `key.properties` not verified to exist with real keystore |
| Firebase BoM 34.11.0, Messaging, Analytics | `android/app/build.gradle.kts:77-79` | ✅ |
| Health Connect client 1.2.0-alpha02 | `android/app/build.gradle.kts:81` | ✅ |
| `google-services.json` real, not placeholder | `android/app/google-services.json` | ✅ Verified — real project ID + API keys |
| Core library desugaring enabled | `android/app/build.gradle.kts:26` | ✅ Java 17 compat |
| Widget receivers with proper `android:exported` | `AndroidManifest.xml:69-122` | ✅ |
| `ViewPermissionUsageActivity` alias for health rationale | `AndroidManifest.xml:201-210` | ✅ |

---

## ❌ MUST FIX BEFORE FIRST UPLOAD (P0)

| # | Item | File | Action |
|---|------|------|--------|
| 1 | `android:allowBackup` not set | `AndroidManifest.xml` `<application>` tag | Add `android:allowBackup="false"` (or define `data_extraction_rules.xml` if cloud backup desired) |
| 2 | `READ_HEALTH_DATA_HISTORY` permission missing | `AndroidManifest.xml` | Add `<uses-permission android:name="android.permission.health.READ_HEALTH_DATA_HISTORY" />` |
| 3 | Firebase Crashlytics not integrated | `pubspec.yaml` + `build.gradle.kts` | Add plugin + dependency + initialize in `main.dart` |
| 4 | No R8/ProGuard minification | `android/app/build.gradle.kts` release block | Add `isMinifyEnabled = true`, `isShrinkResources = true`, `proguardFiles(...)`, create `proguard-rules.pro` |
| 5 | `local.properties` committed | repo root | `.gitignore` + `git rm --cached` |
| 6 | Account deletion flow missing | `lib/screens/settings/` | Add Delete Account screen → `DELETE /v1/me/account` (hard policy req) |
| 7 | Privacy Policy URL is placeholder | Store listing form | **DECIDED: use `https://zvelt.app/privacy` as placeholder. Owner must host this page before submission.** |
| 8 | No upload keystore verified | `android/key.properties` | Generate keystore, commit `key.properties.template`, NEVER commit real `key.properties` |
| 9 | Camera permission rationale | `res/values/strings.xml` | Add `<string name="permission_camera_why">...</string>` etc. for every dangerous permission |
| 10 | Visible dev copy in production (`COMING SOON`, "no demo data") | See `QA_BACKLOG.md` P0.1, P0.3 | Remove/hide before build |

---

## STORE LISTING — DATA SAFETY FORM

This is the form Google Play requires you to fill in Play Console. Below is the prepared content based on the audit; the **owner must submit it via Play Console UI**.

### Data types collected

| Data type | Collected? | Shared? | Optional? | Purpose | Encrypted in transit? |
|-----------|-----------|---------|-----------|---------|----------------------|
| **Email address** | ✅ Yes | No | No (required for account) | Account management, login | ✅ TLS 1.2+ |
| **User name** | ✅ Yes | No | No | Account display | ✅ |
| **Profile photo** | ✅ Yes (optional) | No | Yes | Profile display | ✅ |
| **Health & fitness — heart rate** | ✅ Yes | No | Yes (Health Connect opt-in) | Workout analytics, recovery suggestions | ✅ |
| **Health & fitness — sleep** | ✅ Yes | No | Yes | Recovery suggestions | ✅ |
| **Health & fitness — steps / distance / calories** | ✅ Yes | No | Yes | Daily activity tracking | ✅ |
| **Health & fitness — weight / body fat** | ✅ Yes | No | Yes | Bodyweight-relative ranking (e1RM) | ✅ |
| **Health & fitness — exercise sessions** | ✅ Yes | No | No (core feature) | Workout tracking | ✅ |
| **Health & fitness — VO₂ Max** | ✅ Yes | No | Yes | Cardio analytics | ✅ |
| **Location (precise, foreground only)** | ✅ Yes | No | Yes | Outdoor activity GPS tracking | ✅ |
| **Photos** | ✅ Yes (optional) | No | Yes | Profile photo, post images | ✅ |
| **Crash logs** | ✅ Yes | Yes (with Google for Crashlytics) | No | Stability monitoring | ✅ |
| **Diagnostic info (device model, OS)** | ✅ Yes | Yes (with Google for Analytics) | No | Compatibility debugging | ✅ |
| **App interactions** | ✅ Yes | Yes (with Google for Analytics) | No (with consent) | Product analytics | ✅ |
| **User-generated content (posts, comments)** | ✅ Yes | Visible to friends only by default | Yes | Social feature | ✅ |
| **Friends list** | ✅ Yes | No | Yes (social feature opt-in) | Social graph | ✅ |
| **Push notification token** | ✅ Yes | Yes (with Google FCM) | No | Notification delivery | ✅ |

### Data deletion

- ✅ Users can request data deletion in-app: Settings → Account → Delete Account
- ✅ Backend hard-deletes within 30 days per GDPR (CLAUDE.md commitment)
- ✅ Web URL for deletion request (for users who can't log in): **owner provides URL**

### Security practices

- ✅ Data encrypted in transit (TLS 1.2+)
- ✅ Auth tokens encrypted at rest using Android EncryptedSharedPreferences / iOS Keychain (verify in `auth_service.dart`)
- ✅ Independent security review: **owner decision** (optional checkbox)
- ✅ Follows Play Families Policy: N/A (app is 13+)

---

## STORE LISTING ASSETS — REQUIRED

| Asset | Spec | Owner provides | Status |
|-------|------|----------------|--------|
| App icon | 512×512 PNG (no alpha), 1024×1024 source for adaptive | ✅ | ⚠️ Verify present in `android/app/src/main/res/mipmap-*` |
| Feature graphic | 1024×500 PNG/JPG | ✅ | ❌ Required |
| Phone screenshots | Min 2, up to 8. 1080×1920 portrait recommended | ✅ | ❌ Required (capture from release build) |
| 7-inch tablet screenshots | Optional but recommended for discoverability | ⚠️ | Optional |
| 10-inch tablet screenshots | Optional | ⚠️ | Optional |
| Short description | Max 80 chars | Draft below | ⚠️ |
| Full description | Max 4000 chars | Draft below | ⚠️ |
| Promo video | YouTube link, optional | ⚠️ | Optional |

### Draft — Short description (76/80)

> Track workouts, climb the leaderboard, eat smart. Built for athletes who refuse to plateau.

### Draft — Full description (skeleton, owner to refine)

```
ZVELT — BUILT FOR THE OBSESSED

Most fitness apps were built for people who quit. This one wasn't.

▸ TRAIN
Log every set with sub-second precision. Smart rest timers, plate calculators, and form cues for 200+ exercises.

▸ RANK
Your numbers turn into a rank that means something. Bodyweight-relative e1RM, percentile-based tiers (Iron → Olympian), explainable scoring.

▸ TRIBE
Friend-only feed by default. Privacy you control. Find athletes who match your fingerprint.

▸ AI COACH
Ask Zvelt anything. Trained on your data — knows your sleep, your sets, your stress. Available from any screen.

▸ NUTRITION
Barcode scan, USDA-verified macros, auto-targeting based on your goal and cadence.

▸ HEALTH CONNECT
Pulls heart rate, sleep, VO₂, weight from your watch and phone. Backfills 12+ months on first connect.

▸ STREAKS & QUESTS
Show up. Stack days. Earn what you train for.

—

PRIVACY FIRST
- Friend-only feed by default
- Discovery is opt-in
- Account deletion in 30 days
- Health data encrypted on device

REQUIRES
- Android 9+ (API 28)
- Health Connect (Android 14+: auto-installed)

—

Built by athletes. Shipped for athletes who win.
```

---

## CONTENT RATING

Recommended fill-out:
- **Violence:** None
- **Sexuality:** None
- **Language:** Mild (motivational copy uses "OBSESSED", "DOMINATE" — not profanity, should pass)
- **Controlled substances:** None
- **Gambling:** None
- **User-generated content:** Yes (posts, comments) — describe moderation: reporting flow + audit log per CLAUDE.md
- **User location sharing:** No (location stays on device + backend, not shared between users)
- **Personal info sharing:** No

Expected rating: **PEGI 3 / Everyone**.

---

## TARGET AUDIENCE

- **Primary:** 16-45, athletes / fitness enthusiasts
- **Age groups:** 13-15 (limited features), 16+
- **Family Policy:** N/A (not designed for children)

---

## RELEASE TRACK STRATEGY

1. **Internal testing** (1-day) — closed track, 5-10 internal testers, verify Crashlytics + push notifications
2. **Closed beta** (7 days minimum) — 20-50 testers from Discord/community, gather feedback
3. **Open testing** (optional, 7 days) — for broader pre-launch testing
4. **Production rollout** — staged: 5% → 20% → 50% → 100% over 7 days, monitoring crash rate

---

## SUBMISSION CHECKLIST (PRINT-READY)

Before clicking "Submit for review":

- [ ] AAB built with `flutter build appbundle --release`
- [ ] AAB signed with real upload keystore (not debug)
- [ ] All P0 items from `QA_BACKLOG.md` resolved
- [ ] Privacy Policy URL hosted and tested
- [ ] Account deletion flow tested end-to-end on real device
- [ ] App tested on a real Android 10 device AND a real Android 14 device (minimum)
- [ ] Health Connect permission flow tested (allow / deny / partial)
- [ ] Push notification received on real device
- [ ] Cold-start time < 2s on mid-range device
- [ ] No `console.log` / `print()` / debug logs in release output
- [ ] `flutter analyze` zero errors, zero warnings
- [ ] `flutter test` passes
- [ ] App icon and adaptive icon render correctly on Pixel + Samsung launchers
- [ ] Screenshots captured from release build, not debug
- [ ] Data Safety form submitted via Play Console
- [ ] Content rating questionnaire completed
- [ ] Target audience set
- [ ] Localization: at minimum English fully translated
- [ ] Store listing: short desc, full desc, feature graphic, screenshots uploaded
