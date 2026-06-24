import { deepSeekChat } from '../services/deepseek.service'
import { ZVELT_APP_CONTEXT_FOR_AI } from '../ai/app-context'
import { signalsEliteCompetitionLevel } from './elite-athlete'
import { buildGoalGuidance } from './goal-guidance'

/**
 * Strip prompt-injection attempts and cap length. Use on ANY string sourced
 * from the user before embedding it in a DeepSeek prompt.
 */
export function sanitizePromptInput(input: string): string {
  return input
    .replace(/[<>{}]/g, '')
    .replace(/\b(ignore|disregard|forget)\s+(previous|above|all)\s+(instructions?|rules?|prompts?)/gi, '[filtered]')
    .slice(0, 900)
}

/**
 * Best-effort JSON extraction from a DeepSeek response. Tries the whole text
 * first, then falls back to the first `{...}` block (handles markdown fences,
 * stray prose). Returns `null` when nothing parses.
 */
export function parseJsonFromModel<T>(text: string): T | null {
  const trimmed = text.trim()
  if (!trimmed) return null
  try {
    return JSON.parse(trimmed) as T
  } catch {
    const match = trimmed.match(/\{[\s\S]*\}/)
    if (!match) return null
    try {
      return JSON.parse(match[0]) as T
    } catch {
      return null
    }
  }
}

/**
 * Phrases that signal "AI slop" — generic gym-app filler that adds nothing.
 * Banning them at the prompt level pushes the model toward specifics.
 */
const BANNED_ADVICE_PHRASES = [
  'be consistent',
  'consistency is key',
  'trust the process',
  'small steps',
  'listen to your body',
  'stay hydrated',
  'rest is important',
  'recovery is important',
  'eat enough protein',
  'enjoy the journey',
  'progress takes time',
  'one step at a time',
  'work hard',
  'no pain no gain',
] as const

/**
 * Generate the "goal advice" bullet list shown in the Quick Actions → Advice
 * overlay (goal_advice_overlay.dart). Elite-level signals (national team / pro
 * league) get a tighter sport-science prompt; everyone else gets a structured
 * coach-style brief. Goal intent (jump, sprint, strength, etc.) is detected
 * from the user's free text and injected as a topic-focus block so the AI
 * doesn't slide into generic gym tips.
 *
 * Returns an empty string on AI failure — the caller decides what to do.
 */
export async function generateGoalAdvice(userGoal: string, gymExperienceHint: string): Promise<string> {
  if (!userGoal.trim()) return ''
  const eliteSignals = `${userGoal}\n${gymExperienceHint}`
  const useEliteGoalAdvice = signalsEliteCompetitionLevel(eliteSignals)
  const intentBlock = buildGoalGuidance(userGoal)

  const bannedList = BANNED_ADVICE_PHRASES.map((p) => `"${p}"`).join(', ')

  const advicePrompt = useEliteGoalAdvice
    ? `The athlete described their situation (sport / competitive level / ambitions) in their own words:

GOAL / NARRATIVE:
"${sanitizePromptInput(userGoal)}"
${gymExperienceHint ? `\nTRAINING OR SPORT BACKGROUND (short notes they gave):\n"${sanitizePromptInput(gymExperienceHint)}"\n` : ''}
${intentBlock ? `\nDetected focus areas — use these to direct your bullets:${intentBlock}\n` : ''}
Produce content for an in-app "Advice" panel read by this athlete.

Requirements:
• 8–12 bullet lines; each line MUST start with "• "
• English only
• Focus on **sport and exercise science / performance practice** at the high-performance end: e.g. managing internal & external load and fatigue (note where metrics like acute:chronic ratios are debated), readiness and freshness monitoring where appropriate, sleep extension and travel/circadian disruption, fuelling and protein distribution across the day, carbohydrate timing around repeated high-intensity work, recovery between congested competition periods, taper and competition microcycles, sequencing strength–speed–power work without burying freshness — and other themes grounded in **widely discussed evidence and consensus**, tailored to what they wrote.
• Do **not** centre the answer on generic beginner gym habits, this app's workout templates, or boilerplate motivation.
• Assume they already have qualified coaches and medical staff; phrase items as **considerations to align with their staff**, not commands.
• No medical diagnosis, no prescribing injury treatment, no hype stacks for supplements or illegal ergogenic aids.
• Where evidence is mixed or highly individual (heat, altitude, novel supplements), say uncertainty briefly. **Never invent paper titles, authors, journal names, or publication years.**
• Max ~450 words total.
• Plain text bullets only (no markdown headings).
• **BANNED phrases** (do not write any of these — they are app-app slop): ${bannedList}.`
    : `The user wrote this fitness goal in their own words:
"${sanitizePromptInput(userGoal)}"
${intentBlock ? `\nDetected focus areas — use these to direct your bullets:${intentBlock}\n` : ''}
Write a "Coach Advice" panel for this user — what an experienced strength &
conditioning coach would tell them in the first 15 minutes of a consultation.

Structure (label each section with **bold name** then 1–2 bullets under it):
**Primary principle** — the single most important training principle for this goal.
**Weekly priorities** — what gets covered each week (patterns, energy systems, volume).
**Common mistakes** — what people get wrong on the way to this goal; how to avoid them.
**Specific protocol** — one programming detail with numbers (sets, reps, rest, frequency).
**Recovery** — sleep, off-day movement, how to read fatigue signals.
**Nutrition** — 1–2 specific habits with quantity (grams, timing, meals).

Hard rules:
- Each bullet starts with "• " (no asterisks, no dashes).
- Every bullet MUST include at least one of: a number, a specific cue, a specific protocol detail, or a named exercise/movement. **Abstract motivation is not allowed.**
- **BANNED phrases** (rewrite without them): ${bannedList}.
- Skip a section if it doesn't apply — don't pad.
- English only. Max ~280 words total. No markdown except the **bold section names**.
- No medical diagnosis, no injury prescription.`

  const adviceSystem = useEliteGoalAdvice
    ? `${ZVELT_APP_CONTEXT_FOR_AI}

You write evidence-informed performance guidance for athletes who compete at national-team, professional-league, Olympic, or international championship level (or equivalent). You do not give beginner gym lectures, sell app features, or rely on generic motivation. Every bullet is concrete and falsifiable. No markdown headings in your reply.`
    : `${ZVELT_APP_CONTEXT_FOR_AI}

You write coach-quality advice for recreational and club-level athletes, modeled after a real strength & conditioning coach speaking to a new client. Specific, quantified, prescriptive — never motivational filler. Every line is something the user can act on this week. Banned: platitudes that every fitness app already says. Bold section labels are allowed; no other markdown.`

  try {
    const adviceOut = await deepSeekChat(
      [
        { role: 'system', content: adviceSystem },
        { role: 'user', content: advicePrompt },
      ],
      useEliteGoalAdvice ? { maxTokens: 950, temperature: 0.34 } : { maxTokens: 700, temperature: 0.4 },
    )
    return String(adviceOut.text || '')
      .trim()
      .replace(/^```[\w]*\n?/gm, '')
      .replace(/```$/gm, '')
      .trim()
      .slice(0, 12000)
  } catch {
    return ''
  }
}
