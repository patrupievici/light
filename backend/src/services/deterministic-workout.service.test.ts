import { describe, it, expect } from 'vitest'

import { resolveGoalComponents, routeWorkoutGoal } from './deterministic-workout.service'
import { PROGRAM_BLUEPRINTS } from '../programming/blueprints'

/**
 * The routing contract for the deterministic engine: a free-text goal resolves
 * (additively) into component tags, and a covered goal has a specific blueprint
 * to fill. The dunk case is the regression that started all this.
 */
describe('deterministic engine — goal resolution + blueprint coverage', () => {
  it('resolves "dunk" additively to explosive components (even with a strength enum)', () => {
    const comps = resolveGoalComponents({
      primaryGoal: 'strength', // a misleading picker enum
      onboardingGoalText: 'I want to dunk a basketball',
    });
    expect(comps).toContain('explosive_power');
    expect(comps).toContain('vertical_jump');
    expect(comps).toContain('strength'); // additive: enum kept too
  });

  it('a specific (non-*) blueprint covers the dunk components', () => {
    const comps = resolveGoalComponents({ primaryGoal: null, onboardingGoalText: 'dunk' });
    const covered = PROGRAM_BLUEPRINTS.some(
      (b) => !b.primaryGoals.includes('*') && b.primaryGoals.some((g) => comps.includes(g)),
    );
    expect(covered).toBe(true); // -> deterministic path, not LLM fallback
  });

  it('maps common free-text goals to components', () => {
    expect(resolveGoalComponents({ primaryGoal: null, onboardingGoalText: 'lose fat for summer' })).toContain('fat_loss');
    expect(resolveGoalComponents({ primaryGoal: null, onboardingGoalText: 'build muscle' })).toContain('hypertrophy');
    expect(resolveGoalComponents({ primaryGoal: 'strength', onboardingGoalText: '' })).toContain('strength');
  });

  it('returns no components for a goalless input (caller defers to LLM)', () => {
    expect(resolveGoalComponents({ primaryGoal: null, onboardingGoalText: '' })).toEqual([]);
    expect(resolveGoalComponents({ primaryGoal: null, onboardingGoalText: 'asdf qwer' })).toEqual([]);
  });

  it('routes a NICHE free-text goal to the LLM even when a picker enum is set', () => {
    // The exact bug: "table tennis" + a "strength" picker gave a strength
    // workout because the enum shadowed the unrecognized free text.
    const r = routeWorkoutGoal({ primaryGoal: 'strength', onboardingGoalText: 'table tennis' });
    expect(r.defer).toBe(true); // -> LLM decomposition, NOT the strength blueprint
  });

  it('lets the free-text goal win the blueprint over the picker enum', () => {
    // "dunk" + "strength" picker must route to jump, not strength.
    const r = routeWorkoutGoal({ primaryGoal: 'strength', onboardingGoalText: 'I want to dunk' });
    expect(r.defer).toBe(false);
    expect(r.blueprintGoals).toContain('explosive_power');
    expect(r.blueprintGoals).not.toContain('strength'); // enum doesn't drive selection here
  });

  it('falls back to the picker enum only when there is no free-text goal', () => {
    expect(routeWorkoutGoal({ primaryGoal: 'strength', onboardingGoalText: '' })).toEqual({
      defer: false,
      blueprintGoals: ['strength'],
    });
    expect(routeWorkoutGoal({ primaryGoal: null, onboardingGoalText: '' })).toEqual({ defer: true, blueprintGoals: [] });
  });

  it('defers a compound goal (>1 intent) to the LLM to blend', () => {
    expect(routeWorkoutGoal({ primaryGoal: null, onboardingGoalText: 'dunk and run a marathon' }).defer).toBe(true);
    expect(routeWorkoutGoal({ primaryGoal: null, onboardingGoalText: 'lose fat and build muscle' }).defer).toBe(true);
  });

  it('defers injury/constraint goals to the LLM (safety guardrail)', () => {
    expect(routeWorkoutGoal({ primaryGoal: null, onboardingGoalText: 'get stronger after ACL surgery' }).defer).toBe(true);
    expect(routeWorkoutGoal({ primaryGoal: null, onboardingGoalText: 'dunk again but my achilles is fragile' }).defer).toBe(true);
    expect(routeWorkoutGoal({ primaryGoal: null, onboardingGoalText: 'build muscle with a bad shoulder' }).defer).toBe(true);
    // No injury -> still routes normally.
    expect(routeWorkoutGoal({ primaryGoal: null, onboardingGoalText: 'build muscle' }).defer).toBe(false);
  });

  it('defers endurance goals to the LLM (no good deterministic blueprint)', () => {
    expect(routeWorkoutGoal({ primaryGoal: null, onboardingGoalText: 'run a marathon' }).defer).toBe(true);
    expect(routeWorkoutGoal({ primaryGoal: 'strength', onboardingGoalText: '5k under 25 minutes' }).defer).toBe(true);
  });

  it('merges an explicit extra component spec (the seam for an LLM decomposition)', () => {
    const comps = resolveGoalComponents({
      primaryGoal: null,
      onboardingGoalText: 'table tennis',
      extra: ['explosive_power', 'core_anti_rotation', 'upper_power'],
    });
    expect(comps).toEqual(expect.arrayContaining(['explosive_power', 'core_anti_rotation', 'upper_power']));
  });
});
