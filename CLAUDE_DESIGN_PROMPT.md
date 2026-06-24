# ZVELT — Design System & App Specification

> **Brief for Claude Design.** Continue the visual design of an existing Flutter cross-platform mobile app (iOS + Android) that's currently in late-stage development. Use this document as the source of truth for tokens, components, screen inventory, navigation, and tone.

---

## 0. APP IDENTITY

**ZVELT** is a strength-first fitness tracker with an integrated social feed, nutrition logger, race/challenge system, and AI coach. It's built for **obsessed athletes** — people who climb tiers, log every set, and refuse to plateau.

**Positioning:** "Built for the obsessed." Premium, dark, brutalist-aesthetic. Not a hobby app. The visual language signals seriousness — orange + black, italic display type, no rounded-friendly pastels.

**Target personas:**
- **A** Gamer-of-Progress (18–30) — rank, tier climb, leaderboards
- **B** Busy Builder (25–40) — minimum-friction set logging
- **C** Data Athlete (20–50) — e1RM curves, integrations, charts
- **F** Social Lifter (18–35) — feed, friends, challenges
- **H** Competitor (18–40) — leaderboard fairness, anti-cheat
- (D, E, G personas exist but not the primary visual target)

**Platforms:** Flutter (iOS + Android). Currently dark theme primary; light theme exists but is secondary.

---

## 1. DESIGN SYSTEM

### 1.1 Color tokens (DARK THEME — primary)

#### Background scale (deepest → highest elevation)
| Token | Hex | Use |
|-------|-----|-----|
| `bg0` / `bgPrimary` | `#050505` | Scaffold / root background |
| `bg1` | `#08080A` | Subtle layer (rarely used) |
| `bg2` | `#0D0D0F` | Mid layer |
| `s1` / `bgElevated` | `#111114` | Cards, primary elevated surfaces |
| `s2` / `bgSurface2` / `surfaceContainerHigh` | `#18181B` | Inset elements, sheets, dialogs |
| `s3` / `bgSurface3` | `#222226` | Inputs, chip backgrounds |
| `s4` | `#2A2A2E` | Hairline elevation above s3 |
| `navBarBg` | `#F2111114` (95% alpha) | Bottom nav floating glass effect |

#### Brand orange (signature)
| Token | Hex | Use |
|-------|-----|-----|
| `brand` / `primary` / `accentAmber` | `#FF5A1F` | Primary CTA, brand identity |
| `brand2` | `#FF7A2F` | Gradient mid-stop |
| `brand3` / `accentAmberDim` | `#FFB15C` | Light brand accent, glow halos |
| `deep` | `#D9360B` | Brand darkest (hero card backgrounds) |
| `glow` / `accentAmberGlow` | `#2EFF5A1F` (~18% brand) | Soft brand radial glows behind hero cards |
| `primaryContainer` | `#2A1608` | Brand-tinted container background |

#### Text
| Token | Hex | Contrast vs bg0 | Use |
|-------|-----|-----------------|-----|
| `t1` / `textPrimary` | `#FFFFFF` | 19.5:1 ✓ AAA | Primary text, headings |
| `t2` / `textSecondary` | `#C0C0C2` | 13.0:1 ✓ AAA | Secondary text, body |
| `t3` / `onSurfaceVariant` | `#808086` | 5.20:1 ✓ AA | Tertiary, meta, hints |
| `t4` | `#383840` | 1.65:1 — decorative only | Dividers, disabled glyphs |

#### State / semantic
| Token | Hex | Use |
|-------|-----|-----|
| `success` | `#22C55E` | Streaks done, sync OK, granted permissions |
| `info` / `accentBlue` | `#4DA3FF` (also `#2F6BFF`) | Running / cardio, informational links |
| `warn` / `warning` | `#FFB14A` / `#FFB020` | Caution, recovery, beta badges |
| `error` | `#FF4D4D` | Destructive actions, validation failures |
| `border` | `#14FFFFFF` (~8% white) | Hairline borders on dark surfaces |

#### Light theme (secondary — DON'T optimize for, but maintain parity)
- `_lBg0` `#FAFAFA` / `_lBg1` `#FFFFFF` / `_lBg2` `#F4F4F5`
- `_lS1..4` `#FFFFFF / #F4F4F5 / #E4E4E7 / #D4D4D8`
- `_lT1..3` `#0A0A0C / #3F3F46 / #71717A`
- `_lBorder` `#1A000000` (~10% black)
- Brand orange stays identical — it works on both backgrounds.

### 1.2 Gradients

```dart
gradBrand: 135° linear, [#FF3D1F → #FF6A1F → #FFB15C]  // hero text, badges
gradBtn:   135° linear, [#FF3D1F → #FF7A2F]            // primary CTAs
gradHero:  top→bottom, [bgPrimary → deep → bgPrimary]  // rank-reveal card
```

**Radial glow pattern (used heavily):** `RadialGradient` with stops `[brand@22%, brand@4%, transparent]` at `[0, 0.4, 0.65]` — appears as soft 380px-wide orange halos behind hero content.

### 1.3 Typography

**Three font families:**
- **`Barlow Condensed`** — display / headings. ALWAYS italic, weight 900. Used for: page titles, big numbers (XP, ranks, weights), screen eyebrows.
- **`DM Sans`** (via Google Fonts) — body text. Weights 400/500/600/700/800/900. Used for: paragraphs, labels, captions, inputs.
- **`SpaceMono`** — monospaced, rare use. For data tables, technical readouts (e.g., e1RM CSV exports).

**Size scale (px):**
| Token | Size | Use |
|-------|------|-----|
| xs | 9–10 | Eyebrow labels, micro chips |
| sm | 11–13 | Captions, secondary meta |
| md | 14–16 | Body, button labels |
| lg | 18–22 | Section headings (Sans) / mid display (Barlow) |
| xl | 28–40 | Major display (Barlow Condensed italic 900) |
| xxl | 60–72 | Hero "BUILT FOR THE OBSESSED" |

**Letter-spacing conventions:**
- Eyebrows / chips / button labels in Barlow Condensed italic 900: `letterSpacing: 1.5–3.5` (tracked uppercase)
- Body text DM Sans: default tight or `letterSpacing: 0`
- Display Barlow Condensed: `letterSpacing: -0.01em to -1px` (visually tighter at large sizes)

**Line-height (`height` property):**
- Display: 0.92–1.02 (very tight, almost touching)
- Body: 1.4–1.55
- Numeric readouts (Barlow): 0.9–1 (numeric tightness)

### 1.4 Spacing & Layout

**Grid:** 8pt base (`grid = 8`).

**Padding conventions:**
- Screen edge: `EdgeInsets.fromLTRB(20, 14, 20, 6)` (left/right 20, top 14, bottom 6 because content uses bottom safe area)
- Card inset: 14–16
- Tile inset: 12–14
- Bottom of scroll: `bottom + 28` (safe area + breathing room)

**Border radius scale:**
| Token | Value | Use |
|-------|-------|-----|
| `radiusChip` | 999 | Pills, chips, badges, touch buttons (perfect circle if square) |
| `radiusCard` | 22 | Standard cards, hero cards |
| `radiusModal` | 24 | Bottom sheets, dialogs |
| (sm) | 10–14 | Inputs, small chips, inline elements |
| (xs) | 4 | DM bubble inner corner ("tail" effect) |

**Touch targets:** Min 44×44pt (iOS) / 48dp (Android). Enforced via `Material.constraints` or `ConstrainedBox`.

**Shadows / elevation:**
- Primary CTA shadow: `BoxShadow(color: Color(0x72FF5A1F), blurRadius: 28, offset: Offset(0, 10))` — heavy orange glow under brand-gradient buttons
- Soft elevated card: `BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))`
- Glow halo: not a real shadow — a `RadialGradient` Container behind the element

### 1.5 Motion

**Duration scale:**
- Fast: 160–200ms — toggles, taps, chip selection
- Default: 220–320ms — transitions, AnimatedContainer
- Slow: 800ms–4s — orbital animations, story progress (5s), shimmer loops

**Common curves:**
- `Curves.easeOutCubic` — most transitions
- `Curves.elasticOut` — toggle handles (with delight)
- Linear repeat — pulsing dots, scan lines, dashed-circle rotation

**Repeating animations:**
- Pulsing brand dot (signals "live" or attention) — 2.4s reverse
- Dashed circle ring (around FAB) — 3s reverse, opacity 0.3→0.5
- Story progress bar — 5s linear forward
- Hero scan line — 1.6s linear

### 1.6 Iconography

**Source:** `Icons.*_rounded` (Material rounded set) is the default. Avoid sharp/filled variants unless intentional.

**Common semantic icon assignments:**
- Brand: `Icons.auto_awesome_rounded` (sparkle) → AI Coach
- Train: `Icons.fitness_center_rounded` (dumbbell) / `Icons.bolt_rounded` (push intensity)
- Run: `Icons.directions_run_rounded`
- Bike: `Icons.pedal_bike_rounded`
- Body: `Icons.accessibility_new_rounded` / `Icons.monitor_weight_rounded`
- Health: `Icons.favorite_rounded` (HR), `Icons.bed_rounded` (sleep), `Icons.watch_rounded`
- Social: `Icons.groups_rounded`, `Icons.chat_bubble_outline_rounded`, `Icons.tag_rounded`
- Privacy: `Icons.lock_outline_rounded`, `Icons.visibility_outlined`, `Icons.shield_outlined`
- Race: `Icons.emoji_events_rounded` (trophy), `Icons.flash_on_rounded` (energy)

**Icon color rules:**
- On dark bg: `t2` (body inline) or `brand3` (brand contextual) or semantic (success/info/warn/error)
- Inside circular containers (avatars, action chips): `t1` / `Colors.white`

---

## 2. NAVIGATION STRUCTURE

### 2.1 Top-level shell

`MainScreen` hosts a **4-tab bottom navigation** with a custom **floating central FAB** (the `ZveltPill`):

| Index | Tab | Screen | Purpose |
|-------|-----|--------|---------|
| 0 | Home | `SkeletonHomeTab` | Dashboard — today's training, streak, friend activity, quick stats |
| 1 | Progress | `ProgressHubScreen` | Charts, e1RM, rankings, achievements, photo progress |
| 2 | Social | `SocialPlusScreen` | Main feed (posts, stories, races) |
| 3 | Nutrition | `NutritionTab` | Macros, meals, barcode scan |

**Central FAB:** Floating brand-gradient `+` button with dashed orbital ring. Opens `QuickLaunchSheet` — a bottom-sheet with 4 workout type tiles (Run, Bike, Push, Pull) for one-tap workout start.

**Profile access:** Profile/Settings/Notifications opened from the home tab header (avatar tap) → push fullscreen routes (not part of bottom nav).

### 2.2 Auth & onboarding flow

```
Welcome (entry/welcome_screen.dart)
  ↓ "Get started" or "Already have account"
Login (login_screen.dart) [or Signup, embedded]
  ↓ on success
AuthGate detects token + checks onboarding flag in SharedPrefs
  ↓ if onboarding not done:
OnboardingV2 (29 steps, single file ~4000 lines)
  ↓ on completion:
MainScreen (home tab)
```

**Inside OnboardingV2** there's a sub-route: tapping "Try as guest" pushes `_GuestSignInPage` (embedded), which collects email+password and completes onboarding immediately, skipping the rest.

### 2.3 Feed sub-routes (pushed from SocialPlusScreen)

```
SocialPlusScreen (main feed)
├─ Story tap → _StoryViewerScreen (overlay, auto-advance 5s/story)
├─ Post tap → PostDetailScreen → comment composer + comment list
├─ Avatar tap → UserProfileScreen (any user — posts + add friend / block)
├─ Race hero CTA → RaceHubScreen → RaceChatScreen (private "Race Notes")
├─ Gallery icon → GalleryScreen (all post photos in 3-col grid)
├─ Circle icon → CircleScreen → FriendsScreen / DirectChatScreen
├─ Bell icon → NotificationsScreen
└─ Search → in-feed search (not separate screen)
```

### 2.4 Settings sub-routes

```
Settings
├─ Physical data → ProfileScreen
├─ Notifications → NotificationsScreen
├─ Journal → JournalTab
├─ Change password → inline dialog
├─ Two-factor → inline toggle (PATCH /v1/auth/2fa)
├─ Profile visibility → inline radio dialog
├─ Privacy toggles (3 switches: feed friends-only / discovery / DM friends-only)
├─ Blocked users → BlockedUsersScreen
├─ Delete account → DeleteAccountScreen (P0.9, full screen with confirmation)
├─ Integrations → IntegrationsScreen (Apple Health/Health Connect/Strava/Garmin/Fitbit/Polar/Wahoo)
├─ Appearance / Language / Units → device-local pref dialogs
└─ App Store / Help / Privacy Policy / Terms → external URL launches
```

---

## 3. SCREEN INVENTORY

Total: **63 screens** across 16 functional areas. Organized below.

### 3.1 Authentication & entry (3)
| File | Purpose |
|------|---------|
| `entry/welcome_screen.dart` | Pre-auth landing — brand value prop |
| `login_screen.dart` | Email/password + Apple/Google OAuth |
| `onboarding/onboarding_v2.dart` | 29-step onboarding (see §3.2) |

### 3.2 Onboarding (29 steps in ONE file — already designed, do not redesign)

| Step | Purpose |
|------|---------|
| 0 | Hero "Built for the obsessed" — full-bleed brand statement |
| 1 | Sign-in choice (Apple / Google / Email / Guest) + → guest sub-page |
| 2 | Plateau chart problem statement |
| 3 | 4 pillars 2×2 grid (AI Coach / Strength / Race / Tribe) |
| 4 | 84,000 tribe social proof (3×3 avatar grid) |
| 5 | "Ask Zvelt" chat demo |
| 6 | e1RM chart card |
| 7 | Leaderboard placement preview |
| 8 | One-tap FAB demo (dashed ring + 4 activity micro-cards) |
| 9 | Barcode scanner demo |
| 10 | Name + avatar input |
| 11 | Archetype (Lifter/Runner/Hybrid/Aesthete) 2×2 |
| 12 | Goal selection (5 vertical tiles) |
| 13 | Source survey ("Where did you find us?" 2×2 of 8) |
| 14 | Permissions (Health/Watch/Motion/Location/Notif) with toggles |
| 15 | Body stats (sex + 3 sliders + metric/imperial) |
| 16 | Wearable / vitals tease (Garmin/Apple Watch/Whoop) |
| 17 | Experience (4 tiles 0–5+ years) |
| 18 | Gym PRs (bench/squat/dead inputs) |
| 19 | Cardio PRs (5K time, longest ride) |
| 20 | Weekly cadence (3 tiles 2–3 / 4–5 / 6+) |
| 21 | AI Talk (chat with Zvelt — user types 90-day vision) |
| 22 | "Forging system..." loading with progress ring |
| 23 | Your weekly plan reveal |
| 24 | Hall of Fame placement (#4,829) |
| 25 | 3 matched athletes |
| 26 | Community follow (IG/TikTok/YouTube/X) |
| 27 | Lock the moment (progress photo) |
| 28 | Welcome final ("You're in") |

**(Step 28 paywall was removed for v1.0 ship; Pro tier deferred to v1.1.)**

### 3.3 Home / Dashboard (1 main + 6 skeleton tabs)
| File | Purpose |
|------|---------|
| `skeleton/skeleton_home_tab.dart` | Main home dashboard — streak, today's plan, friend activity |
| `skeleton/skeleton_profile_tab.dart` | Profile hub (opens from header avatar) |
| `skeleton/skeleton_workouts_tab.dart` | Legacy skeleton (not in active nav) |
| `skeleton/skeleton_nutrition_tab.dart` | Legacy skeleton (not in active nav) |
| `skeleton/skeleton_social_tab.dart` | Legacy skeleton (not in active nav) |
| `skeleton/skeleton_ranks_tab.dart` | Legacy skeleton (not in active nav) |
| `main_screen.dart` | Bottom nav shell |

### 3.4 Workouts (8)
| File | Purpose |
|------|---------|
| `workouts/workouts_tab.dart` | Workout history + start new |
| `workouts/workout_tracker_screen.dart` | Active workout (sets/reps/RPE/rest timer/instrumentation) |
| `workouts/quick_launch_sheet.dart` | Bottom sheet from FAB — 4 activity tiles |
| `workouts/exercise_library_screen.dart` | Browse all exercises |
| `workouts/exercise_detail_screen.dart` | Single exercise detail + form cues |
| `workouts/program_builder_screen.dart` | Weekly program builder |
| `workouts/post_workout_screen.dart` | Post-completion summary |
| `workouts/xp_complete_screen.dart` | Rank/XP celebration on PR |

### 3.5 Activity & outdoor (4)
| File | Purpose |
|------|---------|
| `activity/activity_summary_screen.dart` | Read-only summary of a logged activity |
| `activity/activity_tracking_screen.dart` | Live GPS tracking for outdoor activity |
| `activity/workout_complete_screen.dart` | Post-workout XP + share |
| `outdoor/outdoor_track_screen.dart` | Live GPS map + route capture |

### 3.6 Analytics & progress (7)
| File | Purpose |
|------|---------|
| `analytics/progress_hub_screen.dart` | Progress tab root (Progress bottom-nav index 1) |
| `analytics/analytics_hub_screen.dart` | Drill-down analytics hub |
| `analytics/strength_analytics_screen.dart` | e1RM curves per exercise |
| `analytics/progression_screen.dart` | Strength progression chart |
| `analytics/weekly_effort_screen.dart` | Weekly effort score |
| `analytics/hall_of_fame_screen.dart` | Global leaderboard with user placement |
| `analytics/strava_labs_tab.dart` | Strava-derived HR zones, fitness curves |

### 3.7 Photo Progress (2 — local-first, no backend)
| File | Purpose |
|------|---------|
| `analytics/photo_capture_screen.dart` | Camera flow for progress photo |
| `analytics/photo_progress_screen.dart` | Gallery + draggable side-by-side comparison slider |

### 3.8 Nutrition (2)
| File | Purpose |
|------|---------|
| `nutrition/nutrition_tab.dart` | Nutrition bottom-nav root (macros + meals + scan) |
| `nutrition/nutrition_barcode_scan_screen.dart` | mobile_scanner camera for UPC/EAN13 |

### 3.9 Social / Feed (15) — see §4 for component-level detail

| File | Purpose |
|------|---------|
| `social/social_plus_screen.dart` | Main feed (Social bottom-nav index 2) — stories + race hero + feed + filters |
| `social/post_detail_screen.dart` | Single post + comments composer |
| `social/direct_chat_screen.dart` | 1:1 DM thread with FCM realtime + cursor pagination |
| `social/conversations_screen.dart` | DM list |
| `social/circle_screen.dart` | Friends overview — top streaks + recent activity |
| `social/friends_screen.dart` | Friends list / search / requests (3 tabs) |
| `social/notifications_screen.dart` | Notifications inbox with cursor pagination |
| `social/gallery_screen.dart` | All post photos 3-column grid |
| `social/race_hub_screen.dart` | Race configurator + active challenges carousel + chat opener |
| `social/challenge_kind_picker_screen.dart` | Exercise picker for new race |
| `social/create_challenge_sheet.dart` | Bottom-sheet new challenge |
| `social/bookmarks_screen.dart` | "My Bookmarks" with pagination + animated remove |
| `social/user_profile_screen.dart` | View any user's profile + posts (from avatar tap) |
| `social/blocked_users_screen.dart` | Block list management + pending reports footer |
| `social/report_user_sheet.dart` | Modal report flow (6 categories + 500-char note) |

### 3.10 Health (3)
| File | Purpose |
|------|---------|
| `health/health_screen.dart` | Health stats dashboard |
| `biology/biology_tab.dart` | VO₂/HRV/sleep/weight detail tab |
| `calendar/activity_calendar_screen.dart` | Workout calendar |

### 3.11 Profile (5)
| File | Purpose |
|------|---------|
| `profile_screen.dart` | Edit physical data (bw/height/sex/birth-year) |
| `profile/account_settings_screen.dart` | Account menu |
| `profile/achievements_screen.dart` | Earned + locked achievements with tier/XP |
| `profile/heatmap_screen.dart` | Activity heatmap (GitHub-style year grid) |
| `profile/integrations_screen.dart` | Connected apps (Apple Health / Health Connect / Strava + 4 wearables) |

### 3.12 Settings (2)
| File | Purpose |
|------|---------|
| `settings/settings_screen.dart` | Full settings hub (~1700 lines) |
| `settings/delete_account_screen.dart` | GDPR-compliant account deletion |

### 3.13 Journal (2 — local-first, no backend)
| File | Purpose |
|------|---------|
| `journal/journal_tab.dart` | Daily entries list + trend chart |
| `journal/journal_entry_screen.dart` | Composer (mood/energy/soreness/notes) |

### 3.14 AI (1)
| File | Purpose |
|------|---------|
| `ai/ai_chat_screen.dart` | AI Coach chat (Ask Zvelt) |

### 3.15 Segments (1)
| File | Purpose |
|------|---------|
| `segments/segment_leaderboard_screen.dart` | Per-exercise leaderboard with BW band |

### 3.16 Shell overlays (1)
| File | Purpose |
|------|---------|
| `shell/goal_advice_overlay.dart` | Floating coaching overlay |

---

## 4. COMPONENT LIBRARY

### 4.1 Atomic components (already built — use these)

| Component | File | Purpose |
|-----------|------|---------|
| `ZveltPrimaryButton` | `widgets/zvelt_primary_button.dart` | Primary CTA. **3 variants**: `gradient` (default brand), `darkInverse` (black pill for orange-glow heroes), `lightInverse` (white pill for dark configurator cards). **Props**: `small`, `icon`, `busy` + `busyLabel`. Height 56 default, 40 when `small`. |
| `ZveltSecondaryButton` | `widgets/zvelt_secondary_button.dart` | Medium-emphasis (outlined / filled-flat). |
| `ZveltTertiaryButton` | `widgets/zvelt_tertiary_button.dart` | Text-only. Min touch target 44×44 enforced even when `dense: true`. |
| `ZveltAvatar` | `widgets/zvelt_avatar.dart` | Single avatar source. **5 sizes** via `AvatarSize` enum: `xs=28 / sm=36 / md=44 / lg=56 / xl=96`. Auto-renders gradient + initials when no image. Optional ring (orange glow), online dot. `onTap` wraps in `Semantics(button: true, label: "Avatar of $name")`. |
| `ZveltNetworkImage` | `widgets/zvelt_network_image.dart` | `cached_network_image` wrapper with disk cache + tiered `cacheWidth` (`storyThumb` 200 / `feedFull` 1080 / etc.). |
| `ZveltEmptyState` | `widgets/zvelt_empty_state.dart` | Single empty-state widget. Props: `title`, `subtitle`, `icon`, `action`, `compact`. Min height 220 full / 0 compact. |
| `ZveltErrorState` | `widgets/zvelt_error_state.dart` | Single error widget. `ZveltErrorTier { network, auth, server, generic }` with default copy + icon + color per tier. Always renders "Try again" button. |
| `ZveltPill` | `widgets/zvelt_pill.dart` | The floating central FAB (dashed orbital ring + brand gradient `+`). |
| `ZveltMainNavBar` | `widgets/zvelt_main_nav_bar.dart` | Bottom nav glass bar. |
| `SocialFeedPostCard` | `widgets/social_feed_post_card.dart` | Single feed post (author + privacy badge + caption + photo + actions row + inline comments sheet). |
| `SocialChallengeCard` | `widgets/social_challenge_card.dart` | Race/challenge card. |
| `MuscleMapWidget` | `widgets/muscle_map_widget.dart` | Body diagram for workout selection. |
| `GameXpBar` | `widgets/game_xp_bar.dart` | XP progress bar with tier label. |
| `ActivityShareCard` | `widgets/activity_share_card.dart` | Share-to-social card render. |
| `BeastIntelligenceCard` | `widgets/beast_intelligence_card.dart` | AI insight card. |
| `CharacterStatsCard` | `widgets/character_stats_card.dart` | Avatar + stat strip. |
| `SplitsTable` | `widgets/splits_table.dart` | Run/bike splits row table. |
| `ExerciseGifDialog` | `widgets/exercise_gif_dialog.dart` | Exercise demonstration GIF modal. |
| `ShareBottomSheet` | `widgets/share_bottom_sheet.dart` | Standard share UI. |
| `ScrambleText` / `TypewriterRevealText` | `widgets/scramble_text.dart` / `widgets/typewriter_reveal_text.dart` | Animated text effects (hero reveals). |

### 4.2 Charts (`widgets/charts/`)

Custom-painted with `CustomPaint`:
- `_PlateauPainter` — dashed grey line + brand-gradient climb (onboarding step 2)
- `_E1rmChartPainter` — 9-point e1RM curve with gradient fill
- `_DashedCirclePainter` — 16-segment dashed circle (FAB ring)
- `_RingPainter` — circular progress ring (onboarding step 22 loading)
- Workout consistency heatmap (year grid)
- Rest time trend
- Weekly effort score
- VO₂ Max trend line

### 4.3 Card patterns

**Standard card:**
```
padding: EdgeInsets.fromLTRB(16, 14, 16, 14)
color: AppTheme.s1 (#111114)
borderRadius: 22 (radiusCard)
border: 1px AppTheme.border (8% white)
```

**Hero card (orange-glow):**
```
gradient: LinearGradient([#C93010, #E8480E, #FF7A2F], topLeft → bottomRight)
borderRadius: 22
boxShadow: [BoxShadow(color: #66C93010, blurRadius: 40, offset: (0, 14))]
+ Positioned RadialGradient halo (#46FFFFFF→transparent) at top-right corner
```

**Brand-tinted info card:**
```
color: brand@6% opacity
border: brand@18% opacity
borderRadius: 14
+ small pulsing brand dot left of text
```

**Privacy badge pill:**
```
padding: (6h, 2v)
radius: 100
font: 9px DM Sans 900 letterSpacing 1
icon: 10px
- PUBLIC: globe icon, t2 grey
- FRIENDS: people icon, brand3 amber
- PRIVATE: lock icon, warn amber
```

### 4.4 Form inputs

- TextField with `filled: true`, `fillColor: s1 (#111114)`, `contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14)`, `borderRadius: 14`, enabled border `border (#14FFFFFF)`, focused border `brand` 1.5px width.
- Slider with white thumb (12px radius), brand active track, `s3` inactive track, brand@20% overlay on press.
- Toggle switch: 42×24 pill, animated handle slide with `Curves.elasticOut`, brand fill when on / `s3` when off.

### 4.5 Modals & sheets

- **Bottom sheet:** rounded top-left/right 24px, `s1` background, drag handle 36×4 pill at top, `bgPrimary` scrim. Use `isScrollControlled: true` for forms.
- **Dialog:** `bgElevated` background, 16px radius, max-width 320, content inset 24px.
- **SnackBar:** floating, 100px from bottom, `s2` background, 12px radius. Action button text in `brand`.

### 4.6 Empty states (visual spec)

`ZveltEmptyState` consistent across all screens:
- Icon: 56px (full) or 36px (compact), `textSecondary @ 60% alpha`
- Title: 16px or 14px (compact), `t1`, bold
- Subtitle: 13px or 11px (compact), `t2`, center-aligned, max 2 lines
- Optional action below
- Min height 220 full

---

## 5. VISUAL TONE & STYLE

### Mood
- **Dark, brutalist, athletic.** Not friendly — competitive. Like a Berlin techno club aesthetic crossed with a Nike performance ad.
- **Display type is ALWAYS italic Barlow Condensed weight 900.** This is the brand's voice — urgent, condensed, in motion.
- **Orange + black is non-negotiable.** Orange means action, energy, brand. Black is the floor. Anything in-between is signal noise.

### Layout philosophy
- **Dense but breathing.** Cards stack tightly (8–12px gap) but each card has generous inner padding (14–16px).
- **No skeumorphism, no gradients in icons.** Icons are flat rounded outlines or filled, never embossed.
- **Numbers are big.** Weights, XP, ranks, percentages — render at 28–72px with Barlow Condensed italic. This is the app's main visual delight.

### What ZVELT ≠
- ❌ Pastel palettes
- ❌ Cute mascot illustrations
- ❌ Smooth gradients across the whole UI (gradients reserved for primary CTAs and 1–2 hero moments per screen)
- ❌ Material Design 3's default rounded look (we use custom rounding 22/14/100)
- ❌ Calm/wellness app vibes (we're a competitive performance tool, not a mindfulness app)

### What makes ZVELT visually distinct vs other fitness apps
1. **Orange-on-black brutalism** — most fitness apps go blue/green/white. We own orange.
2. **Italic display headlines** — visually communicates motion and urgency.
3. **Radial brand glows** behind hero content (not blurred photo backgrounds).
4. **Numeric typography is a hero element** — the rank #4,829 or weight 87.5kg is treated like a magazine display number.
5. **Eyebrow micro-labels** above every section ("THE PROMISE", "Feature 02 · Strength") in 9–10px ALL-CAPS letter-spacing 3 — gives the app a print-editorial feel.

---

## 6. WHAT'S DONE vs WHAT NEEDS DESIGN WORK

### ✅ Fully designed & shipped
- Entire 29-step onboarding (`onboarding_v2.dart` — DO NOT REDESIGN)
- Bottom nav + FAB shell
- Login + Welcome
- Full social/feed area (feed, post detail, DM, conversations, circle, friends, notifications, gallery, race hub, bookmarks, user profile, blocked users, report sheet)
- Settings + Delete Account
- Photo Progress (capture + gallery + draggable comparison)
- Profile screen (physical data)
- BlockedUsersScreen + ReportUserSheet (Apple §1.2 compliance)
- Achievements + Heatmap + Integrations

### 🟡 Partially designed (functional but visual polish welcome)
- `workouts/workout_tracker_screen.dart` — set logging UI works but could use more delight on PR moments
- `nutrition/nutrition_tab.dart` — macros bar + meal log + scan exists, layout dense, could benefit from a hero macro circle
- `biology/biology_tab.dart` — full UI was built in Wave 9 but card density is high
- `analytics/progress_hub_screen.dart` — many cards stacked, could benefit from clearer hierarchy

### 🔵 Built functional, would benefit from polish
- `health/health_screen.dart` — health stats dashboard
- `analytics/strava_labs_tab.dart` — Strava-derived insights
- `analytics/hall_of_fame_screen.dart` — leaderboard
- `journal/` — journal local feature
- `ai/ai_chat_screen.dart` — works but message bubbles could match DM bubbles more closely
- `calendar/activity_calendar_screen.dart`

### ❌ Missing / planned for v1.1+ (do NOT design now unless asked)
- Pro paywall (removed from onboarding step 28)
- Group DMs (currently 1:1 only)
- Story highlights / story view list
- Voice messages
- Multi-image posts / video posts
- Typing indicators / read receipts
- Hashtag pages
- @mentions UI
- Per-conversation notification settings
- Notification preferences screen (granular)
- Real-time race chat (currently local-only "Race Notes")
- Wear OS companion

---

## 7. DESIGN DELIVERABLES NEEDED FROM YOU

When continuing the design, I expect deliverables in this order:

1. **High-fidelity mockups** for any "Partially designed" screen above (Workout Tracker, Nutrition, Biology, Progress Hub, Health, AI Chat).
2. **A polish pass** on any "Built functional" screen — bring them up to the brand-fidelity bar set by the onboarding.
3. **New screens for v1.1** if scope is approved (Pro paywall, group DMs, story highlights, etc.) — but ONLY after the v1.0 polish pass is signed off.

For each deliverable:
- **3 viewport variants**: small (375×667 iPhone SE), medium (390×844 iPhone 13), large (430×932 iPhone 15 Pro Max).
- **Dark + light theme** versions (light = secondary priority).
- **Spec annotations**: token names used, exact padding/spacing, font sizes, animation timings.
- **Components callouts**: reuse `ZveltPrimaryButton`, `ZveltAvatar`, `ZveltEmptyState`, etc. wherever possible — don't reinvent.

---

## 8. CONSTRAINTS & RULES

1. **Don't redesign onboarding** — it's pixel-locked to the existing HTML reference.
2. **Don't add new icons** — use Material `Icons.*_rounded` set.
3. **Don't introduce new fonts** — Barlow Condensed / DM Sans / SpaceMono only.
4. **Don't introduce new colors** — pull from `AppTheme.*`. If you need a new semantic, add it as a token.
5. **Maintain ≥4.5:1 contrast** for body text (WCAG AA).
6. **Touch targets ≥44pt** (iOS HIG / Material accessibility).
7. **Support dynamic text scaling 200%** without breaking layouts.
8. **Animations honor `MediaQuery.disableAnimations`** (reduced motion users).
9. **Privacy-first messaging** — when a screen handles user data, surface privacy clearly. CLAUDE.md spec: friend-only feed default, opt-in discovery.
10. **Anti-fake** — every UI element must reflect real data state or be clearly marked as private/local-only (e.g., Race Notes). No mock counts, fake user lists, hardcoded "1.2K live" placeholders.

---

## 9. REFERENCE FILES (in the project)

- Design system source of truth: `app/lib/theme/app_theme.dart`
- Onboarding reference (do not redesign): `app/lib/screens/onboarding/onboarding_v2.dart`
- Component widgets: `app/lib/widgets/zvelt_*.dart`
- Original HTML design reference: `C:\Users\razva\Downloads\zvelt-design-bundle\zvelt-v1-0\project\zvelt-app-v2.html` (for onboarding only)
- Project brief: `E:\razvanluna\CLAUDE.md`

---

**End of brief. Ship the polish pass first; v1.1 features second.**
