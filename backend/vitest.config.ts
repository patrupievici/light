import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    // Match *.test.ts colocated next to the source they cover. Keeps the
    // unit being tested one folder click away — easier than a parallel
    // `tests/` tree.
    include: ['src/**/*.test.ts'],
    // Pure unit tests don't need Node API mocking; default 'node' env is fine.
    environment: 'node',
    // Tests touching the DB would need this raised; for now everything is
    // pure-function so 5s is plenty.
    testTimeout: 5_000,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html'],
      include: [
        'src/services/ranking.service.ts',
        'src/lib/exercise-resolver.ts',
        'src/lib/progressive-overload.ts',
        'src/lib/goal-guidance.ts',
        'src/services/weekly-plan.service.ts',
        'src/services/deterministic-workout.service.ts',
      ],
    },
  },
})
