# ZVELT — TO-DO LIST (Updated)

> Auto-synced with codebase state after debugging review (April 2026).
> Status: Done | Partial | Todo | V2 | Bug
> Filter by Status / Priority / Owner. Dependencies = what must be done first.

---

## 🔐 Auth & Onboarding

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 1 | Email/password auth | Signup, login, logout, JWT + refresh auto | **Done** | P0 | — | V1 | — | bcrypt password hashing (fixed from SHA-256) |
| 2 | Google Sign-In | OAuth flow + token storage | **Done** | P0 | — | V1 | — | |
| 3 | Onboarding flow | Start → concept → avatar intro → select → confirm | **Done** | P0 | — | V1 | Auth | |
| 4 | Avatar system upgrade | Design simpler, Apple-style, more options | **Done** | P1 | — | V1 | Onboarding flow | avatar_flow + 4 screens implemented |

---

## 👤 Profile

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 5 | getMe complet | GET /v1/me — all profile data | **Done** | P0 | — | V1 | Auth | |
| 6 | Update profil | PATCH /v1/me/profile — bodweightKg bug | **Partial** | P0 | 0.5z | V1 | getMe complet | Typo `bodweightKg` still in schema (TODO added). Profile update works. |
| 7 | Stats view in profil | XP, rank, streak, workout count, weight | **Done** | P1 | — | V1 | Update profil · Rank · Streak | skeleton_profile_tab (30KB), achievements_screen |
| 8 | Setari cont | Notifications, privacy, units, logout | **Done** | P2 | — | V1 | getMe complet | account_settings_screen.dart (10KB) |

---

## 🏋 Workouts

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 9 | Lista workouts trecute | GET /v1/workouts — functional | **Done** | P0 | — | V1 | Auth | |
| 10 | Start + track workout | POST, tracker screen, complete + XP | **Done** | P0 | — | V1 | Workouts · Exercise lib | workout_tracker_screen (18.7KB), xp_complete_screen |
| 11 | Workout suggestion AI | Suggestion from profile + create from suggestion | **Done** | P1 | — | V1 | Profile · Exercise lib | workout-generator.service + AI trainer endpoint |
| 12 | Exercise library | Exercise list + filters + custom | **Done** | P0 | — | V1 | Auth | |
| 13 | Muscle map upgrade | Heatmap front+back, interactive | **Partial** | P1 | 2z | V1 | Start + track workout | muscle_recovery_service (9.3KB) exists; needs visual heatmap upgrade |
| 14 | Streak gym | Backend exists, UI streak visible | **Partial** | P1 | 0.5z | V1 | Start + track workout · Stats | streak.service.ts done; UI partially in profile |
| 15 | Streak cardio | Separate streak for run/bike/swim | Todo | P2 | 1z | V1 | Log manual cardio · Streak gym | |

---

## 📅 Calendar & Activities

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 16 | Backend history endpoint | GET /v1/activities?month= | **Done** | P1 | — | V1 | Start + track workout | activities.ts + activities_service.dart |
| 17 | Iconite activitate | Gym, run, bike, swim — consistent icons | Todo | P1 | 0.5z | V1 | Logo final | |
| 18 | Activity calendar | Monthly calendar with mini icons per type | **Done** | P1 | — | V1 | Backend history · Icons | activity_calendar_screen.dart (24KB!) |
| 19 | Log manual cardio | Log run/bike/swim without GPS | **Partial** | P2 | 1z | V1 | Activity calendar | outdoor_track_screen + planned_workout infrastructure |

---

## 🗺 GPS Maps & Tracking

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 20 | GPS tracking in-app | flutter_map + geolocator — real-time route | **Done** | P1 | — | V1 | Log manual cardio · Calendar | outdoor_track_screen.dart (10.5KB), flutter_map + geolocator in pubspec |
| 21 | Statistici activitate | Distance, time, avg speed, calories, altitude | **Partial** | P1 | 1z | V1 | GPS tracking | Basic stats in outdoor screen; needs detailed view |
| 22 | Temperature API | Weather API (OpenWeather) for current temp | **Done** | P2 | — | V1 | — | weather.ts + weather_service.dart implemented |
| 23 | Social overlay card | Postable card: track + icon + distance + temp | **Partial** | P1 | 1z | V1 | GPS · Stats · Weather | Post-workout screen exists; overlay card needs polish |
| 24 | Heart rate on overlay | HR from wearable or manual on card | Todo | P2 | 1z | V1 | Social overlay · HR sync | |
| 25 | Export card as image | Screenshot widget + share as photo | Todo | P1 | 1z | V1 | Social overlay card | |

---

## 🤖 AI Chat (DeepSeek)

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 26 | Integrare DeepSeek API | Backend endpoint /v1/ai/chat with char limit | **Done** | P1 | — | V1 | Auth · Backend | 3 endpoints: /chat, /onboarding-interpret, /trainer. Rate limited (6-10/min). Prompt injection sanitized. |
| 27 | Caching raspunsuri | Redis/DB cache — same answer for similar questions | Todo | P1 | 2z | V1 | DeepSeek API | |
| 28 | Tips nutritie | Personalized answers based on profile + macros | **Done** | P1 | — | V1 | DeepSeek · Nutrition | AI trainer has access to nutrition profile |
| 29 | Tips exercitii | Exercise suggestions, form, alternatives | **Done** | P1 | — | V1 | DeepSeek · Exercise lib | AI trainer generates workout suggestions |
| 30 | Tips accidentari | Advice for common injury recovery | **Partial** | P2 | 0.5z | V1 | DeepSeek | AI can answer; no dedicated injury UI |
| 31 | UI Chat screen | Simple chat screen, max 300 chars | **Done** | P1 | — | V1 | DeepSeek · Caching | ai_chat_screen.dart (7.3KB) |
| 32 | AI Stress assistant | Stress management based on sleep + activity | V2 | P3 | 4z | V2 | Sleep tracking · Chat UI | |

---

## 🌐 Social

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 33 | Social feed UI | Posts list, likes, comments connected to backend | **Done** | P0 | — | V1 | Auth · Create post | skeleton_social_tab + social_feed_service + post_detail_screen |
| 34 | Create post flow | Photo pick + workout attach + submit | **Done** | P0 | — | V1 | Social feed UI | social_feed_service.createPost with photo + workout |
| 35 | Friends screen | Search, add, remove friends | **Done** | P1 | — | V1 | Auth | friends_screen.dart (18.9KB!) + friends_service.dart |
| 36 | Comentarii in-app | Full comment screen with reply + like | **Done** | P1 | — | V1 | Social feed UI | post_detail_screen.dart (11.3KB) + comments API |
| 37 | Notificari push | Like, comment, friend request — notifications | **Done** | P0 | — | V1 | Social · Friends | push_messaging_service + FCM + notifications_screen (9.5KB) + DM notifications |
| 38 | Share pe Instagram | Share overlay card or post as Story/Feed | Todo | P2 | 2z | V1 | Export card as image | |
| 39 | Share pe Facebook | Share on Facebook | Todo | P3 | 1z | V1 | Export card as image | |
| — | DM Messaging | Direct messages 1:1 between friends | **Done** | P1 | — | V1 | Friends | conversations_screen + direct_chat_screen + messages_service (not in original list!) |

---

## 🏆 Rank & Medals

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 40 | Overall rank + leaderboard | Score, tier, season leaderboard | **Done** | P0 | — | V1 | Start + track workout | ranking.service.ts + skeleton_ranks_tab (25.8KB) |
| 41 | Rank per exercitiu | Specific rank per exercise | **Done** | P1 | — | V1 | Overall rank | UserExerciseRank model + ranks.ts |
| 42 | Achievements system | Badges on workout complete | **Partial** | P1 | 0.5z | V1 | Start + track workout | Backend done (achievement.service.ts); UI: achievements_screen.dart exists |
| 43 | Rank per grupa musculara | Chest/legs/back rank | Todo | P1 | 3z | V1 | Muscle map · Rank per exercise | |
| 44 | Medalii per grupa | Visual badges per group in profile | Todo | P1 | 2z | V1 | Rank per grupa | |
| 45 | Explainability rank | "Why this score" + next tier estimate | Todo | P2 | 1z | V1 | Overall rank · Rank per exercise | |

---

## 📊 Charts & Analytics

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 46 | Weekly effort chart | Volume + sets + reps per week — fl_chart | **Done** | P1 | — | V1 | Workouts list | weekly_effort_screen.dart + stats_charts_service + fl_chart in pubspec |
| 47 | Monthly progress chart | Monthly progress per main exercise | **Partial** | P1 | 1z | V1 | Weekly effort | analytics_hub_screen.dart (33.5KB) has various charts |
| 48 | Ranking history chart | Rank evolution over time | Todo | P2 | 1z | V1 | Overall rank | |
| 49 | Body weight chart | Body weight evolution graph | **Partial** | P2 | 0.5z | V1 | Update profil | Nutrition service tracks weight; needs dedicated chart UI |
| 50 | Yearly overview | Full year: activity, volume, streaks | Todo | P2 | 2z | V1 | Calendar · Weekly effort | |

---

## 🥗 Nutrition

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 51 | Nutritie backend | POST/GET/PUT /v1/nutrition/* | **Done** | P1 | — | V1 | Auth · DB schema | Full CRUD: day log, weekly plan, batch sync. nutrition.ts (9.3KB) |
| 52 | Food search SQLite | Search foods from local foods.db | **Done** | P1 | — | V1 | Nutritie backend | nutrition_service.dart — SQL injection FIXED, sort in Dart |
| 53 | Log masa zilnica | Add food + quantity + meal (B/L/D) | **Done** | P1 | — | V1 | Food search · Backend | nutrition_tab.dart (42.3KB!) — full meal logging |
| 54 | Macro tracking zilnic | Display calories + P/C/F per day with chart | **Done** | P1 | — | V1 | Log masa · Macros | nutrition_tab has goals, progress rings, charts |
| 55 | Nutritie UI end-to-end | Complete functional screen, connected to backend | **Done** | P1 | — | V1 | All nutrition | 42KB nutrition tab + server sync + offline support |

---

## 💤 Sleep & Wellness

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 56 | Sleep tracking | Health API iOS + HealthConnect Android | **Partial** | P2 | 1z | V1 | health package | health_service.dart reads SLEEP_SESSION; health_screen.dart (24.9KB) shows sleep |
| 57 | Sleep dashboard | Sleep hours, quality, weekly chart | **Partial** | P2 | 1z | V1 | Sleep tracking | health_screen shows sleep; needs dedicated sleep tab |
| 58 | Motivation quotes | Quote adapted to sleep + activity patterns | Todo | P2 | 2z | V1 | Sleep · Calendar | |

---

## ⌚ Wearables

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 59 | Heart rate sync | Read HR from wearable in real-time during workout | **Partial** | P2 | 1z | V1 | Workout · health pkg | health_service reads HEART_RATE + RESTING_HEART_RATE + BLOOD_OXYGEN |
| 60 | Apple Watch UI | Complication or mini Watch app | Todo | P2 | 5z | V1 | HR sync · Workouts | |
| 61 | Garmin/Polar/WearOS | Compatibility via Health APIs | V2 | P3 | 4z | V2 | Watch UI · HR sync | |

---

## 🎨 Branding & UI/UX

| # | Task | Description | Status | Prio | Effort | Ver | Dependencies | Notes |
|---|------|-------------|--------|------|--------|-----|-------------|-------|
| 62 | Logo final | Zvelt logo, vectorial, light + dark | Todo | P0 | design | V1 | — | |
| 63 | Mascota BeastRise | Simple, motivational mascot | Todo | P1 | design | V1 | Logo final | |
| 64 | Avatare Apple-style | Simple, clean, customizable avatars | **Done** | P1 | — | V1 | Logo final | avatar_selection_screen (4KB) with multiple options |
| 65 | Dark theme consistent | Orange #FC4C02 accent, dark bg | **Done** | P0 | — | V1 | Logo final | AppTheme with bgPrimary, accentBlue, Inter + SpaceGrotesk fonts |
| 66 | Micro-animatii | Transitions, loading states, visual feedback | Todo | P1 | 3z | V1 | Social · Nutrition · Profile | |
| 67 | Onboarding redesign | More attractive, modern, mascot integrated | Todo | P2 | 2z | V1 | Mascot · Avatar upgrade | |
| 68 | App Store assets | Screenshots, preview video, description | Todo | P0 | 2z | V1 | Dark theme · Animations · App functional | |
| 69 | Google Play assets | Assets adapted for Play Store | Todo | P0 | 1z | V1 | App Store assets | |

---

## 🐛 Bugs Fixed (from debugging session)

| # | Issue | Severity | Status | File(s) |
|---|-------|----------|--------|---------|
| B1 | SQL injection in food search | CRITICAL | **Fixed** | nutrition_service.dart |
| B2 | SHA-256 password hashing (too weak) | CRITICAL | **Fixed** | auth.ts (now bcrypt) |
| B3 | Auth middleware missing return after 401 | CRITICAL | **Fixed** | middleware/auth.ts |
| B4 | No HTTP timeouts on services | HIGH | **Fixed** | 13 service files + http_client.dart |
| B5 | 30 sequential HTTP requests for nutrition history | HIGH | **Fixed** | nutrition_service.dart (batch sync) |
| B6 | 14 sequential Health Connect calls | HIGH | **Fixed** | health_service.dart (Future.wait) |
| B7 | hasValidToken() trusts revoked refresh tokens | HIGH | **Fixed** | auth_service.dart |
| B8 | AI prompt injection vulnerability | HIGH | **Fixed** | ai.ts (sanitizePromptInput) |
| B9 | Plank bodyweight:false in XP system | MEDIUM | **Fixed** | gym-xp.service.ts |
| B10 | Planned workout UTC vs local time mismatch | MEDIUM | **Fixed** | workouts.ts (ymdLocal) |
| B11 | Double 16ms delay hack | MEDIUM | **Fixed** | main.dart (SchedulerBinding.endOfFrame) |
| B12 | No rate limiting on AI endpoints | MEDIUM | **Fixed** | ai.ts (6-10 req/min) |
| B13 | Unnecessary workout generation in AI trainer | LOW | **Fixed** | ai.ts (conditional) |
| B14 | MainScreen pageCache not disposed | LOW | **Fixed** | main_screen.dart |
| B15 | iOS Firebase config empty | LOW | TODO | firebase_options.dart |
| B16 | bodweightKg typo in schema | LOW | TODO | schema.prisma |

---

## ⚠️ Migration Required

| Issue | Action Required |
|-------|----------------|
| bcrypt password migration | Existing users with SHA-256 hashes cannot log in. Need migration script or dual-verify fallback. |
| bodweightKg → bodyweightKg | Prisma migration + update all TS/Dart references. DB column is already correct. |
| iOS Firebase credentials | Run `flutterfire configure` for iOS target to enable push notifications. |

---

## Summary

| Category | Done | Partial | Todo | V2 | Bugs Fixed |
|----------|------|---------|------|-----|------------|
| Auth & Onboarding | 4 | 0 | 0 | 0 | — |
| Profile | 3 | 1 | 0 | 0 | — |
| Workouts | 4 | 2 | 1 | 0 | — |
| Calendar & Activities | 2 | 1 | 1 | 0 | — |
| GPS Maps | 2 | 2 | 2 | 0 | — |
| AI Chat | 5 | 1 | 1 | 1 | — |
| Social | 6 | 0 | 2 | 0 | — |
| Rank & Medals | 2 | 1 | 3 | 0 | — |
| Charts & Analytics | 1 | 2 | 2 | 0 | — |
| Nutrition | 5 | 0 | 0 | 0 | — |
| Sleep & Wellness | 0 | 2 | 1 | 0 | — |
| Wearables | 0 | 1 | 1 | 1 | — |
| Branding | 2 | 0 | 6 | 0 | — |
| **TOTAL** | **36** | **13** | **20** | **2** | **16** |
