# FEATURE_SUGGESTIONS — Zvelt

**Purpose:** Capture ideas surfaced during the Play-readiness audit that fall outside the "ship v1.0 today" scope. **DO NOT BUILD** any of these without explicit owner approval. Per the directive (Rule 1), the team will not add features or change UX during the Play-submission push.

**Generated:** 2026-05-26

---

## Format

Each entry: title — origin (where it came up) — short description — recommended timeline (v1.1, v1.2, post-launch, never).

---

## 1. Photo Progress Tracking — `v1.1`

- **Origin:** `lib/screens/analytics/progress_hub_screen.dart:1158` had a `COMING SOON` card. Removed for v1.0 per `QA_BACKLOG.md` P0.1.
- **Idea:** Periodic body photos (front, side, back), encrypted local storage with optional encrypted backend backup, side-by-side compare slider, 30/60/90-day reveal banners.
- **Complexity:** Medium. Needs encrypted storage, image upload, comparison UI, retention policy, GDPR-compliant deletion.
- **Recommended timeline:** v1.1, after first cohort of paying users requests it.

---

## 2. Biology Tab Full UI — `v1.0 if time, else v1.1`

- **Origin:** `lib/screens/biology/biology_tab.dart` is a UI skeleton. `HealthService` already returns the data.
- **Idea:** Dedicated tab showing trends over time for VO₂ max, HRV, resting HR, sleep stages, weight, body fat, blood oxygen, ECG (if available). 30/90/365-day toggles. "What changed" insights ("Your HRV dropped 12% — likely the late-night training. Cap intensity tomorrow.").
- **Complexity:** Medium-high. Chart-heavy. AI insights need backend or local heuristics.
- **Recommended timeline:** Hide tab from main shell for v1.0. Ship in v1.1.

---

## 3. Journal Feature — `post-launch`

- **Origin:** `lib/screens/journal/journal_tab.dart` is empty placeholder. No backend.
- **Idea:** Daily mood / energy / soreness / notes log. AI uses entries to adjust suggestions.
- **Complexity:** Medium. New backend table, sync, UI.
- **Recommended timeline:** Per CLAUDE.md roadmap this is post-launch. Hide tab for v1.0.

---

## 4. RevenueCat / Pro Tier — `v1.1` (highly recommended within 30 days post-launch)

- **Origin:** Onboarding Step 23 paywall is visual only. `purchases_flutter` not in `pubspec.yaml`. No paywall enforcement anywhere.
- **Idea:** Per CLAUDE.md spec — Pro tier with unlimited AI coach, advanced analytics, program builder, etc. RevenueCat SDK + Play Billing.
- **Complexity:** Medium. SDK integration is fast; gating each feature behind entitlement check is the time sink. Backend webhook for RevenueCat.
- **Recommended timeline:** Ship v1.0 free-only. Add Pro in v1.1 (~2-4 weeks post-launch) once we have real usage data to price correctly.

---

## 5. Outdoor → Workouts Unified Flow — `v1.0 (if time)` or `v1.1`

- **Origin:** `lib/screens/outdoor/outdoor_track_screen.dart` tracks GPS but doesn't persist as a workout.
- **Idea:** When user ends outdoor session, it's automatically saved as a `workout_type=cardio_outdoor` workout with route_points, distance, pace, elevation. Show on activity calendar.
- **Complexity:** Low. Existing `WorkoutService` already accepts cardio workouts. Just wire the save.
- **Recommended timeline:** v1.0 if we can fit it. Otherwise v1.1.

---

## 6. Server-Side Rest-Time Tracking — `v1.1`

- **Origin:** `lib/widgets/charts/rest_time_trend.dart:82` placeholder text removed in P0.3.
- **Idea:** Each set logs `rest_started_at` and `rest_ended_at`. Backend computes average / variance per exercise per session. "Rest analytics" chart shows trend.
- **Complexity:** Medium. Schema change (`workout_sets.rest_started_at`, `rest_ended_at` columns). Client timer instrumentation. Aggregate query.
- **Recommended timeline:** v1.1.

---

## 7. Real Map Tiles in Quick-Launch Sheet — `decision`

- **Origin:** `lib/screens/workouts/quick_launch_sheet.dart` has a `// Cardio mock animation` with fake street labels.
- **Idea:** Replace mock map with real OpenStreetMap tiles showing user's last route. Or label clearly as "Preview" if intentional onboarding.
- **Recommended action:** **Owner decision** — is the quick-launch animation intentional marketing/demo, or should it be replaced with real data?

---

## 8. Strava OAuth — `v1.0`

- **Origin:** CLAUDE.md spec includes `POST /v1/integrations/strava/exchange`. No client service found.
- **Idea:** Settings → Integrations → "Connect Strava" → OAuth flow → on success, periodic sync of Strava workouts into Zvelt.
- **Complexity:** Low. Backend endpoint exists. Need `IntegrationsService.exchangeStravaCode(code)` + Settings UI.
- **Recommended timeline:** v1.0 if backend is ready. Otherwise v1.1.

---

## 9. Workout Auto-Save / Resume — `v1.0` (recommended)

- **Origin:** `QA_BACKLOG.md` P1.11. If app is killed mid-workout, client state is lost.
- **Idea:** On every set save, persist `workout_id` locally. On app start, check for in-flight workout → offer "Resume workout?" dialog.
- **Complexity:** Low.
- **Recommended timeline:** v1.0 — small effort, big UX win.

---

## 10. Backend-served Race Quick-Replies — `v1.1`

- **Origin:** `lib/screens/social/race_hub_screen.dart:589` hardcoded `['140KG?', 'TOO SLOW!', 'KEEP DREAMING']`.
- **Idea:** Backend serves localized, A/B-testable quick-reply pool.
- **Complexity:** Low.
- **Recommended timeline:** v1.1.

---

## 11. Page Cache Invalidation on Push — `v1.1`

- **Origin:** `lib/screens/main_screen.dart` page cache doesn't auto-refresh.
- **Idea:** When a relevant push notification arrives (new like, comment, friend request), invalidate the cached page so it refreshes on next visit.
- **Complexity:** Low-medium. Need a global event bus or Riverpod/Bloc state.
- **Recommended timeline:** v1.1.

---

## 12. Anti-Cheat Enforcement Client UI — `v1.1`

- **Origin:** CLAUDE.md has anti-cheat rules (max 3 edits / 24h, jump SR >20% flag, weight >2× max → confirm + note).
- **Idea:** Client surfaces these gates clearly: "This is 2.3× your previous Bench PR — please confirm and add a note explaining."
- **Complexity:** Medium.
- **Recommended timeline:** v1.1.

---

## 13. Wear OS Companion — `v2.0`

- **Origin:** CLAUDE.md roadmap mentions Companion Watch.
- **Idea:** Wear OS app for set logging, rest timers, HR monitoring during workouts.
- **Complexity:** High. Separate app.
- **Recommended timeline:** v2.0.

---

## 14. Program Builder — `v1.2+`

- **Origin:** CLAUDE.md roadmap.
- **Idea:** Pro feature — drag-and-drop weekly program builder, templates, copy-from-friend.
- **Complexity:** High.
- **Recommended timeline:** v1.2.

---

## 15. Challenges & Quests — `v1.1`

- **Origin:** CLAUDE.md gamification.
- **Idea:** Basic quests in v1.0 onboarding (e.g., "First workout = +50 XP"). Extended quest system post-launch.
- **Complexity:** Medium.
- **Recommended timeline:** v1.1.

---

## 16. Creator Plans Marketplace — `v2.0`

- **Origin:** CLAUDE.md roadmap, late 2026.
- **Idea:** Verified creators publish training programs; users subscribe.
- **Complexity:** Very high.
- **Recommended timeline:** v2.0.

---

## 17. Localization Beyond English — `v1.1+`

- **Origin:** Directive Rule 4 says minimum English fully translated.
- **Idea:** Add Romanian (`ro_RO`), Spanish (`es_ES`), German (`de_DE`) based on user geography after launch.
- **Complexity:** Low per language (just translations).
- **Recommended timeline:** Driven by user data.

---

## 18. In-App Account Deletion UX Polish — `v1.0`

- **Origin:** `QA_BACKLOG.md` P0.9. Required by Play.
- **Idea:** Currently must build the minimum. Polish: re-onboarding offer if user deletes, exit survey, "soft delete with 30-day undo" UX.
- **Complexity:** Low for minimum. Medium for full UX.
- **Recommended timeline:** Minimum in v1.0; polish in v1.1.

---

## 19. Privacy Controls Granularity — `v1.1`

- **Origin:** CLAUDE.md "Privacy by default" — feed friends-only, discovery opt-in.
- **Idea:** Per-post privacy override (e.g., post this one workout publicly even if account is private). Per-metric sharing toggles.
- **Complexity:** Medium.
- **Recommended timeline:** v1.1.

---

## OWNER DECISIONS NEEDED

The following items require an owner call before development can proceed:

1. **Photo Progress (item 1)** — kill for v1.0 or attempt to ship? Recommendation: **kill**.
2. **Biology tab (item 2)** — hide for v1.0 or rush in? Recommendation: **hide**.
3. **Journal (item 3)** — hide for v1.0? Recommendation: **hide**.
4. **RevenueCat (item 4)** — ship free-only or block submission? Recommendation: **ship free-only**.
5. **Quick-launch mock map (item 7)** — leave as-is or replace? Recommendation: **leave as marketing preview, label clearly as 'Preview'**.
6. **Strava OAuth (item 8)** — verify backend, then ship in v1.0?
