# Zvelt — 10-Persona User Test (heuristic, against real screens)

_Avg rating: 6.3/10. 10 in-character testers read the real app and reacted._


## Cătălin, 24 — the chronic complainer (friction / latency / clutter / broken-promises lens) — 5/10
_Annoyed before I've even broken a sweat — I came to lift, not to scroll a newsletter._

**First impression:** I open "Train" expecting, you know, training. Instead it's a CONVEYOR BELT of cards. AI Workout button, then "Set a new goal" pill, then a recovery card, then "Connect a wearable," then a heatmap, then weekly bars, then a performance chart, then a daily-reminder toggle, then streak + workouts tiles, then an XP bar, then a coach tip, then an outdoor-run hero, then character stats, then last workout, then steps, then a motivational quote at the very bottom. Fifteen-ish cards. To start lifting I either tap the top button or hunt for the center "+". Why is the home of a fitness app a scrollable wall of dashboards? I'm exhausted and I haven't touched a barbell.

**Loved:**
- The countdown is actually slick — big 200px '3...2...1...GO!' with the elastic bounce. Fine, that one's cool.
- Offline save is honest: log a set with no signal and it says 'Saved offline — will sync when back online' instead of just eating my reps. Rare to see done right.
- Empty states don't lie — the heatmap stays empty instead of inventing fake training days, and the AI chat greeting admits it hasn't analyzed anything yet. At least nobody's gaslighting me.
- The exit sheet gives me Save & exit / Complete / Discard with subtitles. Clear. Good.

**Frustrated:**
- TWO different ways to start a workout that don't match. The Train screen has 'AI Workout' + 'Custom workout' boxes; the center '+' opens a totally different sheet ('What are we doing?' with Push/Pull/Legs/Cardio tiles). Same goal, two unrelated UIs. Pick one.
- The '+' sheet's 'AI workout' shortcut chip opens the AI CHAT, but the Train screen's 'AI Workout' button opens an AI workout SHEET. Same name, two destinations. That's how you make me distrust every label.
- Every preset is stuffed with FAKE numbers — Bench 4×6-8 @ 80kg, Deadlift 4×5 @ 140kg, Squat 5×5 @ 120kg — identical for every human on earth. I don't squat 120. Now I have to edit every single set before I even start. That's not a 'quick' launch.
- A forced 3-second countdown before EVERY preset. I tapped 'start', I meant start, not 'start in 3 seconds while a giant number bounces at me'.
- 'AI · always on' green dot in the coach header — then it times out with 'Zvelt is taking a moment to think.' Always on, except when it isn't. And messages are capped at 300 characters, so I can't even explain my injury properly.
- Home fires /me, /workouts, reminder prefs, THEN deferred steps, pack challenge, and training history — staggered loads. The performance-trend scope button literally shows '…' while it refetches when I tap 30D/3M/1Y. I can watch it think.

**Confused:**
- What is 'Strain'? The card says it's a 'transparent daily-load proxy' but as a normal user I have no idea what the number means or why I should care.
- Two near-identical streak surfaces: a 'Streak at risk' retention banner up top AND a separate Streak tile lower down. Which one is the real one?
- The activity card says 'X-day streak · Y sessions' but the weekly bars are driven by actual workouts and the streak is driven by POSTING. So my streak and my training week can disagree and nobody explains why.
- 'Set a new goal' pill — is that a new goal, or editing my existing one? It opens a whole evolution flow. The label undersells what happens.

**Top fixes:**
- Cut the Train screen down to maybe 4 things above the fold: start a workout, today's plan, streak, recent. Move the heatmap/trend/quotes/reminder toggle into Progress or Settings where dashboards belong.
- Unify the workout-start flow. One entry point, one sheet, consistent labels — 'AI Workout' should mean the same thing whether I tap a button or the '+'.
- Kill the fake preset weights, or pre-fill from MY last session. Generic 140kg deadlifts make the whole preset feel like a stock screenshot, and force an edit-everything tax before set one.
- Make the 3-second countdown skippable (tap to skip) and stop showing '…'/staggered loads on Home — preload or cache so tapping a scope is instant.

**Quote:** "I counted fifteen cards before I found my last workout, edited six fake sets I never lifted, then waited three whole seconds for a bouncing number to let me train. 'Quick launch.' Sure."

## Ioana, 19 — the Curious Explorer who taps everything — 8/10
_Wide-eyed and tapping everything: half the time squealing "ooh what's THIS", the other half going "wait... what does this button even do??"_

**First impression:** The onboarding HOOKED me before I even logged in. The splash with the pulsing brand glow and "Train · Fuel · Evolve", then "Five apps. Zero clarity." with the disconnected chips (Workout log, Calorie app, Sleep tracker, Group chat, Spreadsheet) versus the glowing "One system" card — that's a little story, I wanted to swipe to the next one. Then "248k training now" with the stacked avatars and Yusuf's "Hit my first 100kg bench with my Zvelt crew cheering" — okay, sold, "Join them". Once inside, the Train tab is a TREASURE CHEST. The header literally greets me "Good morning, [name]" with today's date, there's an XP bar, a GitHub-style activity heatmap, a recovery card with rings, a performance trend chart with a 30D/3M/1Y button... every card looks tappable and most of them ARE. I kept scrolling going "there's MORE?!"

**Loved:**
- The big juicy + button opens a 'What are we doing?' sheet with 2x2 tiles (Push/Pull/Legs/Cardio) AND a horizontal 'YOUR SHORTCUTS' rail (Empty, AI workout, Run, Meal, Race, Photo) — discovering that little scrolling rail of shortcuts felt like finding a secret menu
- Starting a Push Day actually fires a giant elastic-bounce 3...2...1...GO! countdown with a glow shadow before the workout. That delighted me way more than it should have
- The AI workout sheet shows a 'Why this exercise' chip with a sparkle icon under each move, tied to my goal — I never feel like the app is bossing me around for no reason, it explains itself
- The AI Coach chat opens with prompt chips like 'Am I recovered enough to train?' and 'Review my bench form' so I'm never staring at a blank box wondering what to type
- HIDDEN GEM: long-pressing a tile in the quick-launch sheet pins it as my default — I only found that by accident and felt like a genius
- Cardio Run opens a full live MAP with a route line, recenter button, distance/pace/elevation overlay, and a 'GPS live' pill — I did not expect a real GPS tracker in here
- The weight badge tooltips ('Based on your last working set' vs 'AI estimate from your bodyweight') — I tapped and learned WHY a number was there. Curious-girl heaven
- Tapping the Resting HR / Steps / Sleep / HRV vitals tiles each opens its own detail screen — everything I poked actually went somewhere

**Frustrated:**
- The Train tab is a MILE long — heatmap, weekly bars, performance trend, daily reminder, streak+workouts, XP, coach tip, outdoor track, character stats, last workout, steps, motivation quote. I love exploring but by card #9 my thumb is tired and I've lost track of what's where
- Cardio is hidden in TWO places that do different things: the 'Cardio' quick tile and 'Browse library →' both just open the same library, but the home-screen presets (Outdoor Run) live somewhere else, and the quick-launch comment even admits Swim/Yoga/Hike from the design 'have no tracking flow yet' so they're missing — I went looking for yoga and found nothing
- The Apple sign-in button is right there looking real but just says 'Apple sign-in is coming soon' when I tap it — tease!
- If I haven't connected a wearable, the recovery card shows '–' everywhere and a 'Connect a wearable' nudge, but the card is still fully there taking up space looking broken-ish until I read the tiny text
- Steps shortcut, heatmap, weekly bars all start EMPTY/zero for a brand-new me — honest, but a curious new user pokes a flat chart and thinks 'is it broken?' before realizing she just hasn't trained yet

**Confused:**
- What's the difference between the + Quick Launch sheet, the 'AI / Custom' workout mode boxes at the TOP of Train, AND the AI Coach chat? Three doors that all seem to start workouts — I tapped all three trying to find 'the' way in
- The 'Set goal' button vs the AI coach vs onboarding personalization — where does my goal actually LIVE and which one changes my recommendations?
- The Feed has a 'trending/friends' toggle AND an All/Following/Popular/Races filter row — two filter systems stacked, I couldn't tell which one I'd actually changed
- 'Streak' is based on POSTING not training (the at-risk banner explains it) — that genuinely confused me; I trained 3 days and my streak still felt at risk because I hadn't posted
- The 'Race of the Week' hero said 'Be the first to join' then changed — for a second I thought the race was empty/dead before the count loaded in

**Top fixes:**
- Tame the Train tab — let me reorder/collapse cards or move the deeper stuff (character stats, motivation quote, outdoor track) behind a 'more' section so the first screen isn't a scroll marathon
- Pick ONE obvious 'start a workout' entry point and make the others clearly secondary — three competing doors (mode boxes, + sheet, AI chat) is too many for a first-timer
- Either wire up the teased options or hide them: Apple sign-in 'coming soon', and the missing Swim/Yoga/Hike activities make the explorer feel like she hit dead ends
- Make the posting-based streak crystal clear up front (a tiny 'streak = posting' hint on the streak card itself), because right now it surprises people who actually trained
- Give empty charts/heatmaps a friendly first-run line like 'Log your first workout to fill this in' so a poking newbie doesn't think the chart is broken

**Quote:** ""Okay this app is a RABBIT HOLE in the best way — I found a secret long-press-to-pin and a GPS map I wasn't even looking for. But also: there are like three different buttons that start a workout and I genuinely don't know which one is THE one, pralo.""

## Marius, 38 — the Busy Builder (persona B). Trains 4x/week on a 45-minute clock, wants to log a set in under a minute with the fewest taps. Judges everything by speed, tap-count, and friction in the start→log→done loop. — 6/10
_Halfway impressed, halfway shouting "just let me log the bloody set" at the countdown timer._

**First impression:** Center (+) is right where my thumb is, and "Empty" drops me into a live workout in about two taps — good, that's the loop I actually want. But the very first thing a preset does is throw a 3-2-1 GO countdown with a screen-filling number in my face. I'm in a gym with 45 minutes, not at a starting block. The Quick Start sheet is also busier than it needs to be: a shortcuts strip, a 2x2 tile grid, AND a "Browse library" link all competing — I just want one fat START button.

**Loved:**
- The inline spreadsheet logger in the Empty/Custom tracker: SET / PREV / KG / REPS with a tick glyph, type the number, hit done on the keyboard and the set is saved. That's the sub-minute loop I came for.
- The PREV column showing my last set right next to the input — no digging through history to remember what I did.
- Center (+) to 'Empty workout' is genuinely ~2 taps to a logging screen; the fast lane exists.
- Presets (Push/Pull/Legs) come pre-loaded with 5-6 exercises and suggested weights, so I'm not building a session from nothing.
- Offline-first actually works — sets queue and sync later, so a dead-signal basement gym won't lose my log.

**Frustrated:**
- The 3-2-1 'GO!' countdown with a 200px font fires on EVERY preset start (_buildCountdown in quick_launch_sheet.dart). That's 3 seconds and a cartoon I can't skip fast, every single session.
- Two completely different logging UIs: the Empty/Custom tracker uses fast inline TextFields, but the PRESET flow (ActiveWorkoutView) makes me edit weight/reps through SetLogDialog which is ALL SLIDERS — dialing 82.5kg on a 0-300 slider is painful vs just typing it.
- The preset flow forces a 90-second rest timer card after every single set and marches one exercise at a time with no reorder/skip. The inline tracker is freeform. Pick a model and commit.
- Adding an exercise from the library (addExercise posts only the id) seems to drop me back with no editable set row, so I hit 'Add set' as an extra tap before I can type anything.
- The Train/Home tab is a wall of cards — Today's Body, vitals, heatmap, weekly bars, performance trend, reminder, streak, XP, coach tip, outdoor, character stats, last workout, steps, motivation. The actual 'start a workout' boxes are up top, but I scroll past a dashboard I never asked for.

**Confused:**
- Two ways to log a set that look and behave totally differently (slider dialog in presets vs inline typing in the tracker) — which one is 'the' way?
- Long-press to pin a FAB default preset is a hidden gesture with no hint in the sheet; I'd never discover it.
- 'Empty' lives as a small chip in a horizontal scroll strip labelled YOUR SHORTCUTS, while the big tiles are named workouts — the fastest option is the least prominent.
- After a preset auto-advances through every exercise and finishes on its own, it's not obvious how I'd add a bonus set or an extra exercise mid-session.

**Top fixes:**
- Make the 3-2-1 countdown skippable instantly (tap-to-skip) or off by default — let me opt into hype, don't force it.
- Use the fast inline typed KG/REPS logger everywhere, including the preset flow — kill the slider SetLogDialog for normal weight/reps entry.
- When I add an exercise, auto-create one empty editable set row so I can type immediately with zero extra taps; and make 'Start empty workout' the single biggest button in the Quick Start sheet.

**Quote:** ""The inline logger is exactly right — now bin the 3-2-1 countdown and the sliders, and stop making me scroll past a fitness magazine to press Start.""

## Andrei, 28 — the Data Athlete (persona C). Lives for e1RM, trends, exports, integrations, and numbers he can verify. — 7/10
_Cautiously impressed — finally an app that shows its math, but I keep reaching for the export button that isn't there._

**First impression:** Opened Progress and actually exhaled. The Training tab isn't a vanity dashboard — it stacks a 30-day training-load trend, daily volume bars, a GitHub-style consistency heatmap, volume progression, a PR timeline, muscle balance and a rest-time trend, then routes each metric into a detail screen. The two top cards (Strength: 'e1RM & PRs', Hall of Fame: 'NNN LP') tell me exactly where the data lives. The segmented control (Training / Nutrition / Health / Body / Biology) is the right taxonomy. This was clearly built by someone who respects data.

**Loved:**
- Strength Analytics screen is the real deal: e1RM hero with an area trend + '+X kg this month' delta, a 'Current PR' card with the date it was set, 'Try Today' computing the next 2.5kg increment, Weekly Tonnage over 8 weeks with a signed % vs prev, and a Personal Records table showing tier + LP per lift.
- The 'What it measures' card on every metric detail literally prints the Epley formula — 'weight × (1 + reps / 30), computed from sets of 1–12 reps' — and explicitly says warm-ups and drop sets are excluded. That is exactly the explainability I distrust most apps for hiding.
- Health/Body metric detail screens disclose the weighting: Strain = workout time 50% / active energy 35% / steps 15%; Recovery = HRV 40% / sleep 40% / RHR 20%, and they reweight honestly when a wearable skips HRV. No black box.
- Honest empty/missing states everywhere — '–' when a vital is missing instead of a fabricated number, and the Health tab comment in code even admits the old version faked 459 kcal / 8,241 steps and was replaced with real data. I trust that.
- Integrations breadth: Apple Health, Health Connect (incl. Galaxy Watch via Samsung Health), and a free Strava OAuth with Sync now / Last synced timestamp / Disconnect. Garmin, Oura, Whoop, Polar, Coros and more are staged behind a Terra aggregator.
- A data export actually exists: Settings → 'Export my data' produces a portable JSON of account, training, social and health data and shares it as a file.

**Frustrated:**
- The e1RM hero shows '142 kg estimated 1RM' but never tells me WHICH set produced it (e.g. 120kg × 5). For a number derived from a formula, not showing the source set means I can't sanity-check it — and I won't trust an estimate I can't reverse.
- The real rank explainability — SR = e1RM / bodyweight, percentile_rank within bw_band + sex, LP math — is only reachable from a bottom sheet AFTER completing a workout (xp_complete_screen). From Hall of Fame or the Strength PR table I see 'Gold tier · 240 LP' with zero 'why'. The getRankExplain endpoint is wired but unreachable from where I'd actually look.
- Weekly Tonnage and most detail bar charts are normalized to 0–100% with no numeric Y-axis. I get a hero number and bar SHAPES, but I can't read week 4's absolute kg off the chart. Give me axis labels or tap-to-read values.
- Export is JSON-only and one giant blob. As the data nerd I want per-metric CSV (e1RM history, set-level log, volume by week) I can drop into a spreadsheet — JSON is a developer artifact, not an athlete's export.
- 'Try Today' just adds a flat 2.5kg to the current PR. That's not data-driven progression — it ignores my recent e1RM slope, RPE, and fatigue. Dressing a constant up as an AI insight ('Try +2.5kg on the bar today') reads as fake precision.
- The Strength e1RM trend caps at the last 12 data points and the x-axis collapses to just 'Start / mid / Today'. I want a full date axis and a selectable range (90d / 6m / 1y / all), not a 12-point window.

**Confused:**
- The Strength Analytics 'Try Today' AI Insight card and the e1RM '+X kg this month' use different reference logic (next 2.5kg increment vs e1RM-30-days-ago) — two cards on the same screen telling slightly different stories about the same lift.
- The Training tab hero says 'Training load · 30 days' in 'kg-reps', but Daily Volume below it says 'kg × reps' and the metric detail uses 'kg-reps' as the unit — three labels for what I think is the same quantity, and none defines it inline.
- Strava is a dedicated free card but the other 11 wearables show 'Coming soon' until a Terra aggregator is configured server-side — as a user I can't tell whether Garmin will ever actually work or if it's permanent vaporware.
- Volume delta on the Training trend is null and hidden when there's <14 days of data, but the Weekly Tonnage card still shows a % vs prev from only 2 weeks — inconsistent thresholds for when a delta is 'trustworthy'.

**Top fixes:**
- Surface the e1RM source set on the Strength hero and PR rows ('142kg est · from 120kg × 5 on 12 Jun') and make the full rank explain (SR, bodyweight, percentile within your bw_band + sex, LP math) tappable directly from Hall of Fame and the PR table — not just from the post-workout sheet.
- Add per-metric CSV export (set-level log, e1RM history, weekly volume) and selectable chart date ranges with a readable numeric Y-axis / tap-to-read values on the bar charts.
- Make 'Try Today' genuinely data-driven (use recent e1RM slope + RPE/fatigue, show the reasoning) and unify the volume unit label + define 'kg-reps' inline once.

**Quote:** ""You showed me the Epley formula on the screen — I almost cried. Now show me which set made the number and let me export it to a spreadsheet, and I'm yours.""

## Elena, 45 — the Returner (persona E). Back in the gym after years away, scared of re-injuring her lower back and knee. Wants gentle, guided, "tell me I'm not overdoing it" reassurance more than leaderboards. — 6/10
_Hopeful but holding the handrail — "I want to be coached back, not thrown back."_

**First impression:** The onboarding is calm and pretty, and the very first thing it asks — "Where are you now?" with "Beginner · New or returning" — made me feel seen for about ten seconds. Then it just collected my age/height/weight and spun a lovely "Building your plan" animation (Analyzing your goal, Calibrating training load, Designing your nutrition...). Nowhere did it ask the one thing I most needed to say: that I have a bad back and haven't trained in years. I clicked "Get stronger" and "Beginner" and it felt like it filed me next to a 19-year-old. The home/Train screen is dense — Today's body, vitals, an 8-week heatmap, performance volume charts — beautiful, but a lot of numbers thrown at someone who just wants to know "is today okay to train?"

**Loved:**
- The AI coach (ai_chat_screen.dart) literally suggests 'Am I recovered enough to train?' as a starter chip, and its replies surface a 'Risks to watch' section — this is the reassurance I came for.
- 'Today's body' card with Strain / Recovery / Sleep rings and an honest 'No data yet' state instead of a fake score — when recovery is low it actually says 'Your body needs rest. Skip the gym today.' That's a coach that lets me rest.
- The low-sleep insight in the recovery logic spells out 'Very little sleep. Heavy training today carries extra injury risk' — exactly the kind of warning that keeps me from hurting myself.
- Quitting a session is safe and guilt-free: the exit sheet offers 'Save & exit · Resume later', 'Complete workout', and 'Discard' — I never feel trapped mid-workout.
- Offline-first logging ('Saved offline — will sync when back online') means a flaky gym signal won't lose my sets or stress me out.
- The AI workout sheet explains 'Why this exercise' per movement and admits 'Starting weights are AI estimates — fine-tune them in the tracker', so nothing feels like a black box.

**Frustrated:**
- There is NO place to tell the app about my injuries. The data model and AI service have an 'injuriesLimitations' field (training_profile_models.dart, ai_chat_service.dart), but no screen ever collects or lets me edit it — so my bad back is invisible to the 'personalized' plan unless I happen to type it into chat.
- The Quick-start presets are genuinely scary defaults: Pull Day opens with Deadlift 140kg, Leg Day with Back Squat 120kg, Push Day Bench 80kg. For a returner those numbers aren't aspirational, they're a warning sign — and tapping a tile drops straight into a 3-2-1 countdown to 'GO!' at those loads.
- Nothing warns me when I log something dangerous. The set logger (set_log_dialog.dart) is just sliders to 300kg with an optional RPE; there's no 'that's a big jump from last time, are you sure?' confirmation, no deload prompt, no first-week-back easing — even though the project's own rules call for a confirm + note when weight is way above history.
- The whole Train tab pushes streaks and 'Streak at risk' / 'Pick it back up' nudges based on POSTING. As someone easing back twice a week, being told my streak is in danger makes me feel like I'm already failing.
- Experience picker lumps 'New or returning' into one 'Beginner' bucket — a nervous 45-year-old comeback and a total newbie get the same calibration, and there's no 'I'm coming back from a long break / time off' path.
- 'GO!' countdown, 'Press heavy', 'Push hard today', 'Grind it', 'Full send' taglines everywhere — the tone is built for the gamer persona, not for someone whose goal is to not get hurt.

**Confused:**
- Onboarding promised the plan was 'Tailored to everything you told us' and 'Calibrating training load' — but I never told it anything about my body's limits or history, so what exactly did it calibrate?
- Are the preset weights (140kg deadlift) MY suggested starting weights or just generic placeholders? The tile gives no hint, and the countdown starts before I can check.
- Where do I even enter that I have a back issue? I looked through onboarding and didn't find it; apparently I have to discover the AI chat and say it out loud.
- The performance card flips between '30D/3M/1Y' and says 'improving' or 'pulling back' — for a returner with almost no data, is 'pulling back' judging me already?
- Does the recovery 'Rest day · Skip the gym today' advice actually stop me, or is it just a label while every other card still nudges me to train and protect my streak?

**Top fixes:**
- Add an injuries/limitations step in onboarding (the 'injuriesLimitations' field already exists — just collect it) and make it editable in settings, so the plan and AI actually account for my back and knee.
- Replace the heavy hard-coded preset weights with conservative, history-aware starting loads for beginners/returners, and add a safety confirmation when a logged weight is a big jump from my recent best.
- Give returners a real 'easing back in' path: a distinct option beyond 'Beginner · New or returning', a gentle first-weeks deload, and reassurance messaging instead of streak-at-risk pressure.

**Quote:** ""It keeps telling me to 'press heavy' and 'full send' — but it never once asked about my back. I came here to be eased in, not egged on.""

## Robert, 17 — intimidated first-timer who's never trained and doesn't know the gym words — 6/10
_Excited to start but quietly panicking that everyone else got a manual I didn't._

**First impression:** The sign-up felt friendly and not scary — it asked if I'm a "Beginner (New or returning)" which made me feel seen, and the "Building your plan" animation got me hyped. Then I landed on the Train screen and my stomach dropped. There's a card called "Today's body" with Strain, Recovery, HRV, a "Performance · volume · 30d" chart in kg, a heatmap, "Character stats"... I don't know what ANY of that means. It looks like a cockpit and I just wanted to know "what do I do at the gym today."

**Loved:**
- The AI Workout pop-out is the only thing that talked to me like a human — every exercise has a little 'Why this exercise' box tied to my goal, and the weight tag has a tooltip saying 'AI estimate from your bodyweight & training level'. That made me trust it.
- The line 'Starting weights are AI estimates — fine-tune them in the tracker' under the AI workout — finally something that says it's OK if the number is wrong for me.
- Onboarding used plain words: 'Build muscle / Lose fat / Get stronger / Improve health' and 'Beginner — New or returning'. No jargon there.
- The AI Coach chat greets me with 'Hey, I'm your Zvelt coach' and has a tappable chip 'Review my bench form' — knowing I can just ASK is a relief.
- The exercise detail page actually has a reference GIF button, plus MUSCLES, MOVEMENT, INSTRUCTIONS and even CONTRAINDICATIONS — that's exactly the hand-holding I need.

**Frustrated:**
- The set-log popup has a slider labelled just 'RPE (optional)' from 1 to 10 with zero explanation. I have no idea what RPE is, so I leave it blank and feel like I'm doing it wrong.
- The Quick start presets are terrifying: 'Push Day' prescribes 'Bench Press 4 × 6-8, 80 kg' and 'Pull Day' has 'Deadlift 140 kg'. 80kg bench would flatten me. The numbers aren't adjusted to a beginner — they look like a strong adult's program.
- Preset weights use codes I don't know: 'BW', '+15 kg', 'Incline DB Press', 'RDL / Romanian Deadlift', 'Face Pull'. No glossary, no pictures on that screen — just gym slang.
- During the actual live workout (the countdown 3-2-1-GO screen and tracker) there's no 'How do I do this?' / 'show me the form' button next to the current exercise. The GIF lives on a separate detail screen I have to go hunting for, and I'm mid-set.
- The whole Train home screen is a jargon avalanche: Strain, HRV, RHR, e1RM, 'Performance · volume · kg', 'lp_total'-style ranking stuff. Most of it has no tap-to-explain, so it just makes me feel dumb.
- Progress/analytics is full of 'e1RM' and 'estimated one-rep max' — even the explanation uses more jargon ('Epley', 'working sets 1-12 reps'). I can't tell if I'm improving in normal-person terms.

**Confused:**
- What is RPE? The slider gives me no clue.
- What does 'BW' and '+15 kg' mean next to Pull-Ups and Dips?
- What's 'e1RM' and why is it all over my Progress tab?
- Are those preset weights (80kg bench, 140kg deadlift) meant for ME, or just examples? Nothing says.
- What is 'Strain' and 'HRV' on the Today's body card, and do I need a watch for it to work?
- The streak says it's 'based on posting (up to 3 days between posts)' — so do I lose my streak if I work out but don't post? That's confusing.

**Top fixes:**
- Add a tiny 'What's this?' info tap on RPE (and e1RM, Strain, HRV) that explains it in one plain sentence — e.g. 'RPE = how hard it felt, 1 easy to 10 all-out. Skip it if unsure.'
- Make preset/AI starting weights scale to my onboarding level — a Beginner should NOT be shown 80kg bench / 140kg deadlift. Show a beginner-safe number or 'start light, we'll adjust.'
- Put a 'Show me how' / form-GIF button right next to the current exercise INSIDE the live workout, so I don't have to leave the session to learn the move.
- Give a first-time-user 'guided mode' or a 1-screen 'here's what to do today' instead of dumping the full data cockpit (heatmap, HRV, volume charts) on a brand-new account with no data.

**Quote:** ""The AI workout finally explained WHY I'm doing each exercise — but then it told me to bench 80kg and asked me my 'RPE', and I closed the app to go Google what that even means.""

## Dragoș, 31 — The Competitor (persona H). Lives for leaderboards, tiers, fairness and anti-cheat. Reads every number with one question: can someone fake this to beat me? — 5/10
_Leaning forward, screenshotting the leaderboard, already trying to figure out how to log 24,000kg of "volume" without touching a barbell._

**First impression:** The tiers (Iron → Olympian), LP totals, the Hall of Fame podium and the season leaderboard hooked me instantly — this is built for people like me. There's a real /leaderboard/season call, a top-3 podium, my row highlighted 'YOU', and even +/- rank deltas. But the second I started poking, the competitive credibility started leaking. I can see WHERE I rank, but almost nothing about WHY the number is what it is, and nothing at all about whether anyone else's number is honest.

**Loved:**
- Real season leaderboard in Hall of Fame: /v1/leaderboard/season with a proper podium (2nd-1st-3rd staggered), my 'YOU' row tinted, and green/red rank-delta pills (+3 / -2). That's the loop I want.
- Tier ladder is explicit and consistent everywhere — Iron, Bronze, Silver, Gold, Platinum, Diamond, Olympian — and LP is shown as a total AND per-lift, with lpInTier (LP % 100) so I can see how close I am to promotion.
- Bodyweight is GATED: 'Add bodyweight to unlock ranks' banner (BW_REQUIRED). Good — a strength-ratio leaderboard that didn't force bodyweight would be a joke, so I respect that they block ranking without it.
- There IS an explain endpoint (/ranks/exercises/:id/explain) and it returns a next-tier target like 'Hit ~140kg × 5 to reach Gold · 60 LP left'. That's exactly the carrot a climber wants.
- Segment leaderboards for runs (segments/:id/leaderboard) with my best time and dates — real times, real ranking, and the splits table comment even mentions an anti-cheat route. Promising.

**Frustrated:**
- Race Hub standings are SELF-LOGGED. _logProgress(amount) just takes whatever number I type in the log sheet and adds it to my total, then auto-posts '⚡ Logged X reps — now #1' to the pack. There is zero link to actual logged workouts or verification. I can 'win' a 24,000kg volume race from my couch. For a competitor this isn't a race, it's an honor system — and I will absolutely exploit it.
- No anti-cheat is visible ANYWHERE. CLAUDE.md promises anomaly flags on >20% SR jumps, audit logs, edit caps, and a 'trusted tier' for >30-day accounts on the seasonal board — but on the leaderboard I see no 'verified' badge, no flag icon, no trusted indicator. I have no way to know if the guy above me is a 3-day-old smurf who claimed a 300kg bench.
- The 'why' is half-built. The explain sheet only opens from the post-workout XP screen (xp_complete_screen). I cannot tap my own tier badge, a PR row, or anyone's leaderboard line to ask 'why this rank?'. The actual formula — e1RM (Epley), SR = e1RM/bodyweight, percentile → LP — is never shown to me. I'm told a rank; I'm not shown the math.
- The leaderboard quietly fakes itself. If /leaderboard/season returns empty, Hall of Fame silently swaps to 'YOUR TOP LIFTS' with a little 'PERSONAL' pill where the global board should be. A competitor glancing at it could think they're #1 globally when it's just their own 5 lifts sorted. That's a trust-killer.
- Only the top 8 ever load (limit:'8'), with no 'view full leaderboard', no pagination, and no 'your position' row if I'm rank #40. The whole point of climbing is seeing who's just above me — I can't.
- No season context on the board. The card says 'YOUR SEASON STATS' but there's no season name, no countdown to the 4-month reset, no 'trusted/seasonal' distinction. I don't know what window I'm even competing in.

**Confused:**
- Is the Hall of Fame board global, friends-only, or my bodyweight band? The percentile is supposed to be per exercise_id + bw_band + sex, but the UI gives no scope label at all — I can't tell who I'm being ranked against.
- Race standings show a rank ring and 'g reps behind the leader', but since totals are self-reported I don't know if 'the leader' actually did anything. Real competition or vanity numbers?
- The explain sheet talks about 'strength ratio vs peers' but never shows my SR, my percentile, or the peer pool size. Which peers? How many?
- Honor Badges like 'Top 5%' unlock purely off my own max tier (Gold+), not an actual percentile — so 'Top 5%' might be a lie relative to the real population.
- Tier on a leaderboard row defaults to 'Iron' when the field is missing — is that a real Iron lifter or just a null I'm reading as Iron?

**Top fixes:**
- Make races verifiable: tie race progress to actually-logged WORK sets (the same e1RM/volume pipeline), not a free-text amount sheet. Self-reported standings make the whole competitive feature worthless to a serious competitor.
- Surface anti-cheat to users: a 'Verified' / 'Trusted (30d+)' badge on leaderboard rows and an 'anomaly under review' flag on suspicious jumps. If the server enforces it (as CLAUDE.md claims), SHOW it — fairness invisible is fairness distrusted.
- Make 'why' tappable everywhere and show the real math: tap any tier badge / PR / leaderboard row to get e1RM (Epley), SR = e1RM/bodyweight, your percentile, the bw_band + sex scope, and LP-to-next-tier. Don't hide the formula from the people who care most about it.

**Quote:** ""I can already win your race from my couch — I just type 24,000 into a box. Give me a leaderboard I can't fake, tell me who I'm actually ranked against, and show me the math. Until then this is a vanity board, not a competition.""

## Bianca, 26 — the Social Butterfly (persona F). A workout isn't real until it's posted; lives for the feed, stories, races, and friend energy. — 7/10
_Buzzing but a little lonely — the room is gorgeous, I just can't find anyone to invite._

**First impression:** Okay the Feed tab actually GETS me. The header says 'YOUR TRIBE · X TRAINED TODAY' over a clean 'Feed' title, there's a stories rail right at the top with my own dashed 'You' add-bubble, a 'Race of the Week' hero, active challenges, then the community feed with a glowy '+ POST' button. Trending/Friends toggle, All/Following/Popular/Races pills. This is a real social app, not a spreadsheet with a like button bolted on. I felt at home in two seconds.

**Loved:**
- Stories that build THEMSELVES — the add-story sheet has PR / Workout / Quote presets that pull my real last PR (exercise + kg × reps), my last session, and a daily quote into a 1080×1920 gradient card. I can post a flex without a photo. Chef's kiss.
- Story viewer is proper: tap-to-advance, a 'Reply to <name>…' bar that lands in their DMs, and a heart that's a real server-backed like with a count. That's the Instagram loop I need.
- Races are a whole vibe — 'Race of the Week' hero with real overlapping participant initials + '+N', a Build-a-Race configurator (Lift/Run/Bike/Body, Volume/Reps/etc., duration slider, public/friends), live Standings with medal colors, and a race chat with quick-reply chips and an emoji picker (🔥💪🏆). Logging progress auto-posts '⚡ Logged 50 reps — now #3' to the pack. SO competitive, I love it.
- Privacy is shown, not hidden — every post card wears a PUBLIC/FRIENDS/PRIVATE pill with a tooltip, and posting defaults to Friends. I actually trust where my stuff goes.
- Comments, likes (optimistic with a revert), bookmarks, hide/report/block — the full social toolkit is here and the empty states are friendly ('No comments yet', 'Create a photo post to fill your feed').

**Frustrated:**
- SHARING IS FAKE. Both the share icon on every post AND 'Share post' in the menu just copy a 'zvelt://post/<id>' link to the clipboard and toast 'Link copied!'. There is no native share sheet — I can't fire a post to my Instagram story, WhatsApp group, or TikTok. For a social butterfly that's the whole point, and a 'zvelt://' link does nothing if my friend doesn't have the app yet.
- My beautiful auto-generated stories are trapped. I can compose a gorgeous PR card but there's no 'Share to Instagram' on it — it only publishes inside Zvelt. That's exactly the asset I'd want to post EVERYWHERE, and it's locked in the garden.
- Finding people is painful. Friends > Find only does exact-ish username search (min 3 chars, matches the START of a username), and it literally tells me 'Try fewer characters.' There's no Explore, no suggested friends, no contacts import, no 'people in your races'. If I don't already know someone's exact handle, I can't add them.
- I can't see who viewed or hearted my story. The viewer shows others' like counts but there's zero 'seen by' / viewers list on my own — half the dopamine of stories is gone.
- The 'Race Hub > Race settings' is hollow: it admits per-race notifications and 'leave this race' aren't shipping, so the gear only offers 'Refresh' and a generic 'Share Zvelt'. And 'Share race link' shares a hardcoded https://zvelt.app, not THIS race — I can't actually invite my crew to a specific race.
- The 'Race of the Week' hero is just the NEWEST challenge (there's even a TODO admitting it's not really trending), so the headline act of my social screen can be some random race nobody's in — subtitle literally reads 'Be the first to join'.

**Confused:**
- The 'Races' pill in the feed filter row isn't a filter at all — it secretly navigates me out to the Race Hub instead of filtering my feed to races. The other three pills filter in place. I tapped it expecting race posts and got teleported.
- There are TWO ways to reach my friends — a 'circle' button (gradient users icon with a green dot) in the Feed header AND a Friends screen — and it's not obvious the Circle is just my friends-with-streaks list vs Friends being search/requests/DMs.
- Race chat is described internally as 'Notes' / a notepad in some places but 'Chat' in the tab — am I talking to the pack or to myself? (It IS server-backed now, but the leftover 'notes' language made me unsure if anyone would see my 🔥.)
- The share icon and the bookmark icon use the same glyph whether active or not (the code passes the same icon for liked/unliked, saved/unsaved) — only the color changes, so at a glance I can't always tell if I already saved or liked something.

**Top fixes:**
- Wire up REAL native sharing — a system share sheet on posts AND on generated story images, with deep links that open a web preview for friends who don't have the app yet. Stop copying a dead zvelt:// link.
- Give me a way to FIND people: an Explore/Suggested-friends tab, contacts/Instagram import, and 'add the athletes in my race' — exact-username search alone strands a social user.
- Add 'Seen by / viewers' and reaction lists to my OWN stories and posts. Show me who's looking; that's the fuel.
- Make race invites real: per-race share links + invite-friends from the Race Hub, and make 'Race of the Week' actually pick the trending/most-joined race, not just the newest.

**Quote:** ""The feed, the stories, the races — it's all dressed up gorgeous and ready to party. But the front door's locked: I can't share OUT and I can't find new friends to bring IN. Fix that and I'm posting from this thing every single day.""

## Vlad, 35 — the privacy-paranoid (persona G). Reads every permission, wants private-by-default, real export, real deletion, explicit consent for health data, minimal data leaving the device. — 7/10
_Suspicious but slowly disarmed — I came to catch them harvesting my data and instead found a hard-delete transaction and a consent ledger. Still side-eyeing the gaps._

**First impression:** I went straight to Settings, not Train. The Privacy section (Profile visibility, Blocked users) and a Data section with "Export my data" and "Health & devices" are right there — not buried. Then I dug into the actual delete flow at settings/delete_account_screen.dart and it's the best I've seen: a red "This is permanent" banner, an itemized "What gets deleted" list (profile, all workouts, posts, social graph, health data cache, subscriptions), a literal "Type DELETE to confirm" field, and a 3-row timeline ("Now / Within 30 days / Anonymous aggregate statistics may be retained"). And it's not theater — the backend gdpr.ts actually runs a full children-before-parents hard-delete transaction (eraseUser) and the DELETE route re-checks the DELETE confirmation server-side, not just client-side. That earns real trust.

**Loved:**
- Account deletion is REAL: DELETE /v1/me/account in backend/src/routes/gdpr.ts hard-deletes the whole row tree in one transaction (rolls back if any step fails, so no orphans), revokes external integrations first, and scrubs on-disk avatars/post/story files. DMs are tombstoned to '[deleted user]' instead of nuking the other person's thread — thoughtful.
- Server-side confirmation guard: typing DELETE isn't just a client gate; the route rejects anything but 'DELETE' with CONFIRMATION_REQUIRED. A stray API call can't wipe me on one token.
- Privacy IS default-on: ProfileVisibilityScreen loads privacyDefault='friends', and BOTH _discoverable ('Discoverable in search') and _diagnostics ('Enable diagnostics') default to FALSE. Discovery is genuinely opt-in, exactly as it should be.
- Export is genuine portability: GET /v1/me/export-data returns formatVersion 2 with workouts, posts, DMs, health imports, GPS routes AND a media manifest — and the code comment + select list intentionally EXCLUDE password hashes and refresh tokens. Sent with Cache-Control: private, no-store.
- Health consent has a real audit trail: backend keeps an append-only healthConsentEvent ledger (GDPR Art.7) per data type, and health_service.dart writes a consent record the moment OS health access is granted.
- Logout actually wipes the device: auth_service _clearTokens deletes Keychain/EncryptedSharedPreferences entries AND prefs.clear() — tokens live in secure storage, not plain prefs.
- Notifications and the FCM permission request in onboarding (ScrNotifications) genuinely respect 'Not now' — denial advances, the flow never blocks or nags, and notifications default sensibly (Nutrition off).
- Privacy Policy text says the right things: 'We do not sell personal health data or use private health records for third-party advertising,' and lists access/correct/export/delete + withdraw health/discovery/diagnostic consent.

**Frustrated:**
- The granular health consent is a LIE OF OMISSION at the UI layer. The backend supports per-type consent (steps, heart_rate, sleep, hrv, blood_oxygen, etc.) but health_service.dart only ever sends {consentType:'all', granted:true}. So when I tap Connect on Apple Health/Health Connect, it's all-or-nothing — I can't grant steps but deny HRV, even though the server is built for it.
- There is NO in-app screen to VIEW or REVOKE my health consents. GET /v1/me/health-consents exists in the backend but nothing in app/lib reads it except the writer. The only 'revoke' is Disconnect on the IntegrationsScreen, which is coarse. For a health app that's a real gap.
- Onboarding collects sensitive data (sex, age, height, weight, goal free-text) on ScrBiology/ScrProfile and the personalization flow has ZERO privacy notice or consent checkpoint before it 'syncs to backend' on ScrBuilding. It says 'Tailored to everything you told us' but never 'here's what we store / here's the policy' at the moment of collection.
- Cloud sync screen shows '1.8 GB of 5 GB used' and the onboarding mosaic claims '248k Members / 63 Countries' — these are hardcoded fake numbers (the discovery file literally comments they're 'demo illustrations'). A privacy person reading fabricated stats in a shipping UI immediately distrusts EVERY other number on screen.
- 'Send logs to developer' fires FirebaseCrashlytics.sendUnsentReports() with one tap and a cheerful snack — no preview of WHAT is in those logs before they leave my device. Same with diagnostics: flipping it on enables Crashlytics collection silently.
- Profile photo upload base64-encodes my image and POSTs it to /me/avatar with no mention of where it's stored or that it becomes a public URL (it does — mediaAbsoluteUrl). Avatar/post images are served from /uploads/* URLs that the export manifest resolves; nobody told me my face is at a guessable-ish static URL.
- Two-factor authentication shows 'Not set' and tapping it just snacks 'requires the secure backend challenge flow' — i.e., it doesn't exist yet. For an account holding my health data, no 2FA is a security hole, not a 'coming soon.'
- The deletion timeline note 'Anonymous aggregate statistics may be retained' is vague — which stats? derived from what? A paranoid user wants that pinned down, and analyticsEvent IS deleted in eraseUser, so the wording undersells how clean the delete actually is.

**Confused:**
- Why does Profile visibility have BOTH a 'Friends only' radio AND a separate 'Show activity feed' / 'Show body stats' / 'Discoverable in search' toggle set? The interaction between 'Private (nothing shared to feed)' and 'Show activity feed = on' is unclear — does Private override the toggle or fight it?
- The privacy settings save to BOTH the backend (updateSettings) AND local SharedPreferences mirrors (showStats/showActivity/discoverable). If those drift, which one wins? As the paranoid user I can't tell if my 'discoverable = off' is actually enforced server-side.
- Settings shows 'Health & devices: N connected' but the count quietly includes native HealthKit/Health Connect permission state mixed with backend OAuth integrations — so the number doesn't map cleanly to 'things that have my data.'
- There's a soft-delete flag (ZVELT_SOFT_DELETE) that, when on, keeps ALL my data for a 30-day recoverable window instead of erasing immediately. The UI says 'queued for permanent deletion... within 30 days' either way, so I can't tell whether my data is gone NOW or sitting recoverable for a month.

**Top fixes:**
- Wire the granular per-type health consent the backend already supports: a dedicated 'Health data permissions' screen that reads GET /me/health-consents and lets me grant/revoke steps, heart_rate, sleep, hrv, etc. individually — instead of the client hardcoding consentType:'all'.
- Add an explicit data/privacy consent checkpoint in onboarding at the moment sensitive biology data is collected (ScrBiology/ScrBuilding): a short 'what we store + link to Privacy Policy' the user must acknowledge before the backend sync fires.
- Remove or clearly label every fabricated number (Cloud '1.8 GB of 5 GB', mosaic '248k members') — show real values or nothing. Fake stats in a live UI destroy trust in the real privacy guarantees.
- Before 'Send logs to developer' and when enabling diagnostics, show exactly what's collected and let me review/decline — no silent Crashlytics uploads.

**Quote:** ""The delete button is the most honest one I've ever tapped — it actually deletes. But don't tell me I 'consented' to my heart-rate data when the app only ever asks for 'all,' and don't show me a fake '248k members' counter and expect me to believe your privacy policy.""

## Doru, 42 — the AI-coach purist. The whole point is: tell the AI a goal, it gives you exercises, you log, it adapts and tells you WHY. Everything else is noise. — 6/10
_Impressed the coach actually exists and reasons — furious it's buried under a theme park of side-features._

**First impression:** I open Train and — finally — the top of the screen is "AI Workout · Built for your goal" as the dominant glowing CTA, with Custom Workout demoted underneath, and a "Set a new goal" pill right below. That's the right hierarchy. The AI sheet loads a real recommendation: each exercise carries a "why this exercise" line tied to my goal, plus a weight badge that honestly says whether it's from my history (green clock) or an AI estimate (sparkle). That is exactly the loop I want. But then I look at the bottom nav and the rest of the app and my heart sinks — Train, Progress, Feed, Nutrition tabs, plus a quick-launch with Push/Pull/Legs/Cardio tiles, a library, races, circles, DMs, gallery, hall of fame, journal, biology, barcode scanner... the coach is one room in a 70-screen funhouse.

**Loved:**
- The goal->session->why chain is REAL, not decoration: getWorkoutSuggestion returns per-exercise whyThisExercise tied to my goal text, and the card renders it in a brand-tinted bullet. This is the explainability I came for.
- Adaptation actually closes the loop. The weight badge's weightSource is 'history' vs 'heuristic'/'bodyweight', and the load carries loadSource 'progression'|'hold'|'no_history' with a 'why this load?' reason. So logging a set genuinely feeds the next suggestion — that's a coach, not a generator.
- Goal Evolution flow (goal_evolution_flow.dart) nails it: I rewrite my goal, it PATCHes it, regenerates the weekly plan with previousGoalText, and shows a BEFORE->AFTER card plus a 'COACH'S NOTE ON THE CHANGE' rationale. Adapt-and-explain, exactly.
- Honesty in the copy: 'Starting weights are AI estimates — fine-tune them in the tracker', and the AI chat seed explicitly says it can read my profile/training/recovery but does NOT claim to have 'already analyzed' anything. A coach that doesn't lie about what it knows earns trust.
- The chat (Coach Zvelt) structures replies into Next session focus / Risks to watch / 7-day micro plan, and askTrainer with createWorkout:true can spin up a workout and drop me straight into the tracker. That's the dream path.

**Frustrated:**
- The coach has no home of its own. 'Coach Zvelt' chat (ai_chat_screen.dart) is NOT in the bottom nav — it's hidden behind the center (+) quick-launch as an 'AI workout' shortcut chip, and buried in the profile tab. The single most important feature is a shortcut, while Feed and Nutrition get permanent tabs.
- The quick-launch Push/Pull/Legs presets are HARDCODED dumb templates: 'Bench Press 4x6-8 80kg', 'Deadlift 4x5 140kg' baked into _kAllPresets for everyone regardless of goal, level, or history. That is the anti-coach — a beginner who taps the prominent Push tile gets an 80kg bench with zero adaptation and zero 'why'. It directly competes with and undermines the real AI workout.
- Feature buffet confirmed: 70+ screens — barcode meal scanner, biology tab, journal, segment leaderboards, race hub, circles, DMs, conversations, gallery, bookmarks, photo progress, hall of fame, achievements. Every one of these is attention stolen from the coach. The home Train tab itself is an endless scroll of ~15 cards (recovery rings, vitals, heatmap, weekly bars, performance trend, reminder, streak, XP bar, coach tip, outdoor run, character stats, last workout, steps, motivation quote) before I even feel coached.
- The free-text goal — the thing the ENTIRE engine keys off — is an OPTIONAL field ('In your words (optional)', placeholder 'Bench 100kg by summer') tucked under four canned goal chips in onboarding step 2/6. If a user skips it, the coach is reasoning off a one-word enum. The most load-bearing input is treated as a throwaway.
- Coach tip card silently renders nothing if no plan exists, and the AI workout/chat are the only places the goal surfaces day-to-day. Outside the AI sheet there's no persistent 'here's your goal and today's prescribed session because X' — I have to go dig for the coach every time instead of it greeting me.

**Confused:**
- Two parallel workout systems with no relationship: the adaptive AI Workout sheet vs the hardcoded preset ActiveWorkoutView from quick-launch. Which one is 'the app'? They don't share logic — the preset path never asks the AI anything.
- 'AI workout' in the quick-launch shortcuts actually opens the CHAT screen (case scAi -> AiChatScreen), but the Train tab's 'AI Workout' button opens the SUGGESTION SHEET. Same label, two different destinations. Which is the AI workout?
- The recovery card tells me 'Ready to train / Push hard today' or 'Skip the gym today' — but does that recovery state actually change what exercises the AI prescribes, or is it a separate widget that the coach ignores? I can't tell that the rings feed the suggestion.
- Is the daily motivation quote ('Track it, adjust it, own the process' — Zvelt Coach) coming from the same coach brain, or is it just a decorative quote generator wearing the coach's name?

**Top fixes:**
- Give the coach a permanent bottom-nav tab. Coach Zvelt (chat + today's prescribed session + goal + the 'why') should be the center of the app, not a shortcut chip behind the (+). Demote Feed or Nutrition before you demote the coach.
- Kill or rebuild the hardcoded Push/Pull/Legs presets. Either route those tiles through the same goal/history-aware engine that powers AI Workout, or remove them. A static 80kg bench template for everyone is the opposite of coaching and it dilutes the one thing you do well.
- Make the free-text goal mandatory and central, and surface it everywhere. The whole engine reasons off goalText — stop hiding it as 'optional' under canned chips, and put 'Your goal -> today's session because X' persistently on the Train screen, not buried in the AI sheet.
- Ruthlessly trim the buffet. Barcode scanner, biology tab, journal, segments, races, gallery, circles — every side-feature should justify itself against 'does this make the coach coach better?' Most don't. Fold the survivors behind the coach instead of scattering them across 70 screens.

**Quote:** ""The coach inside this app is genuinely good — it reasons, it adapts off my history, it tells me why. So why have you hidden it behind a (+) button and surrounded it with a barcode scanner and a photo gallery? Build the app the coach deserves, not a fitness theme park with the coach working a side booth.""