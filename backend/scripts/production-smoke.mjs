import crypto from 'node:crypto'

const baseUrl = (process.env.ZVELT_BASE_URL ?? 'https://light-l6en.onrender.com').replace(/\/+$/, '')
const password = `Audit!${crypto.randomBytes(12).toString('hex')}`
const runId = `${Date.now().toString(36)}${crypto.randomBytes(3).toString('hex')}`
const ownerEmail = `codex.owner.${runId}@example.com`
const viewerEmail = `codex.viewer.${runId}@example.com`
const guestEmail = `guest_${runId}@guest.zvelt.app`
const convertedEmail = `codex.converted.${runId}@example.com`
const ownerUsername = `audit_owner_${runId}`.slice(0, 30)
const viewerUsername = `audit_viewer_${runId}`.slice(0, 30)
const tinyPng =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6f0sAAAAASUVORK5CYII='

const checks = []
const accounts = {
  owner: { token: null, refreshToken: null, id: null, deleted: false },
  viewer: { token: null, refreshToken: null, id: null, deleted: false },
  guest: { token: null, refreshToken: null, id: null, deleted: false },
}

function record(name, ok, detail = '') {
  checks.push({ name, ok, ...(detail ? { detail } : {}) })
  return ok
}

function requireCheck(name, ok, detail = '') {
  record(name, ok, detail)
  if (!ok) throw new Error(`${name}${detail ? `: ${detail}` : ''}`)
}

async function api(method, path, token, body, options = {}) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs ?? 30_000)
  const headers = {
    accept: 'application/json',
    'cache-control': 'no-cache',
    ...(options.headers ?? {}),
  }
  if (token) headers.authorization = `Bearer ${token}`
  if (body !== undefined) headers['content-type'] = 'application/json'

  try {
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: controller.signal,
    })
    const contentType = response.headers.get('content-type') ?? ''
    let parsedBody = null
    if (contentType.startsWith('image/')) {
      parsedBody = { byteLength: (await response.arrayBuffer()).byteLength }
    } else {
      const raw = await response.text()
      try {
        parsedBody = raw ? JSON.parse(raw) : null
      } catch {
        parsedBody = raw
      }
    }
    return {
      status: response.status,
      body: parsedBody,
      headers: Object.fromEntries(response.headers.entries()),
    }
  } finally {
    clearTimeout(timeout)
  }
}

function statusIs(response, expected) {
  return response.status === expected
}

async function deleteAccount(account) {
  if (!account.token || account.deleted) return
  try {
    const response = await api('DELETE', '/v1/me/account', account.token, { confirm: 'DELETE' })
    if (response.status === 204 || response.status === 401) account.deleted = true
  } catch {
    // The final report exposes cleanup failures through the explicit deletion checks.
  }
}

async function main() {
  let avatarUrl = null
  let privatePostImageUrl = null

  try {
    const health = await api('GET', '/health', null, undefined, {
      headers: { origin: 'https://evil.example' },
    })
    requireCheck('health endpoint', statusIs(health, 200), `status=${health.status}`)
    record('health identifies deployed release', typeof health.body?.release === 'string' && health.body.release.length > 0)
    record(
      'CORS rejects untrusted browser origin',
      health.headers['access-control-allow-origin'] == null,
      `allow-origin=${health.headers['access-control-allow-origin'] ?? 'none'}`,
    )
    record(
      'security headers active',
      health.headers['x-content-type-options'] === 'nosniff' &&
        Boolean(health.headers['strict-transport-security']),
    )
    record('rate-limit headers active', Boolean(health.headers['x-ratelimit-limit']))

    const invalidToken = await api('GET', '/v1/me', 'invalid-token')
    record('invalid access token rejected', statusIs(invalidToken, 401), `status=${invalidToken.status}`)

    const ownerSignup = await api('POST', '/v1/auth/signup', null, {
      email: ownerEmail,
      password,
      displayName: 'Release Owner',
    })
    requireCheck('owner signup', statusIs(ownerSignup, 201), `status=${ownerSignup.status}`)
    accounts.owner.token = ownerSignup.body?.accessToken
    accounts.owner.refreshToken = ownerSignup.body?.refreshToken
    accounts.owner.id = ownerSignup.body?.user?.id
    requireCheck(
      'owner signup tokens and id',
      Boolean(accounts.owner.token && accounts.owner.refreshToken && accounts.owner.id),
    )

    const viewerSignup = await api('POST', '/v1/auth/signup', null, {
      email: viewerEmail,
      password,
      displayName: 'Release Viewer',
    })
    requireCheck('viewer signup', statusIs(viewerSignup, 201), `status=${viewerSignup.status}`)
    accounts.viewer.token = viewerSignup.body?.accessToken
    accounts.viewer.refreshToken = viewerSignup.body?.refreshToken
    accounts.viewer.id = viewerSignup.body?.user?.id
    requireCheck(
      'viewer signup tokens and id',
      Boolean(accounts.viewer.token && accounts.viewer.refreshToken && accounts.viewer.id),
    )

    const guestSignup = await api('POST', '/v1/auth/signup', null, {
      email: guestEmail,
      password,
      displayName: 'Guest Conversion Marker',
    })
    requireCheck('guest signup', statusIs(guestSignup, 201), `status=${guestSignup.status}`)
    accounts.guest.token = guestSignup.body?.accessToken
    accounts.guest.refreshToken = guestSignup.body?.refreshToken
    accounts.guest.id = guestSignup.body?.user?.id
    requireCheck(
      'guest signup tokens and id',
      Boolean(accounts.guest.token && accounts.guest.refreshToken && accounts.guest.id),
    )
    const oldGuestRefresh = accounts.guest.refreshToken

    const guestProfile = await api('PATCH', '/v1/me/profile', accounts.guest.token, {
      displayName: 'Guest Conversion Marker',
      bodyweightKg: 75,
    })
    requireCheck('guest profile before conversion', statusIs(guestProfile, 200), `status=${guestProfile.status}`)

    const guestConversion = await api('POST', '/v1/auth/guest/convert', accounts.guest.token, {
      email: ` ${convertedEmail.toUpperCase()} `,
      password,
    })
    requireCheck('guest account conversion', statusIs(guestConversion, 200), `status=${guestConversion.status}`)
    record(
      'guest conversion preserves user id and normalizes email',
      guestConversion.body?.user?.id === accounts.guest.id &&
        guestConversion.body?.user?.email === convertedEmail,
    )
    accounts.guest.token = guestConversion.body?.accessToken
    accounts.guest.refreshToken = guestConversion.body?.refreshToken
    requireCheck(
      'converted account returns fresh session',
      Boolean(accounts.guest.token && accounts.guest.refreshToken),
    )

    const oldGuestRefreshAfterConversion = await api('POST', '/v1/auth/refresh', null, {
      refreshToken: oldGuestRefresh,
    })
    record(
      'guest conversion revokes old refresh session',
      statusIs(oldGuestRefreshAfterConversion, 401),
      `status=${oldGuestRefreshAfterConversion.status}`,
    )
    const oldGuestLogin = await api('POST', '/v1/auth/login', null, {
      email: guestEmail,
      password,
    })
    record('old guest credentials rejected', statusIs(oldGuestLogin, 401), `status=${oldGuestLogin.status}`)

    const convertedLogin = await api('POST', '/v1/auth/login', null, {
      email: convertedEmail,
      password,
    })
    requireCheck('converted account login', statusIs(convertedLogin, 200), `status=${convertedLogin.status}`)
    accounts.guest.token = convertedLogin.body?.accessToken
    accounts.guest.refreshToken = convertedLogin.body?.refreshToken
    const convertedMe = await api('GET', '/v1/me', accounts.guest.token)
    record(
      'guest profile survives conversion',
      statusIs(convertedMe, 200) &&
        convertedMe.body?.profile?.displayName === 'Guest Conversion Marker' &&
        Number(convertedMe.body?.profile?.bodyweightKg) === 75,
      `status=${convertedMe.status}`,
    )
    const repeatedConversion = await api(
      'POST',
      '/v1/auth/guest/convert',
      accounts.guest.token,
      { email: `second.${convertedEmail}`, password },
    )
    record(
      'converted account cannot be converted twice',
      statusIs(repeatedConversion, 409) && repeatedConversion.body?.error === 'NOT_GUEST_ACCOUNT',
      `status=${repeatedConversion.status}`,
    )

    const duplicateSignup = await api('POST', '/v1/auth/signup', null, {
      email: ownerEmail,
      password,
    })
    record('duplicate email rejected', statusIs(duplicateSignup, 409), `status=${duplicateSignup.status}`)

    const wrongLogin = await api('POST', '/v1/auth/login', null, {
      email: ownerEmail,
      password: `${password}wrong`,
    })
    record('wrong password rejected', statusIs(wrongLogin, 401), `status=${wrongLogin.status}`)

    const refreshed = await api('POST', '/v1/auth/refresh', null, {
      refreshToken: accounts.owner.refreshToken,
    })
    requireCheck('refresh token rotation', statusIs(refreshed, 200), `status=${refreshed.status}`)
    accounts.owner.token = refreshed.body?.accessToken
    const rotatedRefreshToken = refreshed.body?.refreshToken
    requireCheck('rotated session returned', Boolean(accounts.owner.token && rotatedRefreshToken))

    const logout = await api('POST', '/v1/auth/logout', accounts.owner.token)
    record('logout', statusIs(logout, 204), `status=${logout.status}`)
    const refreshAfterLogout = await api('POST', '/v1/auth/refresh', null, {
      refreshToken: rotatedRefreshToken,
    })
    record(
      'logout revokes refresh session',
      statusIs(refreshAfterLogout, 401),
      `status=${refreshAfterLogout.status}`,
    )

    const login = await api('POST', '/v1/auth/login', null, { email: ownerEmail, password })
    requireCheck('login after logout', statusIs(login, 200), `status=${login.status}`)
    accounts.owner.token = login.body?.accessToken
    accounts.owner.refreshToken = login.body?.refreshToken

    const ownerProfile = await api('PATCH', '/v1/me/profile', accounts.owner.token, {
      displayName: 'Release Owner',
      username: ownerUsername,
      bio: 'Production smoke account',
      unitSystem: 'metric',
      bodyweightKg: 80,
      heightCm: 180,
      birthYear: 1990,
      sex: 'male',
      privacyDefault: 'private',
      dailyCalories: 2400,
      dailyProtein: 170,
      dailyCarbs: 270,
      dailyFat: 70,
      dailyWaterMl: 2600,
      nutritionGoal: 'gain',
      nutritionActivityLevel: 'active',
      nutritionDiet: 'omnivore',
      nutritionMealsPerDay: 4,
    })
    requireCheck('owner profile update', statusIs(ownerProfile, 200), `status=${ownerProfile.status}`)

    const viewerProfile = await api('PATCH', '/v1/me/profile', accounts.viewer.token, {
      displayName: 'Release Viewer',
      username: viewerUsername,
      bodyweightKg: 70,
      privacyDefault: 'private',
    })
    requireCheck('viewer profile update', statusIs(viewerProfile, 200), `status=${viewerProfile.status}`)

    const viewerSettings = await api('PATCH', '/v1/me/settings', accounts.viewer.token, {
      discoveryOptIn: true,
      showActivityFeed: true,
    })
    record('privacy settings update', statusIs(viewerSettings, 200), `status=${viewerSettings.status}`)

    const invalidBodyweight = await api('PATCH', '/v1/me/profile', accounts.owner.token, {
      bodyweightKg: 10,
    })
    record(
      'profile validation rejects invalid bodyweight',
      statusIs(invalidBodyweight, 400),
      `status=${invalidBodyweight.status}`,
    )

    const me = await api('GET', '/v1/me', accounts.owner.token)
    requireCheck('profile read', statusIs(me, 200), `status=${me.status}`)
    const profile = me.body?.profile ?? {}
    record('bodyweight remains canonical', Number(profile.bodyweightKg) === 80)
    record(
      'nutrition preferences round-trip',
      profile.nutritionGoal === 'gain' &&
        profile.nutritionActivityLevel === 'active' &&
        profile.nutritionDiet === 'omnivore' &&
        profile.nutritionMealsPerDay === 4,
    )

    const avatar = await api('POST', '/v1/me/avatar', accounts.owner.token, { photoBase64: tinyPng })
    requireCheck('avatar upload', statusIs(avatar, 200), `status=${avatar.status}`)
    avatarUrl = avatar.body?.photoUrl
    requireCheck('avatar URL returned', typeof avatarUrl === 'string' && avatarUrl.startsWith('/uploads/'))

    const anonymousAvatar = await api('GET', avatarUrl)
    record('anonymous avatar access rejected', statusIs(anonymousAvatar, 401), `status=${anonymousAvatar.status}`)
    const ownerAvatar = await api('GET', avatarUrl, accounts.owner.token)
    record('owner avatar access', statusIs(ownerAvatar, 200), `status=${ownerAvatar.status}`)
    record(
      'private media cache headers',
      ownerAvatar.headers['cache-control']?.includes('no-store') &&
        ownerAvatar.headers.vary?.toLowerCase().includes('authorization') &&
        ownerAvatar.headers['x-content-type-options'] === 'nosniff',
    )
    const viewerAvatar = await api('GET', avatarUrl, accounts.viewer.token)
    record('private avatar hidden from non-friend', statusIs(viewerAvatar, 404), `status=${viewerAvatar.status}`)

    const discovery = await api(
      'GET',
      `/v1/friends/search?query=${encodeURIComponent(viewerUsername.slice(0, 8))}`,
      accounts.owner.token,
    )
    record(
      'opt-in friend discovery',
      statusIs(discovery, 200) &&
        Array.isArray(discovery.body?.data) &&
        discovery.body.data.some((entry) => entry.userId === accounts.viewer.id),
      `status=${discovery.status}`,
    )

    const exerciseList = await api('GET', '/v1/exercises?ranked=true&limit=500', accounts.owner.token)
    requireCheck('exercise catalogue', statusIs(exerciseList, 200), `status=${exerciseList.status}`)
    const exercises = Array.isArray(exerciseList.body?.data) ? exerciseList.body.data : []
    const exercise = exercises.find((item) => item.isRanked && item.rankModel === 'WEIGHTED')
    requireCheck('ranked weighted exercise available', Boolean(exercise?.id))

    const workoutCreate = await api('POST', '/v1/workouts', accounts.owner.token, {
      label: 'Production Smoke',
      timezone: 'Europe/London',
    })
    requireCheck('workout create', statusIs(workoutCreate, 201), `status=${workoutCreate.status}`)
    const workoutId = workoutCreate.body?.workout?.id
    requireCheck('workout id returned', Boolean(workoutId))

    const viewerWorkout = await api('GET', `/v1/workouts/${workoutId}`, accounts.viewer.token)
    record('workout ownership isolation', statusIs(viewerWorkout, 404), `status=${viewerWorkout.status}`)

    const addExercise = await api('POST', `/v1/workouts/${workoutId}/exercises`, accounts.owner.token, {
      exerciseId: exercise.id,
      restSecondsDefault: 120,
    })
    requireCheck('workout exercise add', statusIs(addExercise, 201), `status=${addExercise.status}`)
    const workoutExerciseId = addExercise.body?.workoutExercise?.id
    requireCheck('workout exercise id returned', Boolean(workoutExerciseId))

    const clientSetId = crypto.randomUUID()
    const setPayload = {
      weightKg: 50,
      reps: 5,
      rpe: 7.5,
      tag: 'WORK',
      isCompleted: true,
      clientSetId,
    }
    const addSet = await api(
      'POST',
      `/v1/workouts/${workoutId}/exercises/${workoutExerciseId}/sets`,
      accounts.owner.token,
      setPayload,
    )
    requireCheck('workout set add', statusIs(addSet, 201), `status=${addSet.status}`)
    const setId = addSet.body?.set?.id

    const retrySet = await api(
      'POST',
      `/v1/workouts/${workoutId}/exercises/${workoutExerciseId}/sets`,
      accounts.owner.token,
      setPayload,
    )
    record(
      'offline retry is idempotent',
      statusIs(retrySet, 200) && retrySet.body?.idempotent === true && retrySet.body?.set?.id === setId,
      `status=${retrySet.status}`,
    )

    const invalidSet = await api(
      'POST',
      `/v1/workouts/${workoutId}/exercises/${workoutExerciseId}/sets`,
      accounts.owner.token,
      { weightKg: 501, reps: 5 },
    )
    record('set validation rejects >500kg', statusIs(invalidSet, 400), `status=${invalidSet.status}`)

    const workoutRead = await api('GET', `/v1/workouts/${workoutId}`, accounts.owner.token)
    record(
      'workout read has one physical set',
      statusIs(workoutRead, 200) && workoutRead.body?.workout?.exercises?.[0]?.sets?.length === 1,
      `status=${workoutRead.status}`,
    )

    const complete = await api('POST', `/v1/workouts/${workoutId}/complete`, accounts.owner.token, {})
    requireCheck('workout complete', statusIs(complete, 200), `status=${complete.status}`)
    record('workout completed status', complete.body?.workout?.status === 'completed')
    const duplicateComplete = await api('POST', `/v1/workouts/${workoutId}/complete`, accounts.owner.token, {})
    record(
      'duplicate workout completion rejected',
      statusIs(duplicateComplete, 400) && duplicateComplete.body?.error === 'ALREADY_COMPLETED',
      `status=${duplicateComplete.status}`,
    )
    const workoutList = await api('GET', '/v1/workouts?limit=10', accounts.owner.token)
    record(
      'completed workout listed',
      statusIs(workoutList, 200) && workoutList.body?.data?.some((item) => item.id === workoutId),
      `status=${workoutList.status}`,
    )

    const rankMe = await api('GET', '/v1/ranks/me', accounts.owner.token)
    record(
      'rank generated on workout completion',
      statusIs(rankMe, 200) && rankMe.body?.ranks?.some((rank) => rank.exerciseId === exercise.id),
      `status=${rankMe.status}`,
    )
    const rankExercise = await api('GET', `/v1/ranks/exercises/${exercise.id}`, accounts.owner.token)
    record('exercise rank endpoint', statusIs(rankExercise, 200), `status=${rankExercise.status}`)
    const rankExplain = await api(
      'GET',
      `/v1/ranks/exercises/${exercise.id}/explain`,
      accounts.owner.token,
    )
    record(
      'rank explainability endpoint',
      statusIs(rankExplain, 200) && typeof rankExplain.body?.explanation === 'string',
      `status=${rankExplain.status}`,
    )
    const rankHistory = await api(
      'GET',
      `/v1/ranks/me/history?exerciseId=${exercise.id}`,
      accounts.owner.token,
    )
    record('rank history endpoint', statusIs(rankHistory, 200), `status=${rankHistory.status}`)
    const leaderboard = await api('GET', '/v1/ranks/leaderboard?limit=10', accounts.owner.token)
    record('leaderboard endpoint', statusIs(leaderboard, 200), `status=${leaderboard.status}`)

    const privatePost = await api('POST', '/v1/posts', accounts.owner.token, {
      workoutId,
      visibility: 'private',
      caption: 'Private production smoke workout',
      photoBase64: tinyPng,
    })
    requireCheck('private workout post create', statusIs(privatePost, 201), `status=${privatePost.status}`)
    const privatePostId = privatePost.body?.post?.id
    privatePostImageUrl = privatePost.body?.post?.imageUrl
    requireCheck('private post id and image returned', Boolean(privatePostId && privatePostImageUrl))

    const ownPrivatePost = await api('GET', `/v1/posts/${privatePostId}`, accounts.owner.token)
    record('owner reads private post', statusIs(ownPrivatePost, 200), `status=${ownPrivatePost.status}`)
    const deniedPrivatePost = await api('GET', `/v1/posts/${privatePostId}`, accounts.viewer.token)
    record('private post hidden as 404', statusIs(deniedPrivatePost, 404), `status=${deniedPrivatePost.status}`)
    const deniedLike = await api('POST', `/v1/posts/${privatePostId}/likes`, accounts.viewer.token)
    record('private post like denied as 404', statusIs(deniedLike, 404), `status=${deniedLike.status}`)
    const deniedComment = await api(
      'POST',
      `/v1/posts/${privatePostId}/comments`,
      accounts.viewer.token,
      { body: 'should not be accepted' },
    )
    record('private post comment denied as 404', statusIs(deniedComment, 404), `status=${deniedComment.status}`)

    const ownerPostImage = await api('GET', privatePostImageUrl, accounts.owner.token)
    record('owner reads private post media', statusIs(ownerPostImage, 200), `status=${ownerPostImage.status}`)
    const viewerPostImage = await api('GET', privatePostImageUrl, accounts.viewer.token)
    record('private post media hidden as 404', statusIs(viewerPostImage, 404), `status=${viewerPostImage.status}`)

    const editPost = await api('PATCH', `/v1/posts/${privatePostId}`, accounts.owner.token, {
      caption: 'Private production smoke workout edited',
    })
    record('post edit', statusIs(editPost, 200), `status=${editPost.status}`)

    const publicPost = await api('POST', '/v1/posts', accounts.owner.token, {
      visibility: 'public',
      caption: 'Public production smoke post',
    })
    requireCheck('public social post create', statusIs(publicPost, 201), `status=${publicPost.status}`)
    const publicPostId = publicPost.body?.post?.id
    const viewerPublic = await api('GET', `/v1/posts/${publicPostId}`, accounts.viewer.token)
    record('public post visible to authenticated user', statusIs(viewerPublic, 200), `status=${viewerPublic.status}`)
    const likeOn = await api('POST', `/v1/posts/${publicPostId}/likes`, accounts.viewer.token)
    const likeOff = await api('POST', `/v1/posts/${publicPostId}/likes`, accounts.viewer.token)
    record(
      'rapid like toggle remains consistent',
      likeOn.body?.liked === true && likeOff.body?.liked === false,
      `statuses=${likeOn.status}/${likeOff.status}`,
    )
    const comment = await api('POST', `/v1/posts/${publicPostId}/comments`, accounts.viewer.token, {
      body: 'Audit\u0000 comment',
    })
    record(
      'comment create and control-character sanitization',
      statusIs(comment, 201) && comment.body?.comment?.body === 'Audit comment',
      `status=${comment.status}`,
    )
    const comments = await api('GET', `/v1/posts/${publicPostId}/comments`, accounts.viewer.token)
    record(
      'comment list',
      statusIs(comments, 200) && comments.body?.data?.some((item) => item.id === comment.body?.comment?.id),
      `status=${comments.status}`,
    )

    const friendsPost = await api('POST', '/v1/posts', accounts.owner.token, {
      visibility: 'friends',
      caption: 'Friends production smoke post',
    })
    requireCheck('friends-only post create', statusIs(friendsPost, 201), `status=${friendsPost.status}`)
    const friendsPostId = friendsPost.body?.post?.id
    const beforeFriend = await api('GET', `/v1/posts/${friendsPostId}`, accounts.viewer.token)
    record('friends post hidden before acceptance', statusIs(beforeFriend, 404), `status=${beforeFriend.status}`)

    const friendRequest = await api('POST', '/v1/friends/requests', accounts.owner.token, {
      userId: accounts.viewer.id,
    })
    requireCheck('friend request create', statusIs(friendRequest, 201), `status=${friendRequest.status}`)
    const incoming = await api('GET', '/v1/friends/requests/incoming', accounts.viewer.token)
    record(
      'incoming friend request listed',
      statusIs(incoming, 200) && incoming.body?.data?.some((item) => item.userId === accounts.owner.id),
      `status=${incoming.status}`,
    )
    const acceptFriend = await api('POST', '/v1/friends/accept', accounts.viewer.token, {
      userId: accounts.owner.id,
    })
    requireCheck('friend request accept', statusIs(acceptFriend, 200), `status=${acceptFriend.status}`)
    const afterFriend = await api('GET', `/v1/posts/${friendsPostId}`, accounts.viewer.token)
    record('friends post visible after acceptance', statusIs(afterFriend, 200), `status=${afterFriend.status}`)
    const friendList = await api('GET', '/v1/friends', accounts.owner.token)
    record(
      'accepted friend listed',
      statusIs(friendList, 200) && friendList.body?.data?.some((item) => item.userId === accounts.viewer.id),
      `status=${friendList.status}`,
    )
    const friendAvatar = await api('GET', avatarUrl, accounts.viewer.token)
    record('private avatar remains hidden from friend', statusIs(friendAvatar, 404), `status=${friendAvatar.status}`)

    const feed = await api('GET', '/v1/posts/feed?limit=10', accounts.owner.token)
    record(
      'feed contains own posts',
      statusIs(feed, 200) && feed.body?.data?.some((item) => item.id === privatePostId),
      `status=${feed.status}`,
    )
    const gallery = await api('GET', '/v1/posts?mine=true&limit=10', accounts.owner.token)
    record(
      'profile post gallery',
      statusIs(gallery, 200) && gallery.body?.data?.some((item) => item.id === publicPostId),
      `status=${gallery.status}`,
    )

    const today = new Date().toISOString().slice(0, 10)
    const emptyNutrition = await api(
      'GET',
      `/v1/nutrition/day?date=${today}`,
      accounts.owner.token,
    )
    record('empty nutrition day state', statusIs(emptyNutrition, 200), `status=${emptyNutrition.status}`)
    const nutritionEntry = {
      id: crypto.randomUUID(),
      name: 'Audit oats',
      meal: 'breakfast',
      calories: 300,
      protein: 10,
      carbs: 50,
      fat: 6,
    }
    const nutritionPut = await api('PUT', '/v1/nutrition/day', accounts.owner.token, {
      date: today,
      entries: [nutritionEntry],
      waterMl: 1500,
      weightKg: 80.5,
    })
    requireCheck('nutrition day sync write', statusIs(nutritionPut, 200), `status=${nutritionPut.status}`)
    const nutritionGet = await api(
      'GET',
      `/v1/nutrition/day?date=${today}`,
      accounts.owner.token,
    )
    record(
      'nutrition day sync round-trip',
      statusIs(nutritionGet, 200) &&
        nutritionGet.body?.waterMl === 1500 &&
        Number(nutritionGet.body?.weightKg) === 80.5 &&
        nutritionGet.body?.entries?.length === 1,
      `status=${nutritionGet.status}`,
    )
    const nutritionDays = await api(
      'GET',
      `/v1/nutrition/days?from=${today}&to=${today}`,
      accounts.owner.token,
    )
    record(
      'nutrition range sync',
      statusIs(nutritionDays, 200) && nutritionDays.body?.data?.length === 1,
      `status=${nutritionDays.status}`,
    )

    const nutritionPlan = await api(
      'POST',
      '/v1/nutrition/plan/generate-weekly',
      accounts.owner.token,
      { tzOffset: 0, force: false },
      { timeoutMs: 90_000 },
    )
    record(
      'weekly nutrition plan generation',
      statusIs(nutritionPlan, 200) && nutritionPlan.body?.plan?.length === 7,
      `status=${nutritionPlan.status} error=${nutritionPlan.body?.error ?? 'none'}`,
    )
    if (statusIs(nutritionPlan, 200)) {
      const weekStart = nutritionPlan.body?.weekStart
      const week = await api(
        'GET',
        `/v1/nutrition/plan/week?weekStart=${encodeURIComponent(weekStart)}`,
        accounts.owner.token,
      )
      record(
        'weekly nutrition plan read',
        statusIs(week, 200) && week.body?.plan?.length === 7,
        `status=${week.status}`,
      )
    }

    const smokeEndpoints = [
      ['stats overview', '/v1/me/stats'],
      ['training profile', '/v1/me/training-profile'],
      ['achievements', '/v1/achievements/me'],
      ['notifications', '/v1/notifications'],
      ['routines', '/v1/routines'],
      ['program templates', '/v1/programs/templates'],
      ['challenge feed', '/v1/challenges/feed'],
      ['activity feed', '/v1/activities/feed'],
      ['story feed', '/v1/stories/feed'],
    ]
    for (const [name, path] of smokeEndpoints) {
      const response = await api('GET', path, accounts.owner.token)
      record(`${name} endpoint`, statusIs(response, 200), `status=${response.status}`)
    }

    const notifications = await api('GET', '/v1/notifications/unread-count', accounts.owner.token)
    record('notification unread count', statusIs(notifications, 200), `status=${notifications.status}`)

    const exportData = await api('GET', '/v1/me/export-data', accounts.owner.token)
    record('GDPR export endpoint', statusIs(exportData, 200), `status=${exportData.status}`)
    const exportText = JSON.stringify(exportData.body ?? {}).toLowerCase()
    record(
      'GDPR export excludes credentials',
      !exportText.includes('passwordhash') &&
        !exportText.includes('refreshtoken') &&
      !exportText.includes('tokenhash'),
    )

    const deleteConvertedGuest = await api('DELETE', '/v1/me/account', accounts.guest.token, {
      confirm: 'DELETE',
    })
    requireCheck(
      'converted guest hard deletion',
      statusIs(deleteConvertedGuest, 204),
      `status=${deleteConvertedGuest.status}`,
    )
    accounts.guest.deleted = true
    const convertedGuestAfterDelete = await api('GET', '/v1/me', accounts.guest.token)
    record(
      'deleted converted guest token revoked',
      statusIs(convertedGuestAfterDelete, 401),
      `status=${convertedGuestAfterDelete.status}`,
    )

    const deleteOwner = await api('DELETE', '/v1/me/account', accounts.owner.token, {
      confirm: 'DELETE',
    })
    requireCheck('owner hard deletion', statusIs(deleteOwner, 204), `status=${deleteOwner.status}`)
    accounts.owner.deleted = true
    const ownerAfterDelete = await api('GET', '/v1/me', accounts.owner.token)
    record(
      'deleted owner access token revoked',
      statusIs(ownerAfterDelete, 401),
      `status=${ownerAfterDelete.status}`,
    )
    const ownerRefreshAfterDelete = await api('POST', '/v1/auth/refresh', null, {
      refreshToken: accounts.owner.refreshToken,
    })
    record(
      'deleted owner refresh token revoked',
      statusIs(ownerRefreshAfterDelete, 401),
      `status=${ownerRefreshAfterDelete.status}`,
    )
    const avatarAfterDelete = await api('GET', avatarUrl, accounts.viewer.token)
    record('deleted owner avatar is inaccessible', statusIs(avatarAfterDelete, 404), `status=${avatarAfterDelete.status}`)
    const postImageAfterDelete = await api('GET', privatePostImageUrl, accounts.viewer.token)
    record(
      'deleted owner post media is inaccessible',
      statusIs(postImageAfterDelete, 404),
      `status=${postImageAfterDelete.status}`,
    )

    const deleteViewer = await api('DELETE', '/v1/me/account', accounts.viewer.token, {
      confirm: 'DELETE',
    })
    requireCheck('viewer hard deletion', statusIs(deleteViewer, 204), `status=${deleteViewer.status}`)
    accounts.viewer.deleted = true
    const viewerAfterDelete = await api('GET', '/v1/me', accounts.viewer.token)
    record(
      'deleted viewer access token revoked',
      statusIs(viewerAfterDelete, 401),
      `status=${viewerAfterDelete.status}`,
    )
  } catch (error) {
    record('smoke test completed without fatal dependency failure', false, error.message)
  } finally {
    await deleteAccount(accounts.owner)
    await deleteAccount(accounts.viewer)
    await deleteAccount(accounts.guest)
  }

  const failures = checks.filter((check) => !check.ok)
  console.log(
    JSON.stringify(
      {
        baseUrl,
        total: checks.length,
        passed: checks.length - failures.length,
        failed: failures.length,
        failures: failures.map(({ name, detail }) => ({ name, detail: detail ?? '' })),
        cleanup: {
          ownerDeleted: accounts.owner.deleted,
          viewerDeleted: accounts.viewer.deleted,
          guestDeleted: accounts.guest.deleted,
        },
      },
      null,
      2,
    ),
  )
  if (failures.length > 0) process.exitCode = 1
}

await main()
