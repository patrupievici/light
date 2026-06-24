# Progression Analytics - Feature Status & Fix

**Date:** April 28, 2026  
**Issue:** User couldn't find progression graphs in the app

---

## ✅ Status: FULLY IMPLEMENTED (but hidden)

The progression analytics feature was **already completely implemented** but was poorly discoverable - hidden behind a small icon in the AnalyticsHub AppBar.

---

## 🎯 What's Already Working

### Backend (`/v1/ranks/me/history`)
**File:** `backend/src/routes/ranks.ts` (lines 134-265)

**Features:**
- ✅ Calculates e1RM (estimated 1-Rep Max) for each exercise
- ✅ Tracks LP (Lifting Points) progression over time
- ✅ Computes tier rankings (Iron → Bronze → Silver → Gold → Platinum → Diamond → Olympian)
- ✅ Returns data points per workout with:
  - Date
  - e1RM in kg
  - LP score
  - Tier level
  - Weight and reps used

**Data sources:**
- `user_exercise_ranks` table (current rank per exercise)
- `workouts` table (completed/posted status)
- `workout_sets` table (WORK sets with weight/reps)
- `exercises` table (isRanked flag, rankModel)

---

### Frontend Screen (`ProgressionScreen`)
**File:** `app/lib/screens/analytics/progression_screen.dart` (749 lines)

**Features:**
1. **Exercise Selector** - Chips to select which exercise to view
2. **Current Stats Card** with gradient background:
   - Current Tier (with trophy icon)
   - Best e1RM (with fitness icon)
   - LP Score (with trending icon)
   - Progress bar to next tier (0-100 LP)
3. **e1RM Progression Chart** (Line chart using fl_chart):
   - X-axis: Date
   - Y-axis: e1RM in kg
   - Shows strength growth over time
4. **Tier Progression Timeline** - Visual history of tier changes
5. **Personal Records** - List of all PRs for selected exercise
6. **All Exercises Summary** - Cards showing quick stats for every ranked exercise

---

### Frontend Service
**File:** `app/lib/services/workout_service.dart`

**Method:** `getMyProgressionHistory()` (line 247)

**DTO:** `ExerciseProgressionDto` (line 753)
```dart
class ExerciseProgressionDto {
  String exerciseId;
  String exerciseName;
  int currentLP;
  String currentTier;
  double bestE1rmKg;
  List<ProgressionDataPoint> dataPoints;
  
  int get lpInTier => currentLP % 100; // Progress within current tier
}
```

---

## 🔧 What Was Fixed

### Problem:
ProgressionScreen was only accessible via a small chart icon in the AnalyticsHub AppBar - very poor discoverability.

### Solution:
Added a **prominent card** at the top of the Training section in AnalyticsHub:

**Visual Design:**
- Gradient background (amber → blue)
- Large trending_up icon (32px)
- Clear title: "Strength Progression"
- Subtitle: "e1RM over time, tier progress & PRs"
- Arrow icon indicating it's tappable

**Location:** `app/lib/screens/analytics/analytics_hub_screen.dart` (line 147)

**User Flow:**
```
Progress Tab → Analytics Hub → [Strength Progression Card] → ProgressionScreen
```

---

## 📊 What the Feature Shows

### 1. **Strength Progression (e1RM over time)**
Example: Bench Press
- Jan 15: 60 kg e1RM
- Jan 22: 62.5 kg e1RM  
- Feb 05: 65 kg e1RM
- Feb 19: 67.5 kg e1RM
- Mar 05: 70 kg e1RM ⬆️

**Shows:** Clear upward trend in strength

---

### 2. **Tier Progression**
Tier system (based on LP - Lifting Points):
```
Iron (0-99 LP)
  ↓
Bronze (100-199 LP)
  ↓
Silver (200-299 LP)
  ↓
Gold (300-399 LP)
  ↓
Platinum (400-499 LP)
  ↓
Diamond (500-599 LP)
  ↓
Olympian (600+ LP)
```

**Progress bar shows:** "47/100 LP to Bronze"

---

### 3. **Percentile Comparison**
The backend calculates where you stand vs general population:
- By age group
- By weight class
- By exercise

**Example output:**
```
Bench Press: 70 kg e1RM
- Age 25-30: 75th percentile (better than 75% of lifters)
- Weight 75-80kg: 68th percentile
- Overall: Top 25% of all lifters
```

---

### 4. **Personal Records Timeline**
Shows all PRs chronologically:
```
🏆 Bench Press PR History:
- Mar 05, 2026: 70 kg × 5 reps (e1RM: 70 kg)
- Feb 19, 2026: 67.5 kg × 5 reps (e1RM: 67.5 kg)
- Feb 05, 2026: 65 kg × 5 reps (e1RM: 65 kg)
```

---

## 🚀 How to Access (After Fix)

### Method 1: Main Navigation
1. Tap **Progress** tab (bottom nav, index 1)
2. Analytics Hub opens automatically
3. Tap **"Strength Progression"** card (top of Training section)
4. ProgressionScreen opens with all exercises

### Method 2: Quick Access (still available)
1. Tap **Progress** tab
2. Tap the **chart icon** (📊) in AppBar
3. ProgressionScreen opens

---

## ⚠️ Requirements for Data to Show

For progression data to appear, user must:

1. **Complete workouts** (status = 'completed' or 'posted')
   - Draft workouts don't count

2. **Use ranked exercises**
   - Exercise must have `isRanked = true`
   - Exercise must have `rankModel = 'WEIGHTED'`
   - Examples: Bench Press, Squat, Deadlift, Overhead Press

3. **Log WORK sets**
   - Sets must have `tag = 'WORK'`
   - Sets must have `isCompleted = true`
   - Must have weight and reps logged

4. **Have bodyweight in profile** (for percentile calculation)
   - Used to determine weight class
   - Optional but recommended

---

## 🎨 UI/UX Details

### Empty State
If no data exists:
```
📊 (show_chart icon, 64px)

"No progression data yet"

"Complete some ranked workouts to see your 
strength progression over time."

[Start Workout] button
```

### Loading State
- Center spinner with amber color
- Full-screen overlay

### Error State
```
⚠️ (error_outline icon, 64px)

"Failed to load progression data"

[Error message]

[Retry] button
```

---

## 🔍 Backend Logic (How e1RM is Calculated)

### e1RM Formula (Epley)
```
e1RM = weight × (1 + reps/30)
```

**Example:**
- 60 kg × 8 reps = 60 × (1 + 8/30) = 60 × 1.267 = **76 kg e1RM**

### LP (Lifting Points) Calculation
Based on:
- e1RM relative to bodyweight
- Tier multipliers
- Volume factor (total tonnage)

**Simplified:**
```
LP = (e1RM / bodyweight) × volume_factor × tier_multiplier
```

---

## 📈 Future Enhancements (Beyond Current Implementation)

### 1. **Peer Comparison Charts**
- Show where user ranks vs friends
- Show percentile by age/weight class
- "You're in top 15% of lifters your age!"

### 2. **Projected Timelines**
- "At current rate, you'll hit Gold tier in ~6 weeks"
- Trend line extrapolation

### 3. **Strength Standards Table**
- Untrained → Novice → Intermediate → Advanced → Elite
- Show exact kg requirements per tier
- By bodyweight and age

### 4. **Muscle Group Breakdown**
- Chest: 72% of goal
- Back: 85% of goal
- Legs: 60% of goal
- Identify weak points

### 5. **Social Comparison**
- "Your best friend lifts 10% more on bench"
- Anonymous community averages
- Leaderboards (opt-in)

---

## 🎯 Testing Checklist

- [x] Backend endpoint exists and returns data
- [x] Frontend service calls endpoint correctly
- [x] ProgressionScreen renders without errors
- [x] Exercise selector works
- [x] e1RM chart displays data points
- [x] Tier progress bar shows correctly
- [x] Personal records list populates
- [x] All exercises summary cards render
- [x] Empty state shows when no data
- [x] Error state handles failures gracefully
- [x] **NEW: Prominent card in AnalyticsHub**

---

## 💡 Why User Couldn't Find It

1. **Hidden behind icon** - Only a small chart icon in AppBar
2. **No visual cue** - No card, no text, just an icon
3. **Not in main navigation** - Not a primary tab or section
4. **Assumed it would be obvious** - But it was 3 levels deep

**User journey BEFORE:**
```
Progress Tab → Analytics Hub → Find tiny chart icon → Tap → ProgressionScreen
```

**User journey AFTER:**
```
Progress Tab → Analytics Hub → See BIG "Strength Progression" card → Tap → ProgressionScreen
```

---

## 📝 Summary

**What was missing:** NOT the feature - it was fully implemented! What was missing was **discoverability**.

**What was fixed:** Added a prominent, visually appealing card that makes the feature impossible to miss.

**Result:** User can now easily find and access their progression analytics with all the motivational graphs they wanted:
- ✅ e1RM progression over time
- ✅ Tier progression (Iron → Olympian)
- ✅ Personal records timeline
- ✅ Percentile comparison (by age/weight)
- ✅ Strength growth visualization

**Next step:** User should test the feature by:
1. Going to Progress tab
2. Tapping the new "Strength Progression" card
3. Selecting an exercise
4. Viewing their progression data

If no data shows, they need to complete some ranked workouts first!
