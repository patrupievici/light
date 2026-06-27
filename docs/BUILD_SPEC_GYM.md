# Zvelt — Gym Build Spec (multi-week programs)

Status: **COMPLETE** (2026-06-26). Backend (model+migration, 8 templates, % TM engine,
materialization service, `/v1/programs` routes) + Flutter UI (library/detail/active screens +
"Programe" card in Train) + Phase 5 polish + adversarial review with all real findings fixed.
Verified: backend tsc clean + 722 tests + prisma valid; app analyze clean + APK builds + 158 tests.

Phase 5 / review fixes applied: equipment auto-filter+substitute in materialization (skips wave
main lifts); equipment selector UI in the start sheet (so auto-swap actually gets tags); set/edit
training maxes mid-program (PATCH oneRepMaxes + banner + sheet — fixes "set 1RM later"); program
completion card (/active falls back to latest completed); AMRAP marker in session preview; advance
race/mounted fix in Flutter; advance-after-completed guard; deload double-flag clarified.

Deliberately OUT of scope (justified): manual exercise-swap button in the tracker (user chose
"filtrare + swap AUTOMAT", not manual swap); structureJson per-set edits; full Train sub-tab /
bottom-nav center-FAB restructure (tracked as a separate NAV task, not part of gym).

## Decisions (locked with user)
- **Library:** big — PPL, Upper/Lower, Full Body, StrongLifts 5x5, nSuns, 5/3/1, PHUL, Arnold split.
- **Progression (Liftosaur model — per program):** 5x5/Starting Strength → `linear`; PPL/PHUL/Arnold/Upper-Lower → `double`; 5/3/1 + nSuns → `percentage` (% of training max, NEW); AI/custom → `auto` (RPE). Targets recomputed at workout finish.
- **Prescriptive:** per-set auto targets (weight × reps) pre-filled; user confirms/adjusts.
- **Editing:** edit a template/AI plan (swap exercise, tweak sets) — NO from-scratch builder.
- **Deload:** auto every 4th week (−12% + trim a set) via existing engine, with an in-app banner.
- **Equipment:** pick gear at start → filter impossible exercises + auto-offer swaps (existing `equipment-compatibility`).
- **Warm-ups:** auto-generate ramp for compounds (wire existing `generateWarmupSets`).
- **Legal:** ExerciseDB (already integrated) for GIFs. Liftosaur is AGPL — inspiration only, never copy.

## Architecture
Templates live in **code** (like `blueprints.ts`); one new DB model holds the user's instance.
A program day is **materialized into the existing `PlannedWorkout` → tracker flow**, so the
whole logging/anti-cheat/offline-sync surface is reused, not rebuilt.

### Data model — `UserProgram` (DONE, migration `20260626120000_add_user_programs`)
`id, userId, templateId, title, totalWeeks, daysPerWeek, progressionScheme, deloadCadence,
status(active|completed|archived), currentWeek, stateJson (per-slot trainingMax/currentWeight),
structureJson (user edits), equipmentTags, startedAt, completedAt`. FK cascade on user delete.

### Program templates — `src/programming/program-templates.ts` (Phase 2)
```
ProgramSlot   { slotKey, pattern, role(main|accessory), sets, repRange, scheme?, pctOfTM?, restSeconds, warmup? }
ProgramDay    { dayKey, title, slots[] }
ProgramTemplate { id, title, description, goalTags[], defaultScheme, weeksOptions[], daysOptions[], split, deloadCadence, days[] }
```
8 templates: `stronglifts_5x5`(linear), `full_body_3day`(linear), `upper_lower_4day`(double),
`ppl_6day`(double), `phul`(double), `arnold_split`(double), `nsuns_4day`(percentage), `531_bbb`(percentage).

### Progression — `percentage` scheme (Phase 2)
% of training max (TM = 90% of e1RM). 5/3/1 weekly waves
(w1 .65/.75/.85, w2 .70/.80/.90, w3 .75/.85/.95, w4 deload), TM +2.5kg upper / +5kg lower per cycle.
Computed in the program materialization layer (needs week+set+TM context), NOT in the
history-driven `progression-schemes.ts` (which keeps its clean 4 schemes for free workouts).

### Backend routes — `src/routes/programs.ts`, prefix `/v1/programs` (Phase 3)
Zod-validated, Bearer auth, error shape `{error,message,request_id}`.
- `GET /templates` — list templates (library screen).
- `GET /templates/:id` — full preview (weeks × days × slots).
- `POST /start` — `{templateId, weeks?, daysPerWeek?, equipmentTags?, oneRepMaxes?}` → creates UserProgram, seeds stateJson.
- `GET /active` — active program + "week X of N" + today's materialized day.
- `GET /:id/day?week=&day=` — materialize a day → exercisesJson with per-set targets, warmups, deload flag.
- `POST /:id/start-day` — materialize today into a PlannedWorkout + open the live Workout draft (returns workoutId).
- `PATCH /:id` — swap exercise / edit sets (structureJson) / archive.
- `POST /:id/advance` — complete day; advance week; apply TM increments at cycle end.
- `DELETE /:id` — archive.

### Flutter — `app/lib/screens/workouts/` (Phase 4)
- Train tab sub-tabs: **Azi · Programe · Exerciții · Istoric**.
- `programs_library_screen.dart` — program cards (title, weeks, days/wk, split, scheme badge), filter by goal/days.
- `program_detail_screen.dart` — preview + "Start program" (weeks/days/equipment + optional 1RM entry).
- `active_program_screen.dart` — "Week 3 of 8" header, week calendar, today's card, deload banner → opens tracker.
- Tracker: show per-set TARGET pre-filled (confirm/adjust), warmup rows, swap-exercise button, GIFs (exist).
- `program_service.dart` — API client.

### Phase 5 — polish
Equipment filter UI, swap sheet, warm-up rows in tracker, deload banner; wire up unused
`anti-cheat.service.ts` + `post-visibility.ts` into routes (Tier-3 finding from cleanup).

## Verification gate per phase
Backend: `tsc --noEmit` + `vitest run` + `prisma validate` (+ migration file). App: `flutter analyze` + `flutter test`.
