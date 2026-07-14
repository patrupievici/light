# ZVELT Release Readiness Audit

Audit date: 2026-07-14  
Audited code revision: `e36f69c538ba0050cfbde4ac4dc87129d40a024b`  
Production API: `https://light-l6en.onrender.com`  
Scope: Flutter client, Fastify/Prisma backend, PostgreSQL migrations, Android release artifacts, Android emulator, production API, privacy, security, accessibility, UX, product and operational launch readiness.

## 1. Executive Summary

ZVELT is now materially stronger than the first audit. The previously identified critical dependency vulnerability, private-media bypass, incomplete account erasure, nutrition target mismatch, theme navigation reset, red Flutter suite, misleading Premium action, hidden strength entry point, unlabeled controls and inaccessible guest-account flow have been repaired and retested.

The current Android/backend candidate is suitable for an internal or tightly monitored closed beta. It is not yet ready for a public cross-platform launch tomorrow. The remaining launch blockers are concentrated outside the now-stable core API: iOS Firebase configuration is placeholder-only, no iOS release was built or device-tested, RevenueCat billing is absent, store submission was not performed, and Health/Strava/Google/camera/background behavior has not been validated on representative physical devices.

No Critical issue remains in the audited Android/backend path. Four High launch issues remain. The recommendation is intentionally strict because the stated product is cross-platform and the public-launch bar includes billing, hardware integrations and both stores.

### Release Fixes Completed

- Upgraded the Fastify/JWT dependency chain; production and full `npm audit` now report zero known vulnerabilities.
- Added authenticated, policy-checked delivery for avatar, post and story media; private URLs no longer bypass privacy rules.
- Replaced ephemeral Render filesystem storage for new user media with durable PostgreSQL storage while preserving `/uploads/...` URLs and authorization checks.
- Added immediate access-token revocation behavior after account deletion by checking active account state on every protected request.
- Completed backend and device-local account erasure, including credentials, encrypted databases, caches and progress-photo files.
- Added strict CORS allowlisting, Helmet security headers, HSTS and generic production error responses.
- Removed plain `SharedPreferences` fallback for auth tokens; SecureStorage failures now fail closed.
- Added guest-to-email conversion on the same `userId`, preserving profile, workouts and social data.
- Added onboarding sign-in and Profile > Account > Save account; switching to an existing account from Profile requires explicit data-loss confirmation.
- Normalized email addresses at backend auth boundaries and revoked old guest refresh sessions on conversion.
- Synchronized nutrition preferences and canonical targets with the backend; stale or partial weekly plans regenerate.
- Fixed AI Coach so normal questions never create/open a workout as a side effect.
- Removed navigator reset on theme change and removed the global text-scale cap.
- Added meaningful semantics and 48dp targets to the audited icon controls.
- Made strength workout entry prominent and made the unavailable Premium surface honest and non-interactive.
- Removed unnecessary Android broad media permission; retained camera permission only where required.
- Added production release identification and a repeatable production smoke suite.

## 2. Overall Application Score

**78 / 100**

The core Android/backend product is functional, privacy-aware and extensively tested. The score is held below release-ready range by unvalidated iOS/store/hardware paths, incomplete billing, performance uncertainty on physical devices and remaining architectural debt.

## 3. UI Score

**86 / 100**

The approved visual design is consistent across Home, Plan, Feed, AI, Nutrition, Profile and Settings. Manual portrait, landscape and 1.6x text checks found no overflow in the sampled release screens. Remaining deductions cover limited 2.0x coverage, a scroll-heavy login screen and incomplete cross-platform visual validation.

## 4. UX Score

**80 / 100**

Core activation is much clearer: strength is discoverable, guest users can save their progress, existing users can sign in from onboarding, account deletion is complete, and AI no longer redirects meal questions into workout tracking. Remaining friction includes no account-data merge into an existing account, incomplete integrations and several visible future-feature surfaces.

## 5. Performance Score

**72 / 100**

Release builds complete, scrolling was stable on the emulator, lazy screen construction and caches are present, and production smoke completed successfully. Risk remains around a 110.6 MB universal APK, a 73.8 MB AAB, first-launch frame skips observed on the emulator, Skia being forced instead of Impeller and no physical low/mid-tier device profiling.

## 6. Accessibility Score

**78 / 100**

Automated accessibility tests pass, audited controls have labels and 48dp targets, system text scaling is no longer capped, and sampled screens survived 1.6x text and landscape. A complete TalkBack/VoiceOver pass and 2.0x full-screen test matrix are still missing.

## 7. Code Quality Score

**80 / 100**

Static analysis is clean, backend tests are broad, migrations are versioned, release smoke is repeatable and high-risk auth/media logic has focused regression tests. Deductions remain for 28 direct HTTP client files, 12 `$queryRawUnsafe` call sites, 28 empty catches and some dead/incomplete feature code.

## 8. Product Score

**72 / 100**

Workout, ranking, social, nutrition, AI and account-management journeys are coherent. Product completeness is reduced by unavailable subscriptions, partial wearable/integration surfaces, English-only UI and local-only journal data.

## 9. Security Score

**88 / 100**

Dependency audit is clean; bearer sessions, CORS, private media, deletion, token storage and production headers were hardened and tested. Remaining concerns are unencrypted local progress-photo bytes, unsafe raw-SQL APIs, incomplete external-provider validation and the need to move durable media to dedicated object storage at scale.

## 10. Stability Score

**89 / 100**

Flutter tests pass `209/209`; backend tests pass `837/837`; Flutter analysis and TypeScript builds are clean; production smoke passes `113/113`; account cleanup succeeds. Residual risk is dominated by devices and platforms not exercised in this Windows/Android-emulator audit.

## 11. Launch Readiness Score

**68 / 100**

Android closed beta: acceptable with monitoring.  
Public Android release: close, but physical-device/store checks remain.  
Public iOS + Android release: blocked by iOS configuration/build validation, billing and operational store readiness.

### Verification Evidence

| Check | Result |
| --- | --- |
| `flutter analyze` | Pass, no issues |
| Flutter test suite | Pass, 34 files, 209 tests |
| Backend TypeScript build | Pass, including `prisma generate` |
| Backend test suite | Pass, 67 files, 837 tests |
| Prisma schema validation | Pass |
| Production dependency audit | 0 vulnerabilities |
| Full backend dependency audit | 0 vulnerabilities |
| Production smoke, release `e36f69c538ba` | 113/113 pass, 0 fail, all accounts cleaned |
| APK release build | Pass, 115,973,081 bytes |
| AAB release build | Pass, 77,419,356 bytes |
| APK SHA-256 | `48D78C48632E0F6D543D596069C792457F0B022115AD8FC6A1B21234DF21F1FB` |
| AAB SHA-256 | `F0F6D8819BEFC58ACFB79360F321195CD7B8BDA62BF93D308D43AB1DE5C090FF` |
| Android signing | Pass, signer `CN=Zvelt, OU=Mobile, O=Zvelt, C=RO` |
| Manual emulator screens | Home, Plan, Feed, AI, Nutrition, Profile, Account, Delete Account, onboarding/login |
| Offline restart | Pass: authenticated cached Home remained usable; requests failed without crash |
| Rotation | Pass on sampled landscape screen |
| Text scale | Pass at 1.6x on sampled Home/onboarding screens |
| Private media without authorization | Rejected |
| Deleted access/refresh sessions | Rejected |
| Guest conversion | Same user id, data preserved, old credentials revoked |
| Durable media across Render deployment | `PENDING_DURABLE_MEDIA_REDEPLOY_CHECK` |

### Audit Limits

- No macOS host was available, so iOS compilation/signing could not be performed.
- No App Store Connect or Play Console publishing action was available in this workspace.
- No representative physical iPhone or Android handset was tested.
- Google Sign-In, Strava, HealthKit, Health Connect, camera and push delivery require external accounts/hardware and were not completed end to end.
- Load, soak, low-memory, thermal and long-duration background tests were not run.

## 12. Top 20 Highest Priority Issues

### A-01: iOS Firebase configuration is placeholder-only

- Screen: iOS startup, push notifications, Crashlytics and Google Sign-In.
- Description: `firebase_options.dart` still contains `REPLACE_IOS_API_KEY` and `REPLACE_IOS_APP_ID`. The iOS Firebase path therefore cannot be considered operational.
- Why it matters: A cross-platform public launch can fail at startup or silently lose push/crash telemetry on iOS.
- Severity: **High**.
- Steps to reproduce: Inspect `app/lib/config/firebase_options.dart`, or build/run the iOS target with current options.
- Suggested solution: Register the production iOS bundle in Firebase, add valid options and `GoogleService-Info.plist`, then test startup, push and Crashlytics on a physical device.
- Estimated implementation complexity: Medium, 1-2 days plus Apple/Firebase credentials.

### A-02: No iOS release build, signing or physical-device QA

- Screen: Entire iOS application.
- Description: This Windows audit could not compile, sign or execute the iOS client. Layout, permissions, Keychain, HealthKit, background modes and store entitlements remain unverified.
- Why it matters: Android success does not predict iOS build or runtime behavior.
- Severity: **High**.
- Steps to reproduce: Attempt the release pipeline on macOS; no verified `.ipa` or TestFlight build is present in the evidence.
- Suggested solution: Run `flutter build ipa`, archive with the production team, install through TestFlight and repeat the critical-flow matrix on at least two iPhone classes.
- Estimated implementation complexity: High, 2-5 days depending on signing status.

### A-03: RevenueCat purchase, restore and entitlement flows are absent

- Screen: Profile Premium and any Pro-gated feature.
- Description: The visible banner truthfully says purchases are unavailable and is not clickable, but no RevenueCat client dependency or operational checkout/restore flow exists. A dead `_PremiumSheet` prototype remains in source.
- Why it matters: The stated monetization plan cannot launch, and subscription review requirements are untested.
- Severity: **High** if subscriptions are part of launch; otherwise Medium.
- Steps to reproduce: Inspect `app/pubspec.yaml` and Profile; no purchase can be initiated or restored.
- Suggested solution: Integrate RevenueCat, configure products/entitlement, implement purchase/restore/error states and validate sandbox receipts on both stores. Keep the banner disabled until complete.
- Estimated implementation complexity: High, 3-7 days plus store configuration.

### A-04: Store publishing and review readiness were not executed

- Screen: Release operations, privacy declarations and store listings.
- Description: Signed Android artifacts exist, but no Play Console upload, internal-track install, App Store archive, screenshots, privacy labels or review submission was performed in this audit.
- Why it matters: Version codes, signing, declarations, billing policy and review metadata can still block launch even when the app runs.
- Severity: **High**.
- Steps to reproduce: Check the evidence set; there is no verified store-track build/install or review receipt.
- Suggested solution: Upload the AAB to Play internal testing, resolve pre-launch report findings, complete Data Safety, then repeat for TestFlight/App Store privacy details.
- Estimated implementation complexity: Medium, 1-3 days excluding review time.

### A-05: Hardware and lifecycle integrations lack a representative device matrix

- Screen: Camera, HealthKit, Health Connect, Strava, push, background/foreground and low-memory recovery.
- Description: Emulator checks cannot validate OEM camera providers, health permissions, Bluetooth/wearable behavior, APNs/FCM delivery, process death or GPU-specific rendering.
- Why it matters: These failures commonly produce one-star reviews and can affect sensitive health data.
- Severity: **High**.
- Steps to reproduce: Run the named flows on a low-tier Android, modern Android and two iPhone versions; evidence is currently absent.
- Suggested solution: Establish a release matrix with physical devices and scripted expected results, including permission denial/revocation and process death.
- Estimated implementation complexity: High, 3-5 days for the first complete pass.

### A-06: No automated real-PostgreSQL plus device release gate

- Screen: Cross-feature API contracts.
- Description: The production smoke is strong but manually invoked. Most backend route tests mock Prisma, and Flutter tests do not boot the production stack.
- Why it matters: Schema/client drift can return between audits, and release quality depends on a person remembering the smoke command.
- Severity: **Medium**.
- Steps to reproduce: Inspect CI configuration; no mandatory job starts Postgres, applies migrations and drives the critical mobile/API flows.
- Suggested solution: Add CI with disposable Postgres, migrations, API contract tests and an Android integration suite; schedule a read-only production health smoke.
- Estimated implementation complexity: High, 3-6 days.

### A-07: Progress-photo files are not encrypted at rest on device

- Screen: Progress photos.
- Description: Metadata databases are encrypted, but image bytes are stored as ordinary sandbox files. Source comments defer AES encryption.
- Why it matters: Body-progress imagery is sensitive health-adjacent data and deserves stronger protection on compromised devices/backups.
- Severity: **Medium**.
- Steps to reproduce: Save a progress photo and inspect the app Documents photo directory on a test device.
- Suggested solution: Encrypt each file with an authenticated cipher and a platform-keystore-protected key; retain the now-tested erasure path.
- Estimated implementation complexity: High, 3-5 days plus migration testing.

### A-08: PostgreSQL media storage is durable but not the long-term scaling target

- Screen: Avatars, feed photos and stories.
- Description: New media now survives stateless deploys and remains policy-protected, but storing up to 1.8 MB per image in the primary relational database increases backup size, I/O and database cost.
- Why it matters: Growth in social media can degrade the same database serving workouts, ranks and auth.
- Severity: **Medium**.
- Steps to reproduce: Observe the `stored_media` table and project storage growth at expected photo volume.
- Suggested solution: Move bytes to encrypted S3/R2-compatible object storage with private keys/signed delivery; retain database ownership metadata and migrate existing rows in batches.
- Estimated implementation complexity: High, 4-8 days plus infrastructure.

### A-09: Client networking remains fragmented

- Screen: Multiple service and integration flows.
- Description: 28 Dart files still invoke `http.*` directly. Timeout, token refresh, request IDs, cancellation and error handling can diverge.
- Why it matters: Expired sessions and slow networks may behave differently between otherwise similar screens.
- Severity: **Medium**.
- Steps to reproduce: Search direct `http.get/post/put/patch/delete` calls under `app/lib`.
- Suggested solution: Migrate feature-by-feature to one authenticated API client with typed errors, deduplicated refresh, timeout policy and observability hooks.
- Estimated implementation complexity: High, 5-10 days incrementally.

### A-10: Unsafe raw-SQL APIs remain in stats and segments

- Screen: Stats and GPS segment APIs.
- Description: Twelve `$queryRawUnsafe` references remain. Current runtime parameters are bound, so no injection was confirmed, but the API permits future interpolation mistakes.
- Why it matters: A later edit can silently turn a safe query into an injection vulnerability.
- Severity: **Medium**.
- Steps to reproduce: Search `$queryRawUnsafe` under `backend/src`.
- Suggested solution: Convert to Prisma tagged SQL/typed SQL and add a lint/review prohibition for unsafe raw queries.
- Estimated implementation complexity: Medium, 2-4 days.

### A-11: Expected offline failures are reported as nonfatal errors

- Screen: Offline restart, warmup/history/notification/FCM requests.
- Description: Airplane-mode testing stayed usable, but several expected `SocketException` paths were sent to the crash reporter.
- Why it matters: Crashlytics noise can hide real defects and distort stability triage.
- Severity: **Medium**.
- Steps to reproduce: Enable airplane mode, restart, inspect debug/crash-reporter output.
- Suggested solution: Classify connectivity failures as breadcrumbs/metrics, not exceptions, unless retries are exhausted in a user-blocking flow.
- Estimated implementation complexity: Low, 1-2 days.

### A-12: Renderer and cold-start performance are not signed off on hardware

- Screen: App launch and animation-heavy screens.
- Description: The emulator logged a first-launch skipped-frame burst, and Android explicitly disables Impeller in favor of Skia due to GPU concerns.
- Why it matters: Low/mid-tier devices may show jank or GPU-specific crashes that the emulator cannot reveal.
- Severity: **Medium**.
- Steps to reproduce: Profile cold/warm launch and scroll with Flutter DevTools on representative physical GPUs.
- Suggested solution: Define startup/frame budgets, profile release mode, validate current Skia choice and revisit Impeller with a device allow/test matrix.
- Estimated implementation complexity: Medium, 2-4 days.

### A-13: Release artifact size needs optimization

- Screen: Installation and update funnel.
- Description: The universal APK is 110.6 MB and the AAB is 73.8 MB before store delivery splitting.
- Why it matters: Large downloads increase abandonment, update friction and storage complaints.
- Severity: **Medium**.
- Steps to reproduce: Inspect the release artifacts listed in Verification Evidence.
- Suggested solution: Run size analysis, compress/remove unused bitmap/audio/database assets, verify native library splits and set a release size budget.
- Estimated implementation complexity: Medium, 2-5 days.

### A-14: Full screen-reader walkthrough is incomplete

- Screen: Entire app, especially complex sheets, charts, maps and workout controls.
- Description: Automated semantics and Android hierarchy checks improved key controls, but TalkBack and VoiceOver were not used end to end.
- Why it matters: Focus order, announcements, chart alternatives and modal trapping cannot be proven statically.
- Severity: **Medium**.
- Steps to reproduce: Complete all critical flows using TalkBack/VoiceOver with the screen hidden.
- Suggested solution: Run an assistive-technology test script and fix focus order, merged labels, live regions and chart summaries.
- Estimated implementation complexity: Medium, 2-5 days depending on findings.

### A-15: Dynamic type coverage stops short of the full 2.0x matrix

- Screen: Dense forms, cards, sheets and workout tracker.
- Description: The global cap is removed and sampled 1.6x screens passed, but every route was not exercised at 2.0x or with longest localized copy.
- Why it matters: Remaining clipping can block users who rely on the largest text settings.
- Severity: **Medium**.
- Steps to reproduce: Set 2.0x text and traverse all routes, including landscape and keyboard-open states.
- Suggested solution: Add parameterized full-screen widget/golden tests at 1.0x, 1.6x and 2.0x and allow controls to wrap/reflow.
- Estimated implementation complexity: Medium, 2-4 days.

### A-16: Guest progress cannot be merged into an already-existing account

- Screen: Profile > Account > Save account > Sign in.
- Description: Creating a new email account preserves the guest `userId`. Signing into an existing account is a deliberate account switch; the app now warns that the guest account/data will be deleted, but it cannot merge the two data sets.
- Why it matters: A returning user who trained as guest must choose between old account history and new guest progress.
- Severity: **Medium**.
- Steps to reproduce: Log workouts as guest, open Save account, toggle to Sign In and read the switch confirmation.
- Suggested solution: Design a server-side merge policy for workouts/profile data with conflict handling, audit logs and explicit user confirmation.
- Estimated implementation complexity: High, 5-10 days.

### A-17: Google Sign-In was not validated with a real production identity

- Screen: Login and onboarding account access.
- Description: Token validation code exists, but this audit did not complete the external Google consent/token flow on a signed release build.
- Why it matters: OAuth client IDs, SHA fingerprints and consent configuration can fail only in production signing conditions.
- Severity: **Medium**.
- Steps to reproduce: Install the signed build from a store/internal track and complete Google login with new and returning accounts.
- Suggested solution: Add production OAuth fingerprints/client IDs and maintain a release smoke account for both account states.
- Estimated implementation complexity: Medium, 1-3 days plus console access.

### A-18: Empty catches reduce observability

- Screen: Best-effort sync, caches and optional UI flows.
- Description: Twenty-eight `catch (_) {}` sites remain. Many are intentional, but they erase diagnostic context.
- Why it matters: Silent failures make intermittent sync/data defects hard to reproduce.
- Severity: **Low**.
- Steps to reproduce: Search `catch (_) {}` under `app/lib`.
- Suggested solution: Classify each site; add sampled breadcrumbs for meaningful failures and document truly ignorable cases.
- Estimated implementation complexity: Medium, 2-3 days.

### A-19: The shipped UI is effectively English-only

- Screen: Settings > Language and all product copy.
- Description: Only English is selectable; many strings remain outside generated localization resources.
- Why it matters: It limits market readiness and makes later translation/layout work more expensive.
- Severity: **Low** for an English-only launch; Enhancement otherwise.
- Steps to reproduce: Open Language settings and inspect localization resources.
- Suggested solution: Finish string extraction, add target locales, pseudo-localization and long-copy layout tests before advertising localization.
- Estimated implementation complexity: High, 5-10 days plus translation.

### A-20: Journal data remains local-only

- Screen: Journal.
- Description: Journal entries are not synchronized to the backend, as documented by a source TODO.
- Why it matters: Entries do not follow the user to another device and may be lost on uninstall/device loss.
- Severity: **Enhancement**.
- Steps to reproduce: Create an entry and inspect API traffic/data on another device.
- Suggested solution: Add encrypted journal endpoints, offline sync/conflict policy, export and deletion coverage.
- Estimated implementation complexity: High, 4-8 days.

## 13. Quick Wins

- Add valid iOS Firebase options and fail CI when any `REPLACE_*` production value remains.
- Remove the unreachable `_PremiumSheet` until billing is implemented.
- Reclassify expected offline `SocketException` events as breadcrumbs.
- Add a CI job for `flutter analyze`, `flutter test`, backend build/test and both dependency audits.
- Add 2.0x tests for login, workout tracker, nutrition sheets and Profile Account.
- Replace the first simple `$queryRawUnsafe` queries with tagged Prisma SQL and establish the pattern.
- Add a store-track install check using the signed AAB before each release.
- Record artifact size and hashes automatically in release output.

## 14. Long-Term Improvements

- Migrate media bytes from PostgreSQL to private object storage before high social-media volume.
- Build a disposable real-stack E2E environment and make it a protected-branch gate.
- Consolidate all mobile transport behind one typed API client.
- Implement server-assisted guest/existing-account merge with conflict resolution.
- Add performance budgets, startup telemetry, API p95 dashboards and load tests against ranking/feed paths.
- Complete RevenueCat and store-server notification/webhook verification.
- Establish physical-device and OS-version release matrices for health, camera, push and background behavior.
- Complete localization architecture and pseudo-localization.

## 15. Technical Debt

- 28 Dart files with direct HTTP calls.
- 12 unsafe raw-SQL API references, despite current parameter binding.
- 28 empty catches with uneven observability.
- 91 packages have newer versions outside current constraints; this is maintenance debt, not a confirmed vulnerability.
- Dead Premium prototype code remains unreachable.
- Media uses the primary PostgreSQL database as an MVP durability layer.
- Progress-photo encryption and journal sync are deferred by explicit TODOs.
- Production smoke is scripted but not yet enforced by CI.

## 16. UX Improvements

- Offer a future merge option when a guest signs into an existing account.
- Keep the Save account action visible until conversion and explain the benefit before users accumulate substantial guest history.
- Add explicit offline/sync status to data-changing flows, not only background logs.
- Replace unavailable integration rows with feature flags or a single optional roadmap area.
- Show real service states for external integrations and actionable recovery when authorization expires.
- Reduce the login screen's vertical distance to the account-mode toggle on shorter devices.

## 17. UI Improvements

- Complete 2.0x and longest-copy checks for every bottom sheet and compact control.
- Validate chart/map alternatives and focus order under screen readers.
- Profile startup and animation-heavy screens on low/mid-tier GPUs before deciding the long-term renderer setting.
- Run a size/asset audit and compress high-cost visual assets without changing the approved design.
- Remove unreachable billing UI to reduce maintenance and accidental reactivation.

## 18. Missing Features Worth Considering

- RevenueCat purchase, restore and entitlement management.
- Guest-to-existing-account data merge.
- Cross-device journal sync.
- Full iOS push, HealthKit and production OAuth configuration.
- Additional languages after full string extraction.
- Object-storage media pipeline with lifecycle/retention policies.
- User-visible sync queue/retry center for offline changes.
- Account recovery beyond email code where social-only identities are used.

## 19. Risks That Could Affect User Reviews

- iOS startup, push or OAuth failures if released with placeholder configuration.
- Camera/health/background defects that appear only on physical OEM hardware.
- Missing subscriptions or restore purchases if marketing promises Premium at launch.
- Large download/install size, especially on constrained devices or networks.
- First-launch jank or GPU-specific issues on low/mid-tier Android phones.
- Losing guest progress when deliberately switching to an existing account, despite the new warning.
- English-only UX in markets where localized store listings imply broader support.
- Noisy or delayed behavior on poor networks where direct HTTP paths differ.

## 20. Final Recommendation

**Needs Significant Work Before Release**

Do not use this assessment to block a monitored Android internal/closed beta: the tested Android/backend core is strong enough for that stage. Do block a public cross-platform launch until A-01 through A-05 are closed with evidence. If subscriptions are intentionally deferred and the launch is Android-only, the remaining bar can be reassessed after Play internal-track and physical-device validation.
