import { describe, it, expect } from 'vitest'

import { buildGoalGuidance, detectGoalIntents, goalTagsForIntent, hasInjuryContext, __testIntents } from './goal-guidance'

/**
 * The relevance "brain": free-text goal → which training guidance block gets
 * injected into the planner prompt. This is what makes "I want to dunk a
 * basketball" produce plyometrics instead of a generic strength block — the
 * regression that shipped silently before.
 */
describe('buildGoalGuidance', () => {
  it('routes dunk / basketball goals to the vertical-jump block', () => {
    for (const goal of [
      'I want to dunk a basketball',
      'help me increase my vertical jump',
      'jump higher for volleyball spikes',
    ]) {
      const g = buildGoalGuidance(goal)
      expect(g, goal).toContain('[VERTICAL JUMP / DUNK]')
      expect(g, goal).toContain('Plyometrics')
      expect(g, goal).toMatch(/single-leg/i)
      // Must NOT silently fall back to a pure-strength program.
      expect(g, goal).not.toContain('[STRENGTH / POWERLIFTING / 1RM]')
    }
  })

  it('routes fat-loss phrasing to the fat-loss block', () => {
    for (const goal of ['I want to lose 10kg', 'get lean and shredded', 'burn fat for summer']) {
      expect(buildGoalGuidance(goal), goal).toContain('[FAT LOSS / CUT / LEAN]')
    }
  })

  it('routes endurance phrasing to the endurance block', () => {
    for (const goal of ['train for a marathon', 'run a 5k under 25 min', 'build aerobic base for cycling']) {
      expect(buildGoalGuidance(goal), goal).toContain('[ENDURANCE / CARDIO / RUNNING / CYCLING]')
    }
  })

  it('routes powerlifting / strength phrasing to the strength block', () => {
    for (const goal of ['I want to get stronger', 'powerlifting total PR', 'hit a 1RM max on squat']) {
      expect(buildGoalGuidance(goal), goal).toContain('[STRENGTH / POWERLIFTING / 1RM]')
    }
  })

  it('routes muscle-building phrasing to the hypertrophy block', () => {
    for (const goal of ['build muscle and get jacked', 'put on size', 'bodybuilding hypertrophy']) {
      expect(buildGoalGuidance(goal), goal).toContain('[MUSCLE / HYPERTROPHY / BODYBUILDING]')
    }
  })

  it('stacks multiple detected intents', () => {
    const g = buildGoalGuidance('I want to lose fat and run a marathon')
    expect(g).toContain('[FAT LOSS / CUT / LEAN]')
    expect(g).toContain('[ENDURANCE / CARDIO / RUNNING / CYCLING]')
  })

  it('returns empty string when nothing matches or input is blank', () => {
    expect(buildGoalGuidance('')).toBe('')
    expect(buildGoalGuidance(null)).toBe('')
    expect(buildGoalGuidance(undefined)).toBe('')
    expect(buildGoalGuidance('asdfqwer zzz')).toBe('')
  })

  it('detectGoalIntents + goalTagsForIntent widen the pool additively for a free-text goal', () => {
    // The exact regression: "dunk a basketball" must contribute explosive_power
    // pool tags so plyometric exercises survive the candidate filter, even when
    // the picker enum says something else (e.g. strength/hypertrophy).
    expect(detectGoalIntents('I want to dunk a basketball')).toContain('jump');
    expect(goalTagsForIntent('jump')).toContain('explosive_power');
    expect(detectGoalIntents('run a marathon')).toContain('endurance');
    expect(detectGoalIntents('')).toEqual([]);
  });

  it('only treats "faster" as sprint in a running context', () => {
    expect(detectGoalIntents('swim faster')).not.toContain('sprint');
    expect(detectGoalIntents('type faster')).not.toContain('sprint');
    expect(detectGoalIntents('run faster')).toContain('sprint');
    expect(detectGoalIntents('sprint faster')).toContain('sprint');
  });

  it('does not treat bare "basketball" as a jump goal (only dunk/vertical do)', () => {
    expect(buildGoalGuidance('basketball conditioning')).toBe('');
    expect(buildGoalGuidance('dunk a basketball')).toContain('[VERTICAL JUMP / DUNK]');
  });

  it('recognizes "bulk" as hypertrophy', () => {
    expect(buildGoalGuidance('lean bulk')).toContain('[MUSCLE / HYPERTROPHY / BODYBUILDING]');
  });

  it('flags injury / constraint context', () => {
    expect(hasInjuryContext('get stronger after ACL surgery')).toBe(true);
    expect(hasInjuryContext('dunk again but my achilles is fragile')).toBe(true);
    expect(hasInjuryContext('lose fat with knee pain')).toBe(true);
    expect(hasInjuryContext('build muscle')).toBe(false);
  });

  it('exposes a stable set of intent labels', () => {
    // Guards against an intent being accidentally deleted in a refactor.
    expect(__testIntents).toEqual(
      expect.arrayContaining(['jump', 'sprint', 'strength', 'calisthenics', 'fat_loss', 'hypertrophy', 'endurance']),
    )
  })
})
