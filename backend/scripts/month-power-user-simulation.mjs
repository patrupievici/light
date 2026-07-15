import crypto from 'node:crypto'

const baseUrl = (process.env.ZVELT_BASE_URL ?? 'https://light-l6en.onrender.com').replace(/\/+$/, '')
const keepAccount = process.env.ZVELT_KEEP_ACCOUNT === '1'
const strict = process.env.ZVELT_STRICT === '1'
const minRequestIntervalMs = Math.max(650, Number(process.env.ZVELT_REQUEST_INTERVAL_MS ?? 700))
const runId = `${Date.now().toString(36)}${crypto.randomBytes(3).toString('hex')}`
const email = `codex.month.${runId}@example.com`
const password = `Month!${crypto.randomBytes(12).toString('hex')}`

const PROGRAM_IDS = [
  'stronglifts_5x5',
  'full_body_3day',
  'upper_lower_4day',
  'ppl_6day',
  'phul',
  'arnold_split',
  'nsuns_4day',
  '531_bbb',
  'basic_beginner',
  'gzclp',
  '531_monolith',
]

const checks = []
const requestLatencies = []
const requestSamples = []
const statusCounts = new Map()
let requestCount = 0
let rateLimitRetries = 0
let lastRequestAt = 0
let accessToken = null
let accountDeleted = false

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function routeKey(method, path) {
  const pathname = path.split('?')[0].replace(
    /[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/gi,
    ':id',
  )
  return `${method} ${pathname}`
}

function ymd(date) {
  return date.toISOString().slice(0, 10)
}

function dateAt(day, hour, minute = 0) {
  const d = new Date(day)
  d.setUTCHours(hour, minute, 0, 0)
  return d
}

function record(name, ok, detail = '') {
  checks.push({ name, ok, ...(detail ? { detail } : {}) })
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ` | ${detail}` : ''}`)
  return ok
}

function requireCheck(name, ok, detail = '') {
  record(name, ok, detail)
  if (!ok) throw new Error(`${name}${detail ? `: ${detail}` : ''}`)
}

async function api(method, path, token, body, options = {}) {
  const maxAttempts = options.retryRateLimit === false ? 1 : 4
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const sinceLast = Date.now() - lastRequestAt
    if (sinceLast < minRequestIntervalMs) await sleep(minRequestIntervalMs - sinceLast)

    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), options.timeoutMs ?? 60_000)
    const headers = { accept: 'application/json', 'cache-control': 'no-cache' }
    if (token) headers.authorization = `Bearer ${token}`
    if (body !== undefined) headers['content-type'] = 'application/json'
    const started = Date.now()

    try {
      lastRequestAt = Date.now()
      const response = await fetch(`${baseUrl}${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: controller.signal,
      })
      const latencyMs = Date.now() - started
      requestLatencies.push(latencyMs)
      requestSamples.push({ key: routeKey(method, path), method, status: response.status, latencyMs })
      requestCount += 1
      statusCounts.set(response.status, (statusCounts.get(response.status) ?? 0) + 1)

      const raw = await response.text()
      let parsedBody = null
      try {
        parsedBody = raw ? JSON.parse(raw) : null
      } catch {
        parsedBody = raw
      }

      if (response.status === 429 && attempt < maxAttempts) {
        rateLimitRetries += 1
        const retryAfter = Number(response.headers.get('retry-after') ?? 1)
        await sleep(Math.max(1, retryAfter) * 1000)
        continue
      }

      return {
        status: response.status,
        body: parsedBody,
        latencyMs,
        headers: Object.fromEntries(response.headers.entries()),
      }
    } finally {
      clearTimeout(timeout)
    }
  }
  throw new Error(`${method} ${path} exhausted retries`)
}

function routePoints({ distanceM, durationS, startedAt, latitudeSeed }) {
  const count = 25
  const latDelta = distanceM / 111_320
  return Array.from({ length: count }, (_, index) => {
    const ratio = index / (count - 1)
    return {
      lat: latitudeSeed + latDelta * ratio,
      lng: -0.12,
      t: startedAt.getTime() + Math.round(durationS * 1000 * ratio),
    }
  })
}

async function completeProgramWorkout(programId, day, counters) {
  const templateResponse = await api('GET', `/v1/programs/templates/${programId}`, accessToken)
  requireCheck(
    `${programId}: template detail`,
    templateResponse.status === 200 && templateResponse.body?.template?.id === programId,
    `status=${templateResponse.status}`,
  )
  const template = templateResponse.body.template
  const oneRepMaxes = Object.fromEntries(
    (template.trainingMaxLifts ?? []).map((lift, index) => [lift, 100 + index * 20]),
  )
  const startResponse = await api('POST', '/v1/programs/start', accessToken, {
    templateId: programId,
    weeks: template.defaultWeeks,
    ...(Object.keys(oneRepMaxes).length > 0 ? { oneRepMaxes } : {}),
  })
  requireCheck(
    `${programId}: program start`,
    startResponse.status === 201 && startResponse.body?.program?.templateId === programId,
    `status=${startResponse.status}`,
  )
  const userProgramId = startResponse.body.program.id

  const materialized = await api(
    'POST',
    `/v1/programs/${userProgramId}/start-day`,
    accessToken,
    undefined,
    { timeoutMs: 90_000 },
  )
  requireCheck(
    `${programId}: materialize day`,
    materialized.status === 201 && Boolean(materialized.body?.workoutId),
    `status=${materialized.status} error=${materialized.body?.error ?? 'none'}`,
  )
  const workoutId = materialized.body.workoutId

  const workoutResponse = await api('GET', `/v1/workouts/${workoutId}`, accessToken)
  const exercises = workoutResponse.body?.workout?.exercises ?? []
  const setCount = exercises.reduce((sum, exercise) => sum + (exercise.sets?.length ?? 0), 0)
  requireCheck(
    `${programId}: tracker payload`,
    workoutResponse.status === 200 && exercises.length > 0 && setCount > 0,
    `exercises=${exercises.length} sets=${setCount}`,
  )
  const weightedWorkSets = exercises.flatMap((exercise) =>
    exercise.exercise?.rankModel === 'WEIGHTED'
      ? (exercise.sets ?? []).filter((set) => set.tag === 'WORK')
      : [],
  )
  const zeroLoadCount = weightedWorkSets.filter((set) => Number(set.weightKg) <= 0).length
  requireCheck(
    `${programId}: safe first-session loads`,
    weightedWorkSets.length > 0 && zeroLoadCount === 0,
    `weightedSets=${weightedWorkSets.length} zeroLoad=${zeroLoadCount}`,
  )

  for (const exercise of exercises) {
    for (const set of exercise.sets ?? []) {
      if (set.isCompleted === true) continue
      const patched = await api(
        'PATCH',
        `/v1/workouts/${workoutId}/exercises/${exercise.id}/sets/${set.id}`,
        accessToken,
        { isCompleted: true },
      )
      requireCheck(
        `${programId}: complete planned set ${set.id.slice(0, 8)}`,
        patched.status === 200 && patched.body?.set?.isCompleted === true,
        `status=${patched.status}`,
      )
      counters.completedSets += 1
    }
  }

  const startedAt = dateAt(day, 12)
  const endedAt = dateAt(day, 13, 15)
  const completed = await api(
    'POST',
    `/v1/workouts/${workoutId}/complete`,
    accessToken,
    {
      startedAt: startedAt.toISOString(),
      endedAt: endedAt.toISOString(),
      timezone: 'Europe/London',
    },
    { timeoutMs: 90_000 },
  )
  requireCheck(
    `${programId}: complete workout`,
    completed.status === 200 && completed.body?.workout?.status === 'completed',
    `status=${completed.status} error=${completed.body?.error ?? 'none'}`,
  )

  const advanced = await api('POST', `/v1/programs/${userProgramId}/advance`, accessToken)
  requireCheck(
    `${programId}: advance progression`,
    advanced.status === 200 && advanced.body?.program?.sessionIndex === 1,
    `status=${advanced.status} session=${advanced.body?.program?.sessionIndex ?? 'missing'}`,
  )
  counters.programsUsed += 1
  return workoutId
}

async function completeCustomWorkout(day, dayIndex, exercises, counters) {
  const startedAt = dateAt(day, 12)
  const endedAt = dateAt(day, 13, 10)
  const created = await api('POST', '/v1/workouts', accessToken, {
    label: `Power month day ${dayIndex + 1}`,
    startedAt: startedAt.toISOString(),
    timezone: 'Europe/London',
  })
  requireCheck(
    `day ${dayIndex + 1}: create custom workout`,
    created.status === 201 && Boolean(created.body?.workout?.id),
    `status=${created.status}`,
  )
  const workoutId = created.body.workout.id

  for (let exerciseIndex = 0; exerciseIndex < exercises.length; exerciseIndex += 1) {
    const exercise = exercises[exerciseIndex]
    const added = await api('POST', `/v1/workouts/${workoutId}/exercises`, accessToken, {
      exerciseId: exercise.id,
      position: exerciseIndex,
      restSecondsDefault: 120,
    })
    requireCheck(
      `day ${dayIndex + 1}: add ${exercise.name}`,
      added.status === 201 && Boolean(added.body?.workoutExercise?.id),
      `status=${added.status}`,
    )
    const workoutExerciseId = added.body.workoutExercise.id

    for (let setIndex = 0; setIndex < 3; setIndex += 1) {
      const weightKg = 55 + exerciseIndex * 7.5 + Math.floor(dayIndex / 7) * 2.5
      const setResponse = await api(
        'POST',
        `/v1/workouts/${workoutId}/exercises/${workoutExerciseId}/sets`,
        accessToken,
        {
          weightKg,
          reps: [5, 6, 8][setIndex],
          rpe: 7 + setIndex * 0.5,
          tag: 'WORK',
          isCompleted: true,
          clientSetId: crypto.randomUUID(),
          note: 'Synthetic 30-day QA progression data',
        },
      )
      requireCheck(
        `day ${dayIndex + 1}: log set ${exerciseIndex + 1}.${setIndex + 1}`,
        (setResponse.status === 200 || setResponse.status === 201) && Boolean(setResponse.body?.set?.id),
        `status=${setResponse.status}`,
      )
      counters.completedSets += 1
    }
  }

  const completed = await api(
    'POST',
    `/v1/workouts/${workoutId}/complete`,
    accessToken,
    {
      startedAt: startedAt.toISOString(),
      endedAt: endedAt.toISOString(),
      timezone: 'Europe/London',
    },
    { timeoutMs: 90_000 },
  )
  requireCheck(
    `day ${dayIndex + 1}: complete custom workout`,
    completed.status === 200 && completed.body?.workout?.status === 'completed',
    `status=${completed.status}`,
  )
  return workoutId
}

async function saveCardio(day, dayIndex, kind, counters) {
  const isRide = kind === 'ride'
  const distanceM = isRide ? 15_000 + dayIndex * 250 : 6_000 + dayIndex * 100
  const targetSpeedMs = isRide ? 4.5 : 3.0
  const durationS = Math.round(distanceM / targetSpeedMs)
  const startedAt = dateAt(day, isRide ? 18 : 8, isRide ? 0 : 30)
  const endedAt = new Date(startedAt.getTime() + durationS * 1000)
  const points = routePoints({
    distanceM,
    durationS,
    startedAt,
    latitudeSeed: 50.0 + dayIndex * 0.001 + (isRide ? 0.3 : 0),
  })
  const response = await api('POST', '/v1/activities', accessToken, {
    activity_type: kind,
    route_points: points,
    distance_m: distanceM,
    duration_s: durationS,
    calories: isRide ? 550 : 450,
    visibility: 'private',
    started_at: startedAt.toISOString(),
    ended_at: endedAt.toISOString(),
  })
  requireCheck(
    `day ${dayIndex + 1}: save ${kind}`,
    response.status === 201 && Boolean(response.body?.activity?.id),
    `status=${response.status}`,
  )
  if (response.body?.activity?.type === kind) counters.createResponsesWithExactType += 1
  counters.expectedActivityTypes.set(response.body.activity.id, kind)

  const xp = await api('POST', '/v1/activities/cardio/complete', accessToken, {
    mode: isRide ? 'bike' : 'run',
    distanceM: Number(response.body?.activity?.distanceM ?? distanceM),
    durationSec: Number(response.body?.activity?.durationS ?? durationS),
    source: 'month-power-user-simulation',
  })
  requireCheck(
    `day ${dayIndex + 1}: award ${kind} XP`,
    xp.status === 200 && Number.isFinite(Number(xp.body?.xpGain)),
    `status=${xp.status}`,
  )
}

async function saveNutrition(day, dayIndex) {
  const date = ymd(day)
  const entries = [
    { id: crypto.randomUUID(), name: 'Oats and berries', meal: 'breakfast', calories: 520, protein: 28, carbs: 72, fat: 13 },
    { id: crypto.randomUUID(), name: 'Chicken rice bowl', meal: 'lunch', calories: 760, protein: 58, carbs: 84, fat: 19 },
    { id: crypto.randomUUID(), name: 'Yogurt and fruit', meal: 'snack', calories: 310, protein: 24, carbs: 38, fat: 7 },
    { id: crypto.randomUUID(), name: 'Salmon and potatoes', meal: 'dinner', calories: 810, protein: 55, carbs: 70, fat: 31 },
  ]
  const put = await api('PUT', '/v1/nutrition/day', accessToken, {
    date,
    entries,
    waterMl: 2500 + (dayIndex % 4) * 250,
    weightKg: 82 - dayIndex * 0.03,
  })
  requireCheck(
    `day ${dayIndex + 1}: nutrition sync`,
    put.status === 200 && put.body?.entries?.length === 4,
    `status=${put.status}`,
  )

  const xp = await api('POST', '/v1/nutrition/claim-xp', accessToken, { date, tzOffset: 0 })
  requireCheck(
    `day ${dayIndex + 1}: nutrition XP`,
    xp.status === 200 && Number.isFinite(Number(xp.body?.xpAwarded)),
    `status=${xp.status}`,
  )
}

function percentile(values, pct) {
  if (values.length === 0) return 0
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * pct))]
}

async function deleteAccount() {
  if (!accessToken || accountDeleted || keepAccount) return
  const response = await api(
    'DELETE',
    '/v1/me/account',
    accessToken,
    { confirm: 'DELETE' },
    { retryRateLimit: false },
  )
  accountDeleted = response.status === 204 || response.status === 401
  record('temporary account cleanup', accountDeleted, `status=${response.status}`)
}

async function main() {
  const counters = {
    programsUsed: 0,
    completedSets: 0,
    postsCreated: 0,
    createResponsesWithExactType: 0,
    expectedActivityTypes: new Map(),
  }
  const workoutIds = []
  const today = new Date()
  today.setUTCHours(0, 0, 0, 0)
  const firstDay = new Date(today.getTime() - 30 * 86_400_000)
  const lastDay = new Date(today.getTime() - 86_400_000)

  console.log(`ZVELT 30-day power-user simulation`)
  console.log(`Target: ${baseUrl}`)
  console.log(`Window: ${ymd(firstDay)} -> ${ymd(lastDay)}`)
  console.log(`Request interval: ${minRequestIntervalMs}ms`)

  try {
    const health = await api('GET', '/health', null)
    requireCheck('production health', health.status === 200, `status=${health.status}`)

    const signup = await api('POST', '/v1/auth/signup', null, {
      email,
      password,
      displayName: 'Month Power User',
    })
    requireCheck('temporary account signup', signup.status === 201, `status=${signup.status}`)
    accessToken = signup.body?.accessToken
    requireCheck('temporary access token', Boolean(accessToken))

    const profile = await api('PATCH', '/v1/me/profile', accessToken, {
      displayName: 'Month Power User',
      username: `month_${runId}`.slice(0, 30),
      bodyweightKg: 82,
      birthYear: 1992,
      sex: 'male',
      units: 'metric',
    })
    requireCheck('power-user profile setup', profile.status === 200, `status=${profile.status}`)

    const templatesResponse = await api('GET', '/v1/programs/templates', accessToken)
    const templates = templatesResponse.body?.data ?? []
    requireCheck(
      'all 11 program templates available',
      templatesResponse.status === 200 && PROGRAM_IDS.every((id) => templates.some((item) => item.id === id)),
      `available=${templates.length}`,
    )

    const exerciseResponse = await api('GET', '/v1/exercises?ranked=true&limit=500', accessToken)
    const rankedExercises = (exerciseResponse.body?.data ?? []).filter(
      (exercise) => exercise.isRanked && exercise.rankModel === 'WEIGHTED',
    )
    requireCheck(
      'ranked exercise catalogue for high-volume logging',
      exerciseResponse.status === 200 && rankedExercises.length >= 3,
      `weighted=${rankedExercises.length}`,
    )

    for (let dayIndex = 0; dayIndex < 30; dayIndex += 1) {
      const day = new Date(firstDay.getTime() + dayIndex * 86_400_000)
      console.log(`\nDAY ${String(dayIndex + 1).padStart(2, '0')} ${ymd(day)}`)

      const workoutId = dayIndex < PROGRAM_IDS.length
        ? await completeProgramWorkout(PROGRAM_IDS[dayIndex], day, counters)
        : await completeCustomWorkout(day, dayIndex, rankedExercises.slice(0, 3), counters)
      workoutIds.push(workoutId)

      if (dayIndex % 3 === 0) {
        const post = await api('POST', '/v1/posts', accessToken, {
          workoutId,
          visibility: 'private',
          caption: `Power month day ${dayIndex + 1}: strength, run and ride`,
        })
        requireCheck(
          `day ${dayIndex + 1}: workout post`,
          post.status === 201 && Boolean(post.body?.post?.id),
          `status=${post.status}`,
        )
        counters.postsCreated += 1
      }

      await saveCardio(day, dayIndex, 'run', counters)
      await saveCardio(day, dayIndex, 'ride', counters)
      await saveNutrition(day, dayIndex)
    }

    record('all program templates exercised', counters.programsUsed === PROGRAM_IDS.length, `used=${counters.programsUsed}`)
    record('30 strength workouts completed', workoutIds.length === 30, `completed=${workoutIds.length}`)
    record('high-volume set logging completed', counters.completedSets >= 200, `sets=${counters.completedSets}`)
    record('10 private progress posts created', counters.postsCreated === 10, `posts=${counters.postsCreated}`)

    const prFeed = await api('GET', '/v1/posts/feed?kind=pr&limit=50', accessToken)
    record(
      'workout PR survives complete-to-post transition',
      prFeed.status === 200 && (prFeed.body?.data?.length ?? 0) > 0,
      `prPosts=${prFeed.body?.data?.length ?? 0}`,
    )

    const workouts = await api('GET', '/v1/workouts?limit=50', accessToken)
    const completedWorkouts = (workouts.body?.data ?? []).filter(
      (workout) => workout.status === 'completed' || workout.status === 'posted',
    )
    record(
      'workout list preserves all 30 sessions',
      workouts.status === 200 && completedWorkouts.length === 30,
      `completed=${completedWorkouts.length}`,
    )

    const feedResponse = await api('GET', '/v1/activities/feed', accessToken)
    const feed = feedResponse.body?.feed ?? []
    const feedCounts = feed.reduce((acc, item) => {
      acc[item.type] = (acc[item.type] ?? 0) + 1
      return acc
    }, {})
    record('unified feed contains 90 efforts', feedResponse.status === 200 && feed.length === 90, `count=${feed.length}`)
    record(
      'saved cardio response preserves explicit sport type',
      counters.createResponsesWithExactType === 60,
      `exact=${counters.createResponsesWithExactType}/60`,
    )
    const exactFeedTypes = [...counters.expectedActivityTypes.entries()].filter(([id, type]) =>
      feed.some((item) => item.id === id && item.type === type),
    ).length
    record(
      'unified feed preserves 30 runs and 30 rides',
      exactFeedTypes === 60 && feedCounts.run === 30 && feedCounts.ride === 30,
      `exact=${exactFeedTypes}/60 counts=${JSON.stringify(feedCounts)}`,
    )

    const months = [...new Set(Array.from({ length: 30 }, (_, index) => {
      const day = new Date(firstDay.getTime() + index * 86_400_000)
      return ymd(day).slice(0, 7)
    }))]
    let calendarDays = 0
    let completeCalendarDays = 0
    for (const month of months) {
      const calendar = await api('GET', `/v1/activities/calendar?month=${month}&tzOffset=0`, accessToken)
      requireCheck(`${month}: activity calendar response`, calendar.status === 200, `status=${calendar.status}`)
      for (let index = 0; index < 30; index += 1) {
        const day = new Date(firstDay.getTime() + index * 86_400_000)
        if (!ymd(day).startsWith(month)) continue
        calendarDays += 1
        const types = calendar.body?.days?.[ymd(day)]?.types ?? []
        if (types.includes('gym') && types.includes('run') && types.includes('ride')) completeCalendarDays += 1
      }
    }
    record(
      'calendar sync shows strength, run and ride on every day',
      completeCalendarDays === calendarDays && calendarDays === 30,
      `complete=${completeCalendarDays}/${calendarDays}`,
    )

    const nutrition = await api(
      'GET',
      `/v1/nutrition/days?from=${ymd(firstDay)}&to=${ymd(lastDay)}`,
      accessToken,
    )
    record(
      'nutrition range preserves all 30 days',
      nutrition.status === 200 && nutrition.body?.data?.length === 30,
      `days=${nutrition.body?.data?.length ?? 0}`,
    )

    const volume = await api(
      'GET',
      `/v1/me/stats/cumulative-volume?year=${firstDay.getUTCFullYear()}`,
      accessToken,
    )
    record(
      'volume chart attributes sets to all 30 workout dates',
      volume.status === 200 && volume.body?.activeDays === 30,
      `activeDays=${volume.body?.activeDays ?? 'missing'} totalKg=${volume.body?.totalKg ?? 'missing'}`,
    )

    const recentPrs = await api('GET', '/v1/me/stats/recent-prs?days=180', accessToken)
    const prDates = (recentPrs.body?.data ?? []).map((pr) => String(pr.date).slice(0, 10))
    const prsInsideWindow = prDates.every((date) => date >= ymd(firstDay) && date <= ymd(lastDay))
    record(
      'PR history uses workout dates instead of sync timestamps',
      recentPrs.status === 200 && prDates.length > 0 && prsInsideWindow,
      `prs=${prDates.length} dates=${[...new Set(prDates)].slice(0, 8).join(',')}`,
    )

    const ranks = await api('GET', '/v1/ranks/me', accessToken)
    record(
      'ranking remains available after high-volume month',
      ranks.status === 200 && (ranks.body?.ranks?.length ?? 0) >= 3,
      `ranks=${ranks.body?.ranks?.length ?? 0}`,
    )

    const posts = await api('GET', '/v1/posts?mine=true&limit=50', accessToken)
    record(
      'profile gallery preserves all monthly posts',
      posts.status === 200 && posts.body?.data?.length === 10,
      `posts=${posts.body?.data?.length ?? 0}`,
    )

    record('no unexpected server errors', ![...statusCounts.keys()].some((status) => status >= 500), JSON.stringify(Object.fromEntries(statusCounts)))
    record('no rate-limit responses at realistic pacing', rateLimitRetries === 0, `retries=${rateLimitRetries}`)
    const readP95 = percentile(
      requestSamples.filter((sample) => sample.method === 'GET').map((sample) => sample.latencyMs),
      0.95,
    )
    const writeP95 = percentile(
      requestSamples.filter((sample) => sample.method !== 'GET').map((sample) => sample.latencyMs),
      0.95,
    )
    record('production read p95 meets 300ms SLO', readP95 < 300, `p95=${readP95}ms`)
    record('production write p95 meets 800ms SLO', writeP95 < 800, `p95=${writeP95}ms`)
  } finally {
    await deleteAccount()
  }

  const passed = checks.filter((check) => check.ok).length
  const failed = checks.filter((check) => !check.ok)
  const p50 = percentile(requestLatencies, 0.5)
  const p95 = percentile(requestLatencies, 0.95)
  const routeLatency = [...requestSamples.reduce((groups, sample) => {
    const values = groups.get(sample.key) ?? []
    values.push(sample.latencyMs)
    groups.set(sample.key, values)
    return groups
  }, new Map()).entries()]
    .map(([key, values]) => ({
      route: key,
      count: values.length,
      p50: percentile(values, 0.5),
      p95: percentile(values, 0.95),
      max: Math.max(...values),
    }))
    .sort((a, b) => b.p95 - a.p95)
  const report = {
    target: baseUrl,
    simulatedWindow: { from: ymd(firstDay), to: ymd(lastDay) },
    requests: requestCount,
    latencyMs: { p50, p95, max: Math.max(0, ...requestLatencies) },
    slowestRoutes: routeLatency.slice(0, 12),
    statusCounts: Object.fromEntries(statusCounts),
    checks: { passed, failed: failed.length, total: checks.length },
    failures: failed,
    accountCleanup: keepAccount ? 'kept by request' : accountDeleted ? 'deleted' : 'failed',
  }
  console.log('\nSIMULATION_REPORT')
  console.log(JSON.stringify(report, null, 2))
  if (keepAccount) console.log(`TEST_ACCOUNT ${email} ${password}`)
  if (strict && failed.length > 0) process.exitCode = 1
}

main().catch(async (error) => {
  console.error(`FATAL ${error?.stack ?? error}`)
  try {
    await deleteAccount()
  } catch (cleanupError) {
    console.error(`CLEANUP_FATAL ${cleanupError?.stack ?? cleanupError}`)
  }
  process.exitCode = 1
})
