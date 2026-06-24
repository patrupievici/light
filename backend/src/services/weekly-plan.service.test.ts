import { describe, it, expect } from 'vitest'

import {
  buildWeeklyPlanInputs,
  type PromptProfileInput,
  type PromptTrainingProfileInput,
  type WeeklyPlanOpts,
} from './weekly-plan.service'

/**
 * Integration test for the critical path the app's whole value prop rests on:
 *
 *   user types a free-text goal  →  the planner prompt is built around it.
 *
 * This is exactly the contract that broke silently in production: the onboarding
 * goal ("I want to dunk a basketball") never reached the prompt, so the LLM got
 * only the generic enum bucket and returned generic strength work. We can't
 * (cheaply, deterministically) assert on the LLM's *output*, but we CAN assert
 * that the prompt fed to it carries the goal as top priority, with the right
 * goal-specific guidance and dietary constraints. If that holds, relevance is
 * the model's job; if it doesn't, no model could recover.
 */

const profile: PromptProfileInput = {
  bodyweightKg: 82,
  heightCm: 186,
  sex: 'male',
  birthYear: 1996,
}

function trainingProfile(over: Partial<PromptTrainingProfileInput> = {}): PromptTrainingProfileInput {
  return {
    onboardingGoalText: null,
    primaryGoal: null,
    equipment: ['full_commercial_gym'],
    daysPerWeek: 4,
    sessionMinutes: 60,
    trainingLevel: 'intermediate',
    ...over,
  }
}

function build(opts: WeeklyPlanOpts, tpOver: Partial<PromptTrainingProfileInput> = {}) {
  return buildWeeklyPlanInputs({
    profile,
    trainingProfile: trainingProfile(tpOver),
    opts,
    progressionBlock: '',
  })
}

describe('buildWeeklyPlanInputs — goal → prompt contract', () => {
  it('puts the user free-text goal in the prompt as TOP priority (the dunk regression)', () => {
    const { prompt, effectiveGoalText } = build({
      goalText: 'I want to dunk a basketball',
      goal: 'strength', // a misleading enum hint — must NOT win over the text
    })

    expect(effectiveGoalText).toBe('I want to dunk a basketball')
    expect(prompt).toContain('dunk a basketball')
    expect(prompt).toContain("their own words — top priority")
    // The enum is present but explicitly demoted to a hint.
    expect(prompt).toContain('Goal category (hint): strength')
    // Goal-specific guidance must be jump training, not generic strength.
    expect(prompt).toContain('[VERTICAL JUMP / DUNK]')
    expect(prompt).toContain('Plyometrics')
  })

  it('falls back to the enum bucket only when there is no free-text goal', () => {
    const { prompt, effectiveGoalText } = build({ goal: 'hypertrophy' }, { primaryGoal: 'hypertrophy' })
    expect(effectiveGoalText).toBe('')
    expect(prompt).toContain('Goal: hypertrophy')
    expect(prompt).not.toContain('their own words')
  })

  it('reads the goal from the saved training profile when the request omits it', () => {
    const { prompt, effectiveGoalText } = build({}, { onboardingGoalText: 'run my first marathon' })
    expect(effectiveGoalText).toBe('run my first marathon')
    expect(prompt).toContain('run my first marathon')
    expect(prompt).toContain('[ENDURANCE / CARDIO / RUNNING / CYCLING]')
  })

  it('injects dietary restrictions into the nutrition section', () => {
    const { prompt } = build({
      goalText: 'build muscle',
      dietaryRestrictions: ['Vegan', 'Gluten-free'],
    })
    expect(prompt).toContain('Dietary restrictions: Vegan, Gluten-free')
    expect(prompt).toMatch(/MUST respect the user's dietary restrictions/i)
  })

  it('omits the dietary section entirely when none are given', () => {
    const { prompt } = build({ goalText: 'build muscle' })
    expect(prompt).not.toContain('Dietary restrictions:')
  })

  it('sanitizes, de-dupes and caps the dietary list', () => {
    const { prompt } = build({
      goalText: 'build muscle',
      dietaryRestrictions: ['Vegan', 'Vegan', '   ', ...Array.from({ length: 20 }, (_, i) => `tag${i}`)],
    })
    const line = prompt.split('\n').find((l) => l.startsWith('- Dietary restrictions:')) ?? ''
    const items = line.replace('- Dietary restrictions:', '').split(',').map((s) => s.trim()).filter(Boolean)
    expect(items.length).toBeLessThanOrEqual(12) // hard cap
    expect(items.filter((x) => x === 'Vegan').length).toBe(1) // de-duped
    expect(items).not.toContain('') // blank entries dropped
  })

  it('flags a goal change and asks for a rationale when previousGoalText differs', () => {
    const changed = build({ goalText: 'switch to powerlifting', previousGoalText: 'I want to dunk a basketball' })
    expect(changed.isGoalChange).toBe(true)
    expect(changed.prompt).toContain('PREVIOUS GOAL')
    expect(changed.prompt).toContain('goalChangeRationale')

    const same = build({ goalText: 'I want to dunk a basketball', previousGoalText: 'I want to dunk a basketball' })
    expect(same.isGoalChange).toBe(false)
    expect(same.prompt).not.toContain('PREVIOUS GOAL')
  })

  it('honors applyDailyTargets (default true, false opt-out)', () => {
    expect(build({ goalText: 'build muscle' }).shouldApplyTargets).toBe(true)
    expect(build({ goalText: 'build muscle', applyDailyTargets: false }).shouldApplyTargets).toBe(false)
  })
})
