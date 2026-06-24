# HANDOVER — Zvelt V2 graphics push

_Last session: 2026-06-03 · Context: this file exists because the prior
session was running out of conversation context and Cip asked for a clean
hand-off so the next agent can pick up without re-discovering everything._

---

## Where we are right now

### Branches
- **`Clau`** — active branch with all V2 + AI work + Razvan merge (`c465490`) + V2 widget library + plug-ins. Tracks `clau/main` on the **private** repo `patrupievici/Clau`.
- **`backup-before-razvan-merge`** — safety snapshot before pulling in
  Razvan's massive commit. Restore via `git checkout` if anything is broken
  beyond repair.

### Repos
- **`origin`** = `patrupievici/zveltutzu` (public-ish; what Render auto-deploys)
- **`clau`** = `patrupievici/Clau` (private; full snapshot lives here)

### Current state (verified working)
- Backend typecheck: ✓ clean
- Backend tests: 39/39 passing
- Flutter analyze: 0 errors, ~25 info-level lints (prefer_const, all benign)
- APK builds: ✓ 126 MB (release, debug-signed for personal install)

### Last APK location
`C:\proiect\redesign\app\build\app\outputs\flutter-apk\app-release.apk`

---

## Design system (V2) — single source of truth

```
app/lib/theme/zvelt_tokens.dart       — color / radius / spacing tokens + ZType
app/lib/theme/app_theme.dart          — legacy AppTheme RE-EXPORTS V2 tokens so
                                        every widget that references the old
                                        names (bgPrimary, accentAmber, etc.)
                                        renders V2 light automatically.
                                        ALSO has Razvan-naming aliases
                                        (bg0/s1/t1/brand/warn/etc.) +
                                        gradBrand/gradBtn/barlowCondensed() —
                                        DO NOT remove these or all his
                                        widgets break.
app/lib/widgets/z/                    — V2 widget library:
  z_card.dart                         — ZCard (white surface, soft shadow, 24r)
  z_chip.dart                         — ZChip (neutral/brand/solid variants)
  z_eyebrow.dart                      — ZEyebrow (uppercase mono label)
  z_metric_tile.dart                  — ZMetricTile (4-up vital tile)
  z_vitals_row.dart                   — ZVitalsRow + .placeholder() factory
  z_sparkline.dart                    — ZSparkline (line OR bar mode)
  z_clean_stat_card.dart              — ZCleanStatCard (eyebrow + value + spark)
  z_weekly_progress_card.dart         — ZWeeklyProgressCard (M-S bars + counter)
  z_performance_trend.dart            — ZPerformanceTrend (smooth area chart)
  z_activity_grid.dart                — ZActivityGrid + .fromTrainingDays() helper
                                        + ZActivityGridLegend
  z_body_ring.dart                    — ZBodyRing + .strain/.recovery/.sleep
                                        factories + ZBodyRingsRow
```

### Conventions

**Always prefer `ZveltTokens.foo` + `ZType.bar` over `AppTheme.foo` in NEW
widgets.** Existing widgets that reference `AppTheme.*` keep working because
of the re-export — leave them unless you're explicitly restyling that file.

Common substitutions when restyling a legacy widget:

| Legacy (still works via alias) | Prefer in new code |
|---|---|
| `AppTheme.bgPrimary` | `ZveltTokens.bg` |
| `AppTheme.bgElevated` | `ZveltTokens.surface` |
| `AppTheme.textPrimary` | `ZveltTokens.text` |
| `AppTheme.textSecondary` | `ZveltTokens.text2` |
| `AppTheme.accentAmber` | `ZveltTokens.brand` |
| `AppTheme.border` | `ZveltTokens.border` (use sparingly; design prefers shadow over borders) |
| `AppTheme.radiusCard = 12` | `ZveltTokens.rLg = 24` |
| `TextStyle(fontFamily: 'Inter', fontSize: 16, color: ...)` | `ZType.bodyM` / `ZType.h3` / etc |
| `BoxDecoration(color: bgElevated, border: ..., borderRadius: 12)` | wrap content in `ZCard(...)` |

**Page background MUST be `ZveltTokens.bg` (cream) — not white.** Cards are
white. Cream-on-white is the V2 separation pattern. If a screen still has
`Scaffold(backgroundColor: AppTheme.bgPrimary)` it'll work (alias →
ZveltTokens.bg) but you can be explicit.

**Brand orange is a SIGNAL color** per design-system §2. Never use as decorative
fill on large surfaces. Acceptable: small icon halos (brandTint bg + brand
icon), CTA pills, ring progress, active states. NOT acceptable: full-width
gradient hero cards, big colored borders.

---

## What's BEEN DONE (current state — don't redo)

### Foundation
- ✅ Inter + IBM Plex Mono fonts installed in `app/assets/fonts/`
- ✅ ZveltTokens (1:1 mirror of tokens.css from design bundle)
- ✅ ZType utility text styles
- ✅ AppTheme rewritten to re-export V2 + Razvan aliases

### V2 widget library
- ✅ All 7 hero widgets built (see file list above)

### Train tab (`skeleton_home_tab.dart`)
- ✅ Greeting header V2 (avatar + date eyebrow + Inter greeting + ghost icon buttons)
- ✅ CoachTipCard V2 inserted after AiSuggestion
- ✅ ZBodyRingsRow plugged ("Today's body" hero, placeholder 62/68/84)
- ✅ ZVitalsRow.placeholder plugged
- ✅ ZActivityGrid + legend plugged (placeholder pattern from streak)
- ✅ ZWeeklyProgressCard plugged

### Progress tab — Training sub-tab
- ✅ WeeklyCoachReadCard at top (AI weekly read)
- ✅ ZPerformanceTrend (30-day volume series)
- ✅ ZCleanStatCard × 2 (Sessions + Active days)

### XP Complete screen
- ✅ CoachInsightCard (post-workout AI commentary)

### Onboarding
- ✅ Razvan's onboarding_v2.dart used (29-step flow). GoalInterpretOverlay
  deliberately NOT hooked — `_StepAITalk` chat step already serves the
  same "AI got me" moment.

### AI coach surfaces
- ✅ Goal Evolution flow (Profile → "Update this goal" button in
  GoalAdviceOverlay → edit text → AI regenerates plan with rationale)
- ✅ Backend endpoints: `/v1/ai/goal-interpret`, `/v1/me/weekly-coach-read`,
  `/v1/workouts/:id/insight`, `/v1/me/test-push`, goal-aware push cron
- ✅ `whyThisExercise` 2-sentence prompt on weekly-plan + ai-workout-suggestion
- ✅ buildGoalGuidance helper detects intent (jump/sprint/strength/cal/etc.)

### Razvan's massive refactor merged in
- ✅ SQLCipher local DB encryption, flutter_secure_storage tokens, Crashlytics
- ✅ Moderation trio (Block/Report/Blocklist)
- ✅ Health Connect 12-month backfill + WorkManager sync
- ✅ Story viewer v2, DM pagination, cached_network_image
- ✅ Onboarding v2 (29 steps), guest signin, account deletion
- ✅ photo_capture + photo_progress screens
- ✅ ZveltAvatar, ZveltEmptyState, ZveltErrorState, ZveltTertiaryButton,
  ZveltPrimaryButton variants, ZveltPill (his widgets, kept)
- ✅ 5 docs files in repo root (QA_BACKLOG, PLAY_STORE_SUBMISSION,
  HEALTH_CONNECT_INTEGRATION, FEATURE_SUGGESTIONS, CLAUDE_DESIGN_PROMPT)

---

## What's LEFT — ordered, with file-by-file detail

### Task A — Train tab bottom half (HIGH priority, ~1-2h)

**Goal**: Restyle the 9 cards below `ZWeeklyProgressCard` so they match V2.
They currently render with V2 tokens via aliases (no broken colors) but
have V1 layout assumptions: rounded-12 radius instead of 24, borders
instead of shadows, ALL-CAPS labels in mono where V2 wants Inter clean,
etc.

**Files** (all in `app/lib/screens/skeleton/skeleton_home_tab.dart`):

For each card class below, replace the `Container(decoration: ...)` outer
wrapper with `ZCard(...)`. Strip `Border.all(...)` — V2 uses shadows.
Standardize padding to `EdgeInsets.all(ZveltTokens.s4)` (16). Replace
inline `TextStyle(fontFamily: AppTheme.fontDisplay, ...)` with `ZType.h3` /
`ZType.h4`. Use `ZEyebrow('...')` for the small uppercase labels.

| Class | What needs the V2 treatment |
|---|---|
| `_MotivationCard` | ZCard wrap; replace amber-gradient bg with white surface; quote text → `ZType.bodyL` italic; author → `ZType.bodyS` |
| `_DailyReminderCard` | ZCard wrap; switch use white surface; time chip → `ZChip(variant: brand)` |
| `_StreakCard` / `_WorkoutsCard` | Already partially V2 from pre-merge; verify after merge — likely got reverted to Razvan's version. Re-apply ZCard wrap + `ZType.stat` for the big number + `ZEyebrow` for the label |
| `_ActivityCalendarCard` | Replace with **ZActivityGrid** OR keep table_calendar wrapped in ZCard but reduce padding |
| `_OutdoorTrackCard` | ZCard wrap; map preview thumbnail stays; CTA → primary pill button (theme already pill-shaped) |
| `_LastWorkoutCard` | ZCard wrap; metric badges → ZChip; relative time via Razvan's `relative_time.dart` util (already exists) |
| `_StepsCard` | ZCard wrap; integrate as alternative ZMetricTile-style card OR keep dedicated big card with ring progress (today's steps / 10k goal as ring) |
| `CharacterStatsCard` (external file) | `widgets/character_stats_card.dart` — verify uses ZCard; replace dark surface tones |
| `MuscleMapCard` (external file) | `widgets/muscle_map_widget.dart` — heavy custom-paint; just verify outer chrome uses ZveltTokens |
| `GameXpBarCard` (external file) | `widgets/game_xp_bar.dart` — verify XP progress bar uses ZveltTokens.brand for fill, surface3 for track |

**Strategy**: open file, jump to each `class _Foo extends StatelessWidget`,
replace outer Container/Padding/Material(Color/Border) wrapper with ZCard,
fix typography one Text at a time. ~10-15 minutes per card.

### Task B — Nutrition tab (HIGH, ~3-4h)

`app/lib/screens/nutrition/nutrition_tab.dart` — ~2000 lines, currently
inherits theme via AppTheme aliases. The visual hierarchy needs V2 treatment:

1. **Header** — same V2 greeting pattern as Train (eyebrow + Inter clean title)
2. **Daily macro card** — replace circular progress with ZBodyRing-style
   ring for each macro (calories / protein / carbs / fat)
3. **Meal entry list** — ZCard per meal, ZType.bodyM for food name, mono for
   grams/macros
4. **Search/scan FAB** — pill brand button
5. **Plan preview** — use ZCleanStatCard pattern for upcoming days
6. **Error states** — already V2-styled (we did persistent SnackBar)

### Task C — Bottom nav bar V2 polish (MEDIUM, ~30min)

`app/lib/widgets/zvelt_main_nav_bar.dart` — verify:
- Background: `ZveltTokens.surface` (white) with subtle top shadow
- Active item: brand orange icon + label
- Inactive: text3 grey
- Labels: `ZType.eyebrow` (IBM Plex Mono 10px) OR Inter 11 semibold —
  whichever matches design's nav

### Task D — Profile tab + Settings polish (MEDIUM, ~2-3h)

Razvan rewrote these heavily; mostly need:
- Section dividers using ZveltTokens.hairline instead of borders
- Avatar headline area uses ZBodyRing-style ring for completeness%
- Integration toggles → standard ZChip pattern
- Settings screen rows → standardize padding/typography

### Task E — Modals + dialogs sweep (MEDIUM, ~2h)

Files: `screens/social/*_modal*.dart`, `screens/workouts/quick_launch_sheet.dart`,
any `showModalBottomSheet` call sites.

- Background: ZveltTokens.surface
- Handle bar (drag indicator): ZveltTokens.surface3 small pill
- Title section: ZType.h3
- Replace dark glassmorphic backdrops (Razvan had some)

### Task F — Empty + error states everywhere (LOW, ~1-2h)

Razvan built `ZveltEmptyState` and `ZveltErrorState` widgets. Grep for:
- `'No data'` / `'Nothing here'` / `Center(child: Text('Empty'))` patterns
- Catch-all `Container()` returns inside lists
- Replace with proper ZveltEmptyState + clear CTA

### Task G — Splash + app icon (LOW, ~1h)

- `flutter_launcher_icons` package already in pubspec — needs new
  `image_path` pointing at a V2 logo (Razvan has `assets/images/zvelt_logo.png`
  and `zvelt_z.png` — pick one, run `dart run flutter_launcher_icons`)
- Splash: use `flutter_native_splash` package OR custom; either way
  background = ZveltTokens.bg, logo centered

### Task H — Designs NOT YET in Flutter (LOW priority for launch, but rich)

The design bundle in `/tmp/zvelt-design/zvelt-v2/project/` has:

| File | What it contains | Implementation status |
|---|---|---|
| `screens-train.jsx` | Train hero (BodyRings, Vitals, Activity, etc.) | ~70% (we plugged the heros) |
| `screens-progress.jsx` | Progress with PerformanceTrend, CleanStatCard layouts | ~50% (we did the basics on Training sub-tab) |
| `screens-nutrition.jsx` | Macro rings layout, meal cards, plan preview | 0% — see Task B |
| `screens-social.jsx` | Feed cards, story carousel V2 styling | Razvan has feed but not aligned to design exactly |
| `screens-social-chat.jsx` | DM screen V2 | Razvan has working DM; visual alignment TBD |
| `screens-social-modals.jsx` | Story creator, post composer, reaction picker | TBD |
| `screens-modals.jsx` | Quick launch, settings modals, share sheets | TBD |

**Note**: bundle no longer exists at `/tmp/zvelt-design/` between sessions
(temp dir wiped). To re-fetch:
```bash
curl -s -o /tmp/zvelt-design.html.gz "https://api.anthropic.com/v1/design/h/yKKNI9D0FrtbC7LhHUGzzA?open_file=zvelt-app-v2.html"
mkdir -p /tmp/zvelt-design && cd /tmp/zvelt-design && tar -xzf /tmp/zvelt-design.html.gz
```

---

## Wiring that's still placeholder (data, not graphics)

These are graphic widgets that work but currently show **fake numbers**.
Next session should wire real data:

- **ZBodyRingsRow** on Train tab: hardcoded 62/68/84. Replace with
  `HealthService.instance.getStrain() / getRecovery() / getSleep()` once
  those streams exist (Razvan has Health Connect plumbing — verify).
- **ZVitalsRow.placeholder** on Train tab: hardcoded values. Wire to
  `HealthService` heart rate, steps, sleep, stress (some via Health Connect,
  some not yet recorded).
- **ZActivityGrid** on Train tab: pattern derived from `_streak`. Replace
  `_placeholderActivityIntensities(streak)` with
  `ZActivityGrid.fromTrainingDays(weeks: 8, sessionsByYmd: <map from StatsChartsService>)`
- **ZWeeklyProgressCard** on Train tab: `goal: 5` hardcoded. Replace with
  `trainingProfile.daysPerWeek ?? 5`. `filled` should derive from real
  per-day session count, not streak position.

---

## Render + push state

- Render auto-deploys from `patrupievici/zveltutzu` `main` branch
- Build command in dashboard: `npm install && npx prisma generate && npx prisma migrate deploy && npm run build`
- Start: `npm start`
- Root directory: `backend`
- env vars set: DATABASE_URL, DIRECT_URL, DEEPSEEK_API_KEY, JWT_SECRET,
  EXERCISEDB_KEY, USDA_API_KEY, NODE_ENV=production

If Render is on old code: push `Clau` branch to origin/main:
```bash
git push origin Clau:main
```

---

## Important DON'Ts for next session

- **DON'T remove the Razvan-naming aliases** in `app_theme.dart` (bg0, s1,
  t1, brand, warn, gradBrand, gradBtn, barlowCondensed) — they keep his
  ~50 widgets compiling.
- **DON'T `git checkout --theirs/--ours`** on merge conflicts blindly. Read
  the conflict, decide per file. The big files (skeleton_home_tab,
  progress_hub_screen) have BOTH my AI plug-ins AND Razvan's restyle —
  losing either side hurts.
- **DON'T regenerate Prisma client without `prisma migrate deploy`** —
  schema drift between local and Supabase will silently miss columns.
- **DON'T push to `origin/main` without testing locally** — Render deploys
  immediately on push.

---

## Quick commands

```bash
# Backend
cd backend
npx tsc --noEmit                    # typecheck
npm test                            # vitest (39 tests, should all pass)
npm run dev                         # local dev server

# Flutter
cd app
flutter analyze                     # 0 errors expected, ~25 info lints OK
flutter build apk --release         # APK at build/app/outputs/flutter-apk/
flutter pub get                     # if deps changed

# Git
git push origin Clau:main           # deploy backend (Render auto-deploys)
git push clau Clau:main             # backup snapshot to private repo
git checkout backup-before-razvan-merge  # SAFETY rollback
```

---

## What Cip cares about (so you don't waste cycles)

- **AI coach as the wedge** — every visual decision serves "this is the AI
  that understands your goal". Don't dilute with generic gym tracker UI.
- **Honesty over flattery** — Cip explicitly asks for "trage-mă de
  perciuni" (correct me when wrong). Don't soften feedback.
- **Working APK builds matter more than perfect code** — ship, observe,
  iterate. Don't get stuck polishing one widget for 2 hours.
- **Beep / Ode to Joy via PowerShell after completed tasks** — he likes
  the audible signal.

```powershell
# 1-phrase Ode to Joy (12s):
powershell -NoProfile -Command "[console]::beep(330,240);[console]::beep(330,240);[console]::beep(349,240);[console]::beep(392,240);[console]::beep(392,240);[console]::beep(349,240);[console]::beep(330,240);[console]::beep(294,240);[console]::beep(262,240);[console]::beep(262,240);[console]::beep(294,240);[console]::beep(330,240);[console]::beep(330,360);[console]::beep(294,120);[console]::beep(294,480)"
```

---

_End of handover. Good luck. — Clau (Opus 4.7), 2026-06-03_
