# Zvelt — Home / Muscle Map Build Spec

Bring the front/back muscle map onto the Home tab with per-muscle LEVELS
(volume-RPG + strength) and collapsible chart cards. ~40% → done.

## Decisions (locked with user)
- **Muscle map (front+back) on Home** — the `MuscleMapWidget`/`MuscleMapCard` already exists (used only in Analytics today); embed it on `home_tab`.
- **Per-muscle level = Volume-RPG + Strength (e1RM)** combined.
- **A few charts, NOT prominent — in small collapsible cards that expand on tap.**

## Existing pieces (reuse)
- Flutter: `MuscleMapWidget`/`MuscleMapCard`/`MuscleMapScreen` (SVG front/back, 15 slugs), `MuscleRecoveryService.getRecoveryStatus()` (NSCA recovery per slug, `cacheRevision` ValueNotifier), `ZCard`/`ZEyebrow`/`ZBodyRing`, chart cards (`CumulativeVolumeCard`, `RecentPrsCard`, `MuscleBalanceChart`, `WorkoutConsistencyHeatmap`…), `BeastIntelligenceCard` (expand/collapse pattern to mirror). `home_tab.dart` is the lean light home.
- Backend: `src/constants/muscles.ts` (22 canonical snake_case muscles + `normalizeMuscle`/`normalizeMuscleSet`), `Exercise.{primaryMuscle, secondaryMuscles}`, `WorkoutSet.{weightKg,reps,tag,isCompleted}`, `UserExerciseRank.{lpTotal,bestE1rmKg}`, `ranking.service` (`lpToTier`, TIER_NAMES), `stats.ts` join pattern.

## Level formula (pure, tunable)
```
volumeXp      = Σ over WORK sets (completed): weightKg × reps × contribution   (primary 1.0, secondary 0.5)
volumeLevel   = volumeXp > 0 ? floor(sqrt(volumeXp / 2000)) : 0
strengthBonus = floor(bestLp / 100)              // bestLp = max UserExerciseRank.lpTotal of the muscle's primary lifts (0–699 → 0–6)
level         = volumeXp > 0 ? max(1, volumeLevel + strengthBonus) : 0
```

## Muscle bridge (backend canonical → Flutter SVG slug)
22 canonical → 15 SVG slugs (merge front/side/rear_delts→deltoids, lats+upper_back→upper-back,
quads→quadriceps, hamstrings→hamstring, glutes→gluteal, forearms→forearm, traps→trapezius;
abductors/hip_flexors/neck → dropped, no SVG slug). The endpoint emits Flutter slugs so the
levels align 1:1 with the recovery map. Unit-tested both directions.

## Phases
- **P1 backend:** `src/lib/muscle-levels.ts` (pure bridge + `computeMuscleLevel`) + `GET /v1/me/muscle-levels`
  (derived: WORK-set volume per slug + max lp per slug → level; query `?window=` days, `?includeUntrained=`) + tests.
- **P2 Flutter service:** `getMuscleLevels()` + `MuscleLevel` model (slug, level, volumeXp, tier, lastTrainedAt).
- **P3 Flutter Home:** embed `MuscleMapCard` on `home_tab` + a per-muscle LEVEL strip/grid under the map
  (top muscles: name · Lvl N · tier) + new `ZCollapsibleChartCard` wrapping 2-3 charts (volume, PRs, consistency)
  — collapsed by default, expand on tap.
- **P4 review + verify.**

### Endpoint shape
`GET /v1/me/muscle-levels?window=&includeUntrained=` →
`{ data: [{ slug, level, volumeXp, volumeKg, workSets, bestLp, tier, strengthBonus, lastTrainedAt }] }`
sorted by level desc. Flutter slugs. Derived on-the-fly (no new table).

## Verification gate per phase
Backend: `tsc` + `vitest` + `prisma validate`. App: `flutter analyze` + `flutter test` + `flutter build apk --release`.
