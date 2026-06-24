# Zvelt — Screen Tree (cards · buttons · where each leads)

Working doc for design-parity. One screen per section; each interactive element
lists its destination. We compare against the design in segments (5–10 at a time).
Design source (newest): `C:\Users\cipri_g7\Desktop\zvelt-claude-code\` (screens-train, etc.).

Legend: 🔘 button/tap → destination · 🪧 display-only · ⚙️ inline action (no nav) · ❓ conditional

---

## TRAIN tab — `SkeletonHomeTab` (`app/lib/screens/skeleton/skeleton_home_tab.dart`)

### Header (`_HomeHeader`) — always visible
- 🔘 Avatar (initials + green dot) → **Profile** (`SkeletonProfileTab`)
- 🪧 Greeting + date
- 🔘 Refresh icon → reloads data (in place)
- 🔘 Bell icon → **NotificationsScreen**
- 🔘 Gear icon → **SettingsScreen**

### Body (scrollable), top → bottom
1. **Workout mode boxes** (`_WorkoutModeBoxes`)
   - 🔘 "AI Workout" → **AI Workout sheet** (`_AiWorkoutSheet`, modal) → 🔘 "Start this workout" → **WorkoutTrackerScreen**
   - 🔘 "Custom Workout" → creates workout → **WorkoutTrackerScreen**
2. 🔘 **"Set a new goal"** (`_SetGoalButton`) → **GoalEvolutionFlow**
3. ❓ **Retention banner** (`_RetentionBanner`) — shows when streak-at-risk or inactive → 🔘 CTA → start workout
4. **Today's body** (`TodaysBodyCard`) — always visible
   - 🔘 "Details" → **MetricDetailScreen(recovery)**
   - 🔘 Strain ring → **MetricDetailScreen(strain)**
   - 🔘 Recovery ring → **MetricDetailScreen(recovery)**
   - 🔘 Sleep ring → **MetricDetailScreen(sleep)**
   - 🪧 Coach footer line
5. ❓ **Vitals row** (`ZVitalsRow`) — only if wearable connected
   - 🔘 Resting HR → **MetricDetailScreen(recovery)**
   - 🔘 Steps → **TrainingMetricDetailScreen(steps)**
   - 🔘 Sleep → **MetricDetailScreen(sleep)**
   - 🔘 HRV → **MetricDetailScreen(recovery)**
   - ❓ else (not connected): 🔘 "Connect a wearable" card → **HealthScreen**
6. 🔘 **Activity heatmap** (8 weeks, `ZCard`) → **ActivityCalendarScreen**
7. 🪧 **Weekly progress** (`ZWeeklyProgressCard`) — M–S bars + count, display-only
8. **Performance trend** (`ZPerformanceTrend`) — volume chart
   - ⚙️ "30D / 3M / 1Y" scope button → cycles scope in place
9. 🪧 **Daily focus** (`_MotivationCard`) — quote, display-only
10. **Daily reminder** (`_DailyReminderCard`)
    - ⚙️ Toggle switch → enable/disable reminder
    - ⚙️ "Time: HH:MM" → time picker
11. 🪧 **Streak card** (`_StreakCard`) — display-only
12. 🪧 **Workouts card** (`_WorkoutsCard`) — display-only
13. ❓🪧 **Game XP bar** (`GameXpBarCard`) — shows when gameXp present, display-only
14. 🔘 **Coach tip** (`_CoachTipCard`) → **GoalAdviceOverlay**
15. 🔘 **Activity calendar** row (`_ActivityCalendarCard`) → **ActivityCalendarScreen**
16. 🔘 **Track a run** (`_OutdoorTrackCard`, blue GPS hero) → **OutdoorTrackScreen**
17. **Character stats** (`CharacterStatsCard`)
    - 🔘 5 rings STR/AGI/VIT/INT/PER → stat explainer bottom sheet
    - 🔘 (STR sheet) "View strength progression" → **TrainingMetricDetailScreen(strength)**
    - 🪧 Overall bar
18. ❓🔘 **Last workout** (`_LastWorkoutCard`) — when a workout exists → **workout summary sheet** (`_LastWorkoutSheet`)
19. 🔘 **Steps card** (`_StepsCard`) → **HealthScreen**

### Bottom nav (`ZveltMainNavBar`, persistent on all 4 tabs)
- 🔘 Train (current) · 🔘 Progress → **ProgressHubScreen** · 🔘 center ▶ → **QuickLaunchSheet** · 🔘 Feed → **SocialPlusScreen** · 🔘 Nutrition → **NutritionTab**

### Screens reachable FROM Train (each its own future sub-tree)
AI Workout sheet · WorkoutTrackerScreen · GoalEvolutionFlow · MetricDetailScreen · TrainingMetricDetailScreen · HealthScreen · ActivityCalendarScreen · OutdoorTrackScreen · GoalAdviceOverlay · Last-workout summary sheet · NotificationsScreen · SettingsScreen · Profile · QuickLaunchSheet

---

## TRAIN — parity vs design (`screens-train.jsx`)

### Aligned (present in both, same intent)
- Header: avatar→Profile, bell→Notifications, gear→Settings (app adds a Refresh icon — extra)
- Today's body rings (Strain/Recovery/Sleep) + Details→recovery
- Activity heatmap (8 weeks) → Calendar
- Performance trend with 30D/3M/1Y toggle
- Weekly progress (M–S bars)
- Daily reminder (time + toggle)
- Outdoor "Track a run" → Outdoor
- Character stats rings → metric detail
- Last workout → summary
- Daily focus / motivation quote

### Different (exists in both but diverges)
- **Vitals row metrics**: design = Heart Rate / Steps / Calories / Stress · app = Resting HR / Steps / Sleep / HRV. Only Steps overlaps. (app = recovery-focused; design = activity-focused)
- **Performance trend metric**: design = "Training Load" (ms/min) · app = "Volume" (kg)
- **Character stats taxonomy**: design = STR/END/MOB/PWR (4) · app = STR/AGI/VIT/INT/PER (5)
- **Weekly progress**: design has a period-cycle toggle · app is display-only

### Design-only — in design, absent on app's Train
- **Quick Start CTA** "Today · 6 lifts · 48 min" (programmed day → tracker) — app uses AI/Custom boxes instead
- **AI Suggestion card** "Coach Zvelt" mid-screen → tracker:ai — app's AI is the top "AI Workout" box
- **Hall of Fame / XP tier card** (tappable → leaderboard) — app has a NON-tappable XP bar; Hall of Fame lives on Progress
- **Muscle Map** "Worked this week" (anatomical heatmap) — absent on app Train
- Likely-intentional honest omissions (no data source): **Stress**, live **Heart Rate**, **Calories** in vitals

### App-only — extras not in design (keep, per "restyle don't remove")
- "Set a new goal" button · Retention banner (conditional) · Coach tip → GoalAdviceOverlay
- Separate "Activity calendar" row → Calendar (REDUNDANT — heatmap already taps to Calendar)
- Streak card + Workouts card (design folds these into the heatmap header)
- Steps card at bottom → Health (design puts steps in vitals row)

### Order
- Design: Header → Rings → Vitals → Activity → Trend → QuickStart → Weekly → AISuggestion → Reminder → Outdoor → HallOfFame → CharStats → MuscleMap → LastWorkout → Motivation
- App: Header → AI/Custom → SetGoal → [retention] → Rings → Vitals → Heatmap → Weekly → Trend → Motivation → Reminder → Streak → Workouts → [XP] → CoachTip → Calendar → Outdoor → CharStats → LastWorkout → Steps
- Notable: app places Motivation high (after Trend); design places it LAST.

### Bottom nav
- App: Train · Progress · ▶ QuickLaunch · Feed · Nutrition
- Design (agent-inferred, low confidence — not from app.jsx): Train · Progress · Coach · Social · Profile

---

## PROGRESS tab — `ProgressHubScreen` (`app/lib/screens/analytics/progress_hub_screen.dart`)

### Header + top
- 🪧 Title "Analytics" · 🔘 Bell → **NotificationsScreen**
- 🔘 **Strength** card → **StrengthAnalyticsScreen**
- 🔘 **Hall of Fame** card (LP total from getRankLp) → **HallOfFameScreen**
- Sub-tab selector (inline state, no nav): **Training · Nutrition · Health · Body · Biology**

### Training sub-tab
- 🪧 Weekly Coach read (AI, `fetchWeeklyCoachRead`)
- ⚙️ Performance trend "Training load · 30d"
- 🔘 Sessions / Active-days row → metric:consistency
- 🔘 Metric navigator rows: Weekly volume→volume · Strength progression→strength · Top exercises→exercises · Consistency→consistency (→ **TrainingMetricDetailScreen**)
- 🔘 Daily Volume bar → metric:volume
- 🔘 Photo Progress → **PhotoProgressScreen**

### Nutrition sub-tab
- 🪧 Weekly calories bar · Macros rings (Today) · Hydration cups · Recent meals · Consistency score

### Health sub-tab (gated on wearable; else 🔘 Connect → HealthScreen)
- 🔘 Active Calories → metric:calories · 🔘 Steps (7d bars) → metric:steps · 🪧 Sleep+RHR row · 🪧 Body Weight

### Body sub-tab
- ⚙️ Period picker 1W/1M/3M/1Y · 🪧 Body composition · 🪧 Muscle Recovery Map · 🪧 Weight area chart · 🔘 Measurements "+Log" (sheet) · 🔘 Visual Evidence "+Add photo" → PhotoProgress

### Biology sub-tab (gated; else Connect)
- 🪧 Source status · VO₂ max · SpO₂+HRV row · Sleep stages

---

## PROGRESS — parity vs design (`screens-progress.jsx`)

### Aligned
- Header + Strength/Hall-of-Fame cards + the 5 sub-tabs (same names/order)
- Nutrition: macro ring, weekly calories, hydration, recent meals
- Body: body composition, weight trend (period toggle), measurements list
- Biology: VO₂ max, SpO₂+HRV
- Training metric destinations (volume/strength/exercises/consistency)

### 🐛 Likely real issues (worth fixing)
- **Nutrition tab has a stray "Strength Progression" CTA card that does nothing** (non-interactive, wrong tab — looks like a copy-paste leftover)
- **Training tab renders Sessions + Active-days TWICE** (one tappable row + one non-tappable row) — redundant

### Different (diverges from design)
- **Training richness**: design shows inline charts per metric (Weekly Volume 12-bar, Strength sparkline, Top Exercises list, Consistency 365d heatmap) · app uses compact navigator ROWS + a 7-day daily-volume bar + a Coach read (design puts coach on a separate screen)
- **Health vitals split**: design Health = HRV sparkline + Sleep-stages hypnogram + RHR + Recovery score + Steps&Calories · app Health = Calories/Steps/Sleep/RHR/Weight, and puts HRV + sleep-stages under **Biology** instead

### Design-only — honest omissions (no data source — LEAVE)
- **Rest Time Trend** (Training) · **Body Battery** + **ECG** (Biology) · sleep **hypnogram** with fabricated stages
- Design VO₂/HRV/etc. use demo sparklines + fake deltas ("Fitness age 24") — app shows real values or honest empty

### App-only extras (keep)
- Coach read on Training · Nutrition consistency-score · Muscle Recovery Map + Visual Evidence in Body · Biology source-status card

### Caching applied (this pass)
- All StatsChartsService reads now cache-first (weekly-effort, weekly-sessions, top-exercises, rank-lp, recent-prs, cumulative-volume — daily-training already done) — powers hub header + detail screens instantly, no re-request within 2h TTL
- Weekly coach read cached client-side (6h TTL)
- Nutrition (SharedPrefs+sync), Health/Biology (OS local DB), Body measurements (local) — already cached, untouched

---

## FEED tab — `SocialPlusScreen` (`app/lib/screens/social/social_plus_screen.dart`)

### Tree (top → bottom)
- Header: "FEED" + "Your tribe · N trained today" · 🔘 camera → **GalleryScreen** · 🔘 circle → **CircleScreen**
- Story rail: 🔘 "You" (add) → **CreateStorySheet** · 🔘 bubbles → **StoryViewer** (5s autoadvance, tap zones, long-press pause, swipe-dismiss, delete-own, reply→DM, heart-like)
- 🔘 Race-of-the-week hero → **RaceHub** · 🔘 "Join the race" → join + RaceHub (empty-state fallback when no races)
- ⚙️ Trending/Friends toggle · ⚙️ All/Following/Popular pills · 🔘 Races pill → RaceHub
- Active challenges + 🔘 "+ NEW" → **CreateChallengeSheet** · cards → RaceHub
- Community feed header + 🔘 "+ POST" → **PostWorkoutScreen**
- Feed posts (`SocialFeedPostCard`): ⚙️ like (optimistic) · 🔘 comment → **CommentsSheet** · ⚙️ share (copy zvelt:// link) · ⚙️ bookmark · 🔘 menu (edit/delete/hide/report/block) · 🔘 author → **UserProfileScreen** · image (in-place)
- Infinite scroll + pull-to-refresh

### Parity vs design (`screens-social.jsx`) — already very close
- **Aligned:** header icons, story rail, race hero + participant avatars, Trending/Friends + filter chips, active challenges, post-card actions (like/comment/share/bookmark/menu/author), comments sheet, story viewer, post menu, report-user sheet, user profile, gallery, circle, friends, DM/conversations, bookmarks, blocked-users. (Feed had multiple prior parity rounds — it's the most complete tab.)
- **Gaps, but backend-data-gated (intentional, leave):**
  - Story **"LIVE" badge** — needs an `isLive` flag on stories (on the backend TODO list)
  - Per-comment **Like / Reply / Report** — design has them; needs comment-likes backend
- ✅ **Create Story** now has the 4 design presets (Last PR / Workout / Photo / Quote). PR/Workout/Quote are composed client-side into a gradient story image from real data and published as a normal image story (no backend change).

### Caching judgment — NO changes (by design)
- Live content (feed posts, friend activity, participants, likes/comments) stays **online** — caching a social feed = stale UX. Correct as-is.
- Already persisted where it should be: **stories** (SQLCipher DB + disk, 24h GC), **challenges** (SharedPreferences fallback), **blocked IDs** (session cache), images (Flutter image cache).
- Verdict: unlike Train/Progress (read-mostly "numbers"), Feed has nothing to cache without hurting freshness.
