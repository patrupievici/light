# ZVELT Release Readiness Audit

Audit date: 2026-07-16

Audited code revision: `ea11c4a` (production API behavior verified on `cc88c3f`; `ea11c4a` only changes Android build resolution)

Production API: `https://light-l6en.onrender.com`
Scope: Flutter client, Fastify/Prisma backend, PostgreSQL migrations, Android release artifacts, Android emulator, production API, privacy, security, accessibility, UX, product and operational launch readiness.

## 1. Executive Summary

ZVELT is materially stronger than the first audit. The previously identified critical dependency vulnerability, private-media bypass, incomplete account erasure, nutrition target mismatch, theme navigation reset, stale mounted-tab appearance, red Flutter suite, misleading Premium action, unlabeled controls and inaccessible guest-account flow have been repaired and retested. This follow-up also removes the redundant Home settings/strength controls, consolidates every setting under Profile and replaces the colour-banded card material with stable neutral matte surfaces.

A production-backed 30-day power-user simulation now exercises all 11 strength programs, 30 strength sessions, 367 completed sets, 30 runs, 30 rides, 30 nutrition days, 10 workout posts, ranking, PR filtering, calendar sync and account erasure. The final run made 801 paced requests: 822 of 824 assertions passed, every response was 2xx, no rate limit or server error occurred, and cleanup succeeded. The only failed assertions were the declared latency SLOs: read p95 was 608 ms against 300 ms and write p95 was 1,136 ms against 800 ms.

The audit found and closed additional release defects during that simulation: explicit run/ride type was not preserved across every surface; GPS sessions were absent from the calendar; backfilled volume and PRs used upload time; first-time programs generated 0 kg weighted sets; PR posts lost their PR state after ranking at workout completion; program creation/ranking used avoidable serial database calls; and a clean Android release build resolved an alpha WorkManager dependency that was incompatible with the plugin JVM target.

The current Android/backend candidate is suitable for an internal or tightly monitored closed beta. It is not yet ready for a public cross-platform launch tomorrow. Functional API correctness is stable, but production latency is above its declared SLO; outside the core, iOS Firebase configuration is placeholder-only, no iOS release was built or device-tested, RevenueCat billing is absent, store submission was not performed, and Health/Strava/Google/camera/background behavior has not been validated on representative physical devices.

No Critical issue remains in the audited Android/backend path. Five unconditional High launch issues remain, plus RevenueCat as a sixth High if subscriptions are part of launch. The recommendation is intentionally strict because the stated product is cross-platform and the public-launch bar includes API latency, billing, hardware integrations and both stores.

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
- Repaired live theme propagation for mounted Home, Plan, Feed and Nutrition tabs plus Profile, Settings and the Appearance sheet; Dark/Light changes now repaint without resetting tab state.
- Added meaningful semantics and 48dp targets to the audited icon controls.
- Kept strength workout creation in Plan while removing the redundant Home CTA requested by product ownership.
- Removed the Home settings gear and routed both Profile settings entry points to the complete shared Settings hub.
- Added `Delete account` directly below `Sign out` in Profile Settings while retaining the existing confirmed erasure flow.
- Moved Legal, cache reload, diagnostic reporting, diagnostics consent, social links and version details into the Settings route reached from Profile.
- Replaced transparent coloured card gradients with neutral, nearly opaque matte surfaces and shorter shadows; verified dark and light themes on the Android emulator.
- Removed 280 lines of duplicated Profile settings implementation and added ordering, narrow-screen, golden and card-neutrality regression tests.
- Removed unnecessary Android broad media permission; retained camera permission only where required.
- Added production release identification and a repeatable production smoke suite.
- Preserved explicit run/ride types from Flutter through offline replay, REST storage, feed and calendar sync.
- Merged server cardio history into the local offline-first activity store without duplicate sessions.
- Corrected cumulative-volume and recent-PR dates to use the parent workout date instead of upload time.
- Added safe, explainable first-session program loads while retaining 0 kg only for bodyweight/no-load exercises.
- Batched program workout/set creation and ranking writes, and parallelized independent completion/calendar work.
- Persisted workout PR outcomes at ranking time so later posts remain visible in the PR feed without a duplicate ranking calculation.
- Added a reusable strict 30-day production simulation with automatic GDPR cleanup and route-level latency reporting.
- Pinned AndroidX WorkManager to stable `2.11.2` and aligned `home_widget` to JVM 17, restoring reproducible APK/AAB release builds.

## 2. Overall Application Score

**81 / 100**

The core Android/backend product is functional, privacy-aware and extensively tested. The score is held below release-ready range by measured API SLO misses, unvalidated iOS/store/hardware paths, incomplete billing and remaining architectural debt.

## 3. UI Score

**90 / 100**

The approved visual design is consistent across Home, Plan, Feed, AI, Nutrition, Profile and Settings. The diagonal colour bands reported on Home/Profile cards are gone in the installed release APK; dark and light surfaces are neutral, readable and stable. Manual Dark -> Light -> Dark switching now keeps Home, Profile, Settings, the Appearance sheet and bottom navigation in one coherent mode without relaunching. Manual portrait, landscape and 1.6x text checks found no overflow in sampled release screens. Remaining deductions cover limited 2.0x coverage, a scroll-heavy login screen and incomplete cross-platform visual validation.

## 4. UX Score

**83 / 100**

Core activation is clear: strength remains discoverable in Plan, Home is less cluttered, all settings now have one predictable home under Profile, guest users can save progress, account deletion is complete, and AI no longer redirects meal questions into workout tracking. Remaining friction includes no account-data merge into an existing account, incomplete integrations and several visible future-feature surfaces.

## 5. Performance Score

**66 / 100**

Release APK/AAB builds complete, scrolling was stable on the emulator, lazy screen construction and caches are present, and production smoke completed successfully. Database batching reduced post p95 from 1,957 ms to 975 ms and program start-day p95 from 2,844 ms to 1,297 ms. The score is intentionally lower now that measurement is available: final read p95 was 608 ms versus the 300 ms SLO, write p95 was 1,136 ms versus 800 ms, and workout completion p95 remained 2,357 ms. Risk also remains around a 110.6 MB universal APK, a 73.8 MB AAB, first-launch frame skips, Skia being forced instead of Impeller and no physical low/mid-tier device profiling.

## 6. Accessibility Score

**79 / 100**

Automated accessibility tests pass, audited controls have labels and 48dp targets, system text scaling is no longer capped, and sampled screens survived 1.6x text and landscape. A complete TalkBack/VoiceOver pass and 2.0x full-screen test matrix are still missing.

## 7. Code Quality Score

**85 / 100**

Static analysis is clean, backend tests are broad, migrations are versioned, release smoke and the month simulation are repeatable, and high-risk auth/media/ranking/sync logic has focused regression tests. The duplicated Profile settings sheet was deleted; visual regression coverage includes both card themes plus mounted-tab rebuilding with State preservation. Deductions remain for 28 direct HTTP client files, 12 `$queryRawUnsafe` call sites, 28 empty catches and some dead/incomplete feature code.

## 8. Product Score

**78 / 100**

Workout, all 11 programs, ranking/PR posts, social, nutrition, running, cycling, AI and account-management journeys are coherent under a full synthetic month. Product completeness is reduced by unavailable subscriptions, partial wearable/integration surfaces, English-only UI and local-only journal data.

## 9. Security Score

**88 / 100**

Dependency audit is clean; bearer sessions, CORS, private media, deletion, token storage and production headers were hardened and tested. Remaining concerns are unencrypted local progress-photo bytes, unsafe raw-SQL APIs, incomplete external-provider validation and the need to move durable media to dedicated object storage at scale.

## 10. Stability Score

**94 / 100**

Flutter tests pass `216/216`; backend tests pass `854/854`; Flutter analysis and TypeScript builds are clean; production smoke passes `113/113` after both backend releases; the strict month simulation has zero functional failures, zero 5xx/429 and successful account cleanup. Reinstalling the current signed release over itself preserved the guest session. Residual risk is dominated by latency SLO misses plus devices, platforms and upgrade paths not fully exercised in this Windows/Android-emulator audit.

## 11. Launch Readiness Score

**68 / 100**

- Android closed beta: acceptable with monitoring.
- Public Android release: close, but API SLO, physical-device and store checks remain.
- Public iOS + Android release: blocked by iOS configuration/build validation, billing and operational store readiness.

### UI Technical Health

| Dimension | Score (0-4) | Key finding |
| --- | ---: | --- |
| Accessibility | 3 | Labels/targets and scaling are good; full TalkBack/VoiceOver remains |
| Performance | 3 | No per-card blur; physical-device profiling remains |
| Responsive design | 3 | Narrow-phone/golden checks pass; full 2.0x matrix remains |
| Theming | 4 | Shared tokens, live dark/light propagation and neutral-card regression pass |
| Anti-patterns | 3 | Colour bands are gone; the product still uses a card-heavy vocabulary |
| **Total** | **16/20** | **Good** |

Anti-pattern verdict: **Pass with restraint recommended**. The release no longer shows random diagonal colour bands or decorative blur on repeated cards. Orange is used for active/primary states, but future screens should avoid adding more glow or nested cards.

### Verification Evidence

| Check | Result |
| --- | --- |
| `flutter analyze` | Pass, no issues |
| Flutter test suite | Pass, 216 tests |
| Backend TypeScript build | Pass, including `prisma generate` |
| Backend test suite | Pass, 72 files, 854 tests |
| Prisma schema validation | Pass |
| Production dependency audit | 0 vulnerabilities |
| Full backend dependency audit | 0 vulnerabilities |
| Production smoke, production API | 113/113 pass after each final backend deploy; owner/viewer/guest accounts cleaned |
| Strict 30-day production simulation | 822/824 pass; only read/write latency SLO assertions fail; 801/801 responses are 2xx; cleanup succeeds |
| APK release build | Pass, 115,973,081 bytes |
| AAB release build | Pass, 77,403,841 bytes |
| APK SHA-256 | `D4ABB2B82F7A8EED395D3DC328204A1AB131EF8E3417D21C605B27927C668F3D` |
| AAB SHA-256 | `6FF2373F7E727CEDF1BD12347BB274CA141DE9E7FBEE9AE037B4E07DBEC8012B` |
| Android signing | Pass, signer `CN=Zvelt, OU=Mobile, O=Zvelt, C=RO` |
| Manual emulator screens | Current release APK installed with `adb install -r`; Dark -> Light recolours Home, cards, icons and bottom navigation without relaunch or black remnants |
| UI hierarchy contract | Home exposes no Settings gear/strength CTA; Delete account follows Sign out; support/footer controls are reachable |
| Release reinstall | Pass: signed release installed with `adb install -r`, guest session preserved on restart |
| Card material regression | Pass: dark/light gradients constrained to neutral channels and alpha >= `0xED` |
| Theme-state regression | Pass: mounted tabs rebuild on appearance changes without losing local State; unvisited tabs remain lazy |
| Offline restart | Pass: authenticated cached Home remained usable; requests failed without crash |
| Rotation | Pass on sampled landscape screen |
| Text scale | Pass at 1.6x on sampled Home/onboarding screens |
| Private media without authorization | Rejected |
| Deleted access/refresh sessions | Rejected |
| Guest conversion | Same user id, data preserved, old credentials revoked |
| Durable media across Render deployment | Pass: `200`, 68 bytes, `e36f69c538ba` -> `76e6e2e536ce`; probe cleanup `204` |

### 30-Day Power-User Simulation

The reusable test is `backend/scripts/month-power-user-simulation.mjs` (`npm run simulate:power-month`). It uses a unique temporary account, remains below the configured global rate limit at one request every 700 ms, records route latency and deletes the account in `finally` even on failure.

| Dimension | Final production result |
| --- | --- |
| Window | 2026-06-15 through 2026-07-14 |
| Workload | 11/11 programs, 30 strength workouts, 367 completed sets, 30 runs, 30 rides, 30 nutrition days, 10 private workout posts |
| API outcomes | 801 requests: 460 x 200, 340 x 201, 1 x 204; 0 x 4xx/5xx; 0 rate-limit retries |
| Functional assertions | All pass: program loads, tracker payloads, workout list, explicit run/ride type, 90-item unified feed, 30-day gym/run/ride calendar, nutrition, cumulative volume, historical PR dates, ranking, PR feed and profile posts |
| Read SLO | **Fail:** p95 608 ms, target <300 ms |
| Write SLO | **Fail:** p95 1,136 ms, target <800 ms |
| Slow write routes | workout complete p95 2,357 ms; program start-day p95 1,297 ms; post p95 975 ms |
| Cleanup | Account deletion 204; temporary production data removed |

The fixes materially improved latency without changing behavior: post p95 fell from 1,957 ms to 975 ms, start-day from 2,844 ms to 1,297 ms and global write p95 from 1,871 ms to 1,136 ms between the two comparable final runs. The declared SLOs are nevertheless still unmet and remain a launch risk rather than a closed item.

### Audit Limits

- No macOS host was available, so iOS compilation/signing could not be performed.
- No App Store Connect or Play Console publishing action was available in this workspace.
- No representative physical iPhone or Android handset was tested.
- The first transition from the previously installed legacy build to this release landed in onboarding once. A second release-over-release update preserved the guest session and the issue was not reproduced; a formal legacy-version upgrade matrix is still required before public rollout.
- Google Sign-In, Strava, HealthKit, Health Connect, camera and push delivery require external accounts/hardware and were not completed end to end.
- Concurrent multi-user load, server-process soak, low-memory, thermal and long-duration background tests were not run; the month simulation is sequential and does not replace them.

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

- Screen: Camera, HealthKit, Health Connect, Strava, push, background/foreground, app upgrades and low-memory recovery.
- Description: Emulator checks cannot validate OEM camera providers, health permissions, Bluetooth/wearable behavior, APNs/FCM delivery, process death, GPU-specific rendering or every legacy-to-current data migration. One legacy-build update entered onboarding once; current-release reinstall preserved the guest session.
- Why it matters: These failures commonly produce one-star reviews and can affect sensitive health data.
- Severity: **High**.
- Steps to reproduce: Run the named flows on a low-tier Android, modern Android and two iPhone versions; evidence is currently absent.
- Suggested solution: Establish a release matrix with physical devices and scripted expected results, including permission denial/revocation, process death and upgrades from every publicly distributed version while preserving guest/authenticated sessions and local queues.
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

### A-11: Production API misses its declared latency SLOs

- Screen: Remote data flows, especially workout completion, program start-day, post creation and list/feed reads.
- Description: A single power-user simulation, paced below rate limits and without concurrent load, measured read p95 at 608 ms against the <300 ms SLO and write p95 at 1,136 ms against <800 ms. Workout completion p95 was 2,357 ms. Batching improved all major write paths, but did not close the target.
- Why it matters: Slow completion can look like a frozen save, encourage repeat taps and make post-workout/ranking feedback feel unreliable. Real concurrent traffic can be slower than this single-user run.
- Severity: **High** for a public launch.
- Steps to reproduce: Run `$env:ZVELT_STRICT='1'; npm.cmd run simulate:power-month` in `backend` against production and inspect the route latency summary.
- Suggested solution: Co-locate Render and PostgreSQL, add per-query/APM spans, move non-response-critical ranking/challenge work to a durable job queue, cache/batch media/feed reads, then run controlled concurrent load tests until p95 budgets hold with headroom.
- Estimated implementation complexity: High, 3-7 days plus possible infrastructure migration.

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
- Add APM spans around workout completion, program materialization, streak updates and feed/media enrichment before the next optimization pass.
- Add a CI job for `flutter analyze`, `flutter test`, backend build/test and both dependency audits.
- Add 2.0x tests for login, workout tracker, nutrition sheets and Profile Account.
- Replace the first simple `$queryRawUnsafe` queries with tagged Prisma SQL and establish the pattern.
- Add a store-track install check using the signed AAB before each release.
- Add a staged upgrade test from every previously distributed APK and assert that guest/authenticated sessions, onboarding state and offline queues survive.
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
- Expected offline `SocketException` paths still create nonfatal crash-reporting noise.
- Production latency budgets are declared but not enforced by CI or deployment gates.
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
- A legacy-version update could return a guest to onboarding; same-release reinstall passed, but the complete upgrade matrix is not yet signed off.
- Losing guest progress when deliberately switching to an existing account, despite the new warning.
- English-only UX in markets where localized store listings imply broader support.
- Noisy or delayed behavior on poor networks where direct HTTP paths differ.
- Workout completion and posting may feel stalled on ordinary networks because production p95 already exceeds the declared SLO before concurrent launch traffic.

## 20. Final Recommendation

**Needs Significant Work Before Release**

Do not use this assessment to block a monitored Android internal/closed beta: the tested Android/backend core is strong enough for that stage. Do block a public cross-platform launch until A-01 through A-05 and A-11 are closed with evidence. If subscriptions are intentionally deferred and the launch is Android-only, reassess after the API SLO holds under controlled load plus Play internal-track and physical-device validation.
