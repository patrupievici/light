# Zvelt — Adaptive Coach Loop (Pariul 1)

_Plan from a 12-agent ultra-think (8 mapped the code, 4 designed). Goal: turn the
coach from a logger into something that watches your logs and recomputes what's
next, with "de ce" on every change. All work is backend/AI (owner's lane); app
changes are pure rendering of server fields (minimal design dependency)._

## Diagnosis — where the loop is open today

The loop `Goal → Plan → Log → Adapt → Explain` is **closed only on the weight
number, only at the Monday boundary, and blind to RPE** — and the "de ce" it
computes never reaches the user's eyes.

What feeds back today:
- **Loads (weekly path only):** `computeProgressiveLoads` (progressive-overload.ts:59)
  reads your last logged WORK set and bumps next week's weight by a fixed step
  (`bumpForLevel`: +2.5/+1.25/+0 kg by level), or holds on a coarse 30-day stall.
- **Exercise bias (prompt text):** `getRecentProgression` (progression-context.ts)
  injects a RECENT_PROGRESSION block into the LLM prompt — advisory only.

The gaps (the real opportunity):
1. **RPE is logged but NO planner reads it.** `WorkoutSet.rpe` is collected,
   validated, stored — and consumed by zero generation paths. Biggest untapped signal.
2. **Overload is open-loop.** +2.5kg every session regardless of whether you hit
   the reps or how hard it was. **No deload logic exists anywhere.**
3. **Daily suggestion ignores logs for exercise selection** (goal + equipment +
   `fatigueScore` catalog constant + date-rotation). `composeSession`/`candidateScore`
   have no history term.
4. **Completing a workout changes nothing immediately.** It never calls
   `clearWorkoutSuggestionCache`, never recomputes the next session. Adaptation only
   happens at the Monday `weekly-plan-cron` regen.
5. **Recovery signals (HRV/sleep/RHR/strain) never leave the device** — `BodyMetricsService`
   computes them client-side; no plan endpoint can see them.
6. **The "de ce" is computed then dropped.** `createWorkoutFromPlanned` copies only
   `repRangeHint`; `loadReason`/`loadSource`/`whyThisExercise` are parsed app-side
   (workout_service.dart:1271-1289) but rendered nowhere. The rank `/explain` card is
   **bugged**: backend returns `explanation`, app reads `data['summary']`/`['message']`
   (xp_complete_screen.dart:202) → user always sees a hardcoded string.

Strategic finding: **two divergent weekly pipelines.** The app calls a log-BLIND
title-only route (`generateAiWeeklyPlannedSessionTitles`, planned-workouts.ts),
while the rich adaptive path is `generateAndPersistWeeklyPlan` (weekly-plan.service.ts).
Unifying these amplifies everything below — decide which is canonical.

---

## The plan — 4 rungs, each independently shippable

### Rung 1 — Autoregulate (the heart). impact:high · effort:M
New pure module `backend/src/lib/adaptation-rules.ts`: `decideAdaptation(evidence)
→ progress | hold | deload | swap-variant | change-scheme`. Replaces the blind
bump inside `computeProgressiveLoads`. **RPE finally gets read.**

Core rules (with thresholds):
- **Progress (double-progression, RPE-gated):** hit prescribed reps AND avg RPE ≤ 8
  (≥2 RIR) → if below top of rep range, +1 rep; if at top, +load (`bumpForLevel`) and
  reset reps. _"Hit 5×5 @RPE7 → +2.5kg."_
- **Easy-set accelerator:** RPE ≤ 6 (≥4 RIR) and reps hit → 1.5× the normal bump.
- **Hold:** reps hit but RPE in (8, 9] → repeat same weight. _"On the edge at RPE8.5 — consolidate."_
- **Deload (per-lift):** reps missed by >1 OR RPE ≥ 9.5 on 2 consecutive sessions
  → −10% (`roundToPlate`). _The deload that doesn't exist today._
- **Deload (systemic):** 7-day avg RPE ≥ 9 over ≥3 sessions OR volume +40% while RPE
  rising → `deloadWeek=true`, −10% all compounds + cut a top set.
- **Stall:** |Δe1RM 30d| < 1kg AND ≥3 sessions since gain → 1st stall = change scheme
  (5×5→3×8); 2nd = swap variant (same movement pattern, new exerciseId).
- **Missed-session reshuffle:** pending past-day plan → carry prescription forward, no
  progression (no log = no evidence); ≥2 missed = detraining, −5% compounds.
- **Priority when multiple fire:** systemic deload > per-lift deload > missed-session
  > stall > hold > progress. Safety (principle #4) always beats progression;
  reason string always emitted (principle #3).

Data: reuse `WorkoutSet.rpe/reps/isCompleted`, `PlannedWorkout.exercisesJson`,
`UserExerciseRank`. Add to `ProgressionEntry`: `avgRpeLast`, real `lastSets`,
`repsAchievedLast`, `prescribedRepsLast/WeightLast`, `sessionsSinceE1rmGain`. Add
`UserTrainingProfile.adaptationStateJson` for stateful consecutive-session counters.

**First step:** ship the pure engine with PROGRESS/HOLD/DELOAD only, wired into the
one call site (replace the bump at progressive-overload.ts:177), behind the existing
weekly regen boundary, fully unit-tested (the branching was never tested). Gate behind
a flag with `bumpForLevel` as fallback → reversible.

### Rung 2 — Persist state + recompute on every workout (fix the cadence). impact:high · effort:M
New table `UserExerciseProgress` (@@id [userId, exerciseId]): durable per-lift
autoregulation state. On `POST /v1/workouts/:id/complete`: upsert achieved-vs-target
+ max RPE + computed source/reason, run `reconcileNextSession` to rewrite the next
pending `PlannedWorkout.exercisesJson` loads, and `clearWorkoutSuggestionCache(userId)`.
Adaptation now happens **when you finish a workout, not next Monday.** New read endpoint
`GET /v1/me/next-session-adjustments`. Non-blocking (try/catch, indexed queries, no LLM,
within p95 <800ms).

**First step:** write side only — add the table + upsert one progress row per WORK
exercise on `/complete` + bust the cache. No plan mutation yet (behavior-preserving).

### Rung 3 — Surface the "de ce" (make it visible). impact:high · effort:M
- **Quick win (do first, ~1 line):** fix rank-explain — read `data['explanation']`
  in xp_complete_screen.dart:202, render `nextTier.estimatedWeightAt5Reps`. Turns a
  dead card into the real per-user explanation already computed.
- Add nullable `loadSource/loadReason/whyThisExercise` columns to `WorkoutExercise`;
  make `createWorkoutFromPlanned` copy them 1:1 so the reason survives plan→session.
- Render reason chips in `WorkoutTrackerScreen` (beside repRangeHint) + a dismissible
  "what changed since last time & why" panel on planned-session open
  (`GET /v1/workouts/:id/changes`). All render-only; reasons stay server-side.

### Rung 4 — Proactive coach (it reaches out). impact:high · effort:M
- **Push:** `coach-trigger.service.ts` reuses `getRecentProgression` + `summarizeWeek`
  to detect plateau / under-recovery (high RPE) / streak-at-risk / missed-session / PR,
  emits **persisted, explainable** nudges via `createNotificationSafe` (new
  `NotificationType.COACH_NUDGE`) — fires on the hourly cron AND from `/complete`.
  Rate-limit 2/user/day + per-trigger cooldowns.
- **Chat ACT:** upgrade `POST /v1/ai/trainer` to inject full log/rank context and expose
  `generate_today` / `swap_exercise` / `trigger_deload` tools → chat becomes a command
  surface. Nudges deep-link into chat pre-seeded with the trigger reason.

**First step:** ONE trigger (PLATEAU) end-to-end from `/complete` → persisted nudge.
No schema, no cron change, no app change.

---

## Recommended order
1. **Rung 1 first step** (the engine) — the heart; makes the existing loop autoregulated.
2. **Rung 3 quick win** (rank-explain 1-liner) — instant visible proof of the "render
   server reason" pattern, ~5 min.
3. **Rung 2** (persist + recompute on complete) — closes the cadence gap.
4. Rung 3 full (reason chips) → Rung 4 (proactive).

## Cross-cutting decisions to make
- **Unify the two weekly pipelines** (log-blind titles vs rich adaptive) — pick the
  canonical one; otherwise the app may hit the route that ignores all of the above.
- **Recovery to backend:** POSTing HRV/sleep to the server is a separate unlock that
  upgrades the deload triggers from RPE-only to true readiness. Defer past v1.
- All of the above is backend/AI = owner's lane; app changes are pure rendering.
