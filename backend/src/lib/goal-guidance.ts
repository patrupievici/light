/**
 * Goal-aware prompt augmentation for the AI planner.
 *
 * The user's free-text goal (e.g. "I want to dunk a basketball") carries far
 * more signal than the enum bucket (`explosive_power`). Generic AI prompts
 * produce generic plans — relevant categories but no specificity. This module
 * detects intent keywords and returns a focused guidance block to inject into
 * the planner prompt.
 *
 * Each block tells the model what categories to prioritize, NOT what specific
 * exercises to pick. We want the AI to still apply judgment within the rails
 * we set, not just recite a fixed program.
 *
 * Used by:
 *   - services/weekly-plan.service.ts        (7-day plan)
 *   - services/ai-workout-suggestion.service.ts  (single session)
 */

const JUMP_GUIDANCE = `[VERTICAL JUMP / DUNK]
- Plyometrics are primary: depth jumps, box jumps, broad jumps, bounds.
- INCLUDE single-leg jumps — most sport jumps (basketball dunk) are off one leg.
  Pick single-leg box jumps, skater jumps, step-up jumps, or single-leg bounds.
- Olympic lifts for rate-of-force-development: power clean, hang clean, push press.
- Prefer trap bar deadlift over back squat when both are available (vertical bar path).
- Add 1 session/week of short sprint or acceleration work (10–40m).
- Calf raises for ankle stiffness (low priority, but include).
- Pogo hops / mini-bounds (low ground-contact-time reactive work) once per week.
- Keep upper body work SHORT (≤30 min); jumping budget is lower-body explosive volume.
- Avoid heavy slow grinding strength as the focus — quality plyometric reps matter more.`

const SPRINT_GUIDANCE = `[SPRINT SPEED / ACCELERATION]
- Short sprints (10–40m max effort, full recovery) are the primary modality.
- Sprint mechanics drills: A-skips, B-skips, wall drills, falling starts.
- Plyometric work for elastic strength: bounds, hops, depth jumps.
- Power clean / snatch variations for triple-extension power.
- Hip flexor strengthening for knee drive.
- Posterior chain emphasis: RDL, glute-ham raise, hip thrust.
- Sled push / pull for resisted acceleration when available.
- Keep upper body and isolation work minimal.`

const STRENGTH_GUIDANCE = `[STRENGTH / POWERLIFTING / 1RM]
- Squat, bench, and deadlift are the primary lifts — most sessions should center on one of them.
- Low reps, high intensity: 3–5 reps for the main lift, 4–6 sets, long rests (180–300s).
- Use pause / tempo / deficit variations of the main lifts as accessories.
- Accessories must directly support the big 3 (close-grip bench for triceps, paused squat for depth, deficit DL for lockout).
- AVOID: machine isolation, bodybuilding-style high-rep arm work, fluffy accessory volume.
- 3–4 sessions/week is plenty; recovery matters more than frequency at this intensity.`

const CALISTHENICS_GUIDANCE = `[CALISTHENICS / BODYWEIGHT / SKILL]
- Use bodyweight movements and their progressions as the primary lifts.
- Pulling: pull-ups, chin-ups, rows, and lever progressions (tuck → straddle → full).
- Pushing: push-ups, dips, handstand push-ups, planche progressions.
- Include isometric holds: L-sit, plank, planche tucks, lever holds.
- Skill work goes FIRST in the session, when CNS is fresh (e.g. handstand practice, muscle-up attempts).
- Treat skill work like singles: 3–6 quality attempts, long rests, no metabolic fatigue.
- AVOID machine isolation; weighted accessories OK only if they reinforce a bodyweight goal (e.g. weighted pull-ups for muscle-up).`

const FAT_LOSS_GUIDANCE = `[FAT LOSS / CUT / LEAN]
- Center sessions on compound multi-joint lifts (preserves muscle in a deficit).
- Add 1–2 conditioning finishers per session: KB swings, sled push, battle ropes, AirBike intervals (8–12 min).
- Supersets and giant sets to keep heart rate elevated and density high.
- Don't cut strength work entirely — muscle retention is the goal.
- Notes: emphasize daily steps (NEAT), sleep, and protein intake (1.8–2.4 g/kg).`

const HYPERTROPHY_GUIDANCE = `[MUSCLE / HYPERTROPHY / BODYBUILDING]
- Moderate reps (8–15) on most working sets, RPE 7–9, controlled tempo on eccentric.
- Cover each major muscle group 2× per week minimum for optimal volume.
- Include both compound (squat, bench, row) and isolation (curl, lateral raise, leg curl) work.
- Use a mix of free-weight and machine/cable to bias different lengths of the strength curve.
- Lengthened-position emphasis on isolation lifts (deep stretch under load) when possible.
- Rest 90–180s on compounds, 60–90s on isolation.`

const ENDURANCE_GUIDANCE = `[ENDURANCE / CARDIO / RUNNING / CYCLING]
- 2–4 sessions of zone 2 (conversational pace, 30–60 min) per week as the base.
- 1 session of intervals or tempo work (zone 4–5).
- Keep strength work to 1–2 sessions/week, focus on injury prevention and economy:
  single-leg work, hinge variants, calf raises, anti-rotation core.
- Avoid heavy slow strength training the day before a hard run/ride.`

type GoalIntent = {
  label: string
  patterns: RegExp[]
  guidance: string
}

const INTENTS: GoalIntent[] = [
  {
    label: 'jump',
    patterns: [
      /\b(vertical|vert)\s+(jump|leap|reach)\b/i,
      /\b(jump\s+higher|jump\s+height|hops|jumping)\b/i,
      /\b(dunk|dunking|dunks?)\b/i,
      // NB: no bare /basketball/ — it over-claimed "basketball conditioning" as
      // a pure jump goal. "dunk a basketball" still matches via /dunk/.
      /\b(volleyball\s+spike|spike|block)\b/i,
    ],
    guidance: JUMP_GUIDANCE,
  },
  {
    label: 'sprint',
    patterns: [
      /\b(sprint|sprinter|sprinting)\b/i,
      // "faster" only in a running context — bare "faster" wrongly caught
      // "swim faster", "type faster", etc.
      /\b(run|running|jog|jogging|dash)\s+faster\b/i,
      /\b(speed up|top\s*speed|acceleration|accelerate)\b/i,
      /\b(40[\s-]?yard|40m|100m|60m|200m)\b/i,
      /\b(soccer|football)\s+(speed|pace)\b/i,
    ],
    guidance: SPRINT_GUIDANCE,
  },
  {
    label: 'strength',
    patterns: [
      /\b(powerlifting|powerlifter)\b/i,
      /\b(1\s*rm|one[\s-]?rep[\s-]?max|max\s+lift)\b/i,
      /\b(strength\s+goal|stronger|get\s+stronger)\b/i,
      /\b(deadlift|squat|bench)\s+(pr|record|max)\b/i,
      /\btotal\s+(up|increase)\b/i,
    ],
    guidance: STRENGTH_GUIDANCE,
  },
  {
    label: 'calisthenics',
    patterns: [
      /\bcalisthenics?\b/i,
      /\b(street workout|bar work)\b/i,
      /\b(planche|front lever|back lever|muscle[\s-]?up|handstand|hspu)\b/i,
      /\b(gymnastics|gymnastic strength)\b/i,
      /\b(bodyweight\s+(only|training|progress))\b/i,
    ],
    guidance: CALISTHENICS_GUIDANCE,
  },
  {
    label: 'fat_loss',
    patterns: [
      /\b(fat\s+loss|lose\s+fat|burn\s+fat)\b/i,
      /\b(lose\s+weight|drop\s+weight|cutting|cut\b)/i,
      /\b(get\s+lean|lean\s+(out|down)|shred|shredded)\b/i,
      /\b(lose\s+\d+\s*(kg|lbs?|pounds?|kilos?))\b/i,
    ],
    guidance: FAT_LOSS_GUIDANCE,
  },
  {
    label: 'hypertrophy',
    patterns: [
      /\b(build\s+muscle|muscle\s+(gain|growth|building)|gain\s+muscle)\b/i,
      /\bbodybuilding\b/i,
      /\b(get\s+(jacked|big|swole|huge)|put on\s+(mass|size))\b/i,
      /\b(bulk|bulking)\b/i,
      /\bhypertrophy\b/i,
    ],
    guidance: HYPERTROPHY_GUIDANCE,
  },
  {
    label: 'endurance',
    patterns: [
      /\b(marathon|half[\s-]?marathon|5k|10k|ultra)\b/i,
      /\b(running|cycling|cyclist|triathlon|swimming\s+endurance)\b/i,
      /\b(endurance|stamina|cardio\s+base|aerobic\s+base)\b/i,
    ],
    guidance: ENDURANCE_GUIDANCE,
  },
]

/**
 * Single source of truth for the intent scan. Returns the matched intents in
 * INTENTS order. Labels are unique across INTENTS, so the result needs no
 * dedup. Empty when the text is blank or nothing matches.
 */
function matchIntents(goalText: string | null | undefined): GoalIntent[] {
  const text = (goalText ?? '').trim()
  if (!text) return []
  return INTENTS.filter((intent) => intent.patterns.some((p) => p.test(text)))
}

/**
 * @returns A guidance block to inject into the planner prompt, or an empty
 *   string if no specific intent was detected. Multiple intents stack.
 */
export function buildGoalGuidance(goalText: string | null | undefined): string {
  const matched = matchIntents(goalText)
  if (matched.length === 0) return ''

  return [
    '',
    'Goal-specific priorities (apply on top of generic rules):',
    ...matched.map((m) => m.guidance),
  ].join('\n')
}

/**
 * Detected intent labels for a goal text (e.g. "dunk a basketball" -> ['jump']).
 * Empty when nothing matches. Used to additively widen the AI exercise pool so
 * the user's free-text goal isn't overridden by the enum bucket.
 */
export function detectGoalIntents(goalText: string | null | undefined): string[] {
  return matchIntents(goalText).map((i) => i.label)
}

/**
 * True when the goal mentions an injury, pain, or physical constraint. Such
 * goals must NOT run a blind deterministic blueprint (a jump program for a
 * fragile achilles is dangerous) — the caller should defer to the LLM, which
 * can program around the limitation. Safety guardrail; intentionally broad
 * (a false positive just routes to the LLM, which is the safe direction).
 */
const INJURY_RE =
  /\b(injur(?:y|ies|ed)|pain(?:ful)?|hurts?|sore(?:ness)?|surgery|surgical|post-?op|rehab(?:ilitation)?|recover(?:ing|y)|fragile|tendin(?:itis|opathy)|tendons?|sprain(?:ed)?|strain(?:ed)?|torn|tear|rupture|acl|mcl|pcl|meniscus|rotator\s*cuff|herniat(?:ed|ion)|sciatica|arthritis|bad\s+(?:knee|back|shoulder|hip|elbow|wrist|ankle|neck)|(?:knee|back|shoulder|hip|elbow|wrist|ankle|neck)\s+(?:pain|issue|problem)|achilles)\b/i

export function hasInjuryContext(goalText: string | null | undefined): boolean {
  return INJURY_RE.test((goalText ?? '').trim())
}

/**
 * True when the goal is phrased as a negation/avoidance ("not interested in
 * bulking", "I don't want to lose muscle"). Keyword matching can't grasp
 * negation, so defer to the LLM. Conservative — a false positive just routes to
 * the LLM.
 */
const NEGATION_RE =
  /\b(?:don'?t\s+want|do\s+not\s+want|not\s+(?:interested|trying|into|looking)|no\s+interest|rather\s+not|avoid|stop\s+\w+ing)\b/i

export function hasNegationContext(goalText: string | null | undefined): boolean {
  return NEGATION_RE.test((goalText ?? '').trim())
}

/**
 * Map a detected intent label to the exercise `goalTags` / primaryGoal values
 * the catalog uses, so we can widen the candidate pool. A label may map to
 * several tags (e.g. jump -> explosive_power + vertical_jump).
 */
export function goalTagsForIntent(label: string): string[] {
  switch (label) {
    case 'jump':
      return ['explosive_power', 'vertical_jump']
    case 'sprint':
      return ['explosive_power']
    case 'strength':
      return ['strength']
    case 'calisthenics':
      return ['calisthenics']
    case 'fat_loss':
      return ['fat_loss']
    case 'hypertrophy':
      return ['hypertrophy']
    case 'endurance':
      // No deterministic blueprint fits a cardio-modality goal well (the
      // catalog is strength-biased), and 'maintenance' wrongly routed marathon
      // goals to the hypertrophy blueprint. Return nothing → defer to the LLM.
      return []
    default:
      return []
  }
}

/** Test seam — used by unit tests; not consumed by production code. */
export const __testIntents = INTENTS.map((i) => i.label)
