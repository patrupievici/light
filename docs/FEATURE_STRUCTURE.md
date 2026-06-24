# Zvelt — Structura feature-urilor, flow-uri și dependențe

Document de orientare: de unde pleacă fiecare funcționalitate, ce pași are și ce depinde de ce.

---

## 1. Harta feature-urilor (pe scurt)

| Feature | Entry point | Status actual | Depinde de |
|--------|-------------|---------------|------------|
| **Auth** | App launch / Login screen | ✅ Implementat | — |
| **Entry + Onboarding concept** | După install (Start → Welcome → Login) | ✅ Parțial | Auth |
| **Profil (date fizice)** | Main → Profile | ✅ Parțial (greutate, înălțime) | Auth |
| **Profil (extins)** | Profile screen | ❌ Plan | — |
| **Chestionar onboarding** | După signup (plan) | ❌ Plan | Auth |
| **Avatar** | După onboarding concept | ✅ Implementat | Auth |
| **Workouts / Tracker** | Main → Workouts | ❌ Placeholder | Auth, Exercises, (Profil pentru bodyweight) |
| **Exercises** | Main → Exercises | ❌ Placeholder | Auth, Backend /exercises |
| **Ranking / Ranks** | Main → Ranks, post-workout | ❌ Placeholder | Auth, Profil (bodyweight), Workouts (sets) |
| **Social / Feed** | (plan: tab sau Main) | ❌ Plan | Auth, Posts, Friendships |
| **Streak** | Backend + (plan: Home/Profil) | ⚠️ Backend existent | Auth, Workouts/Posts |
| **Premium / Paywall** | (plan: trial, upgrade) | ❌ Plan | Auth, RevenueCat |
| **Health (HealthKit / Health Connect)** | (plan: onboarding sau setări) | ❌ Plan | Auth, Permisiuni OS |
| **Reminder / Notificări** | (plan: onboarding) | ❌ Plan | Auth, Permisiuni |

---

## 2. Profil (Profile) — flow și dependențe

### 2.1 Unde pleacă
- **Entry:** Main screen → buton **Profile** → `ProfileScreen`.

### 2.2 Ce există acum
- **Input utilizator:** greutate (slider kg), înălțime (slider cm).
- **Persistență:** greutate → `PATCH /v1/me/profile` (backend: `bodyweightKg`); înălțime → doar local (`SharedPreferences`), backend nu are câmp înălțime în schema actuală.

### 2.3 Ce se poate extinde (flow logic)
```
[Profil]
  ├── Date fizice (INPUT USER)
  │     ├── Vârstă (lipsă în UI; backend: birthYear în UserProfile)
  │     ├── Greutate (kg) ✅
  │     └── Înălțime (cm) — doar local ✅
  │
  ├── Scor / metrici (CALCULATE sau AFIȘARE)
  │     ├── Scor consistență (ex: workout-uri/săptămână, streak) → depinde de Workouts + Streak
  │     ├── Dietă recomandată → (viitor: reguli/API; poate depinde de greutate, obiectiv, TDEE)
  │     └── Ore somn → (viitor: Health Connect / input manual) → depinde de Health sau form
  │
  └── Preferințe
        ├── Unități (metric/imperial) — backend: unitSystem ✅
        ├── Avatar (ales la onboarding) — salvat local ✅
        └── Privacy default — backend ✅
```

### 2.4 Dependențe Profil
- **Profil → Backend:** `GET /v1/me`, `PATCH /v1/me/profile` (displayName, username, bio, unitSystem, **bodyweightKg**, birthYear, sex, privacyDefault).
- **Alte feature-uri care depind de Profil:** Ranking (are nevoie de **bodyweight_kg** pentru LP/SR), eventual recomandări dietă/TDEE.

---

## 3. Auth și Entry (flow aplicație)

### 3.1 Flow la deschidere
```
App launch
  → AuthGate (are token?)
       ├── DA → onboarding concept făcut?
       │         ├── NU → OnboardingConceptFlow (FIG 5–7) → apoi avatar făcut?
       │         │                                          ├── NU → AvatarFlow → MainScreen
       │         │                                          └── DA → MainScreen
       │         └── DA → avatar făcut? → la fel ca mai sus
       │
       └── NU → entry flow complet?
                 ├── NU → StartScreen (FIG 1) → WelcomeScreen (FIG 2) → LoginScreen
                 └── DA → LoginScreen
```

### 3.2 Dependențe
- **Auth** nu depinde de niciun alt feature.
- **Onboarding concept + Avatar** depind doar de Auth (user autentificat).
- **LoginScreen** oferă: email/parolă, Google Sign-In → token salvat → AuthGate redirectează.

---

## 4. Workouts (antrenamente) — flow și dependențe

### 4.1 Unde pleacă
- **Entry:** Main → **Workouts** (acum placeholder).

### 4.2 Flow logic (țintă)
```
Workouts
  → Listă workout-uri (GET /v1/workouts) sau „Start empty”
  → Creare workout: POST /v1/workouts
  → Adăugare exerciții la workout (din lista Exercises)
  → Pentru fiecare exercițiu: sets (weight_kg, reps, rpe, tag WORK|WARMUP|DROP)
  → Complete: POST /v1/workouts/:id/complete
  → (Opțional) Post pe feed: POST /v1/posts → declanșează recalcul ranking
```

### 4.3 Dependențe
- **Auth:** obligatoriu.
- **Exercises:** lista de exerciții (GET /v1/exercises) pentru a adăuga la workout.
- **Profil (bodyweight):** nu e obligatoriu pentru a salva workout-ul, dar **Ranking** nu poate calcula LP fără bodyweight → mesaj `BW_REQUIRED`.
- **Offline-first:** spec cere funcționalitate fără internet; sync la reconectare (de implementat).

---

## 5. Exercises (exerciții)

### 5.1 Unde pleacă
- **Entry:** Main → **Exercises** (acum placeholder).

### 5.2 Flow logic
```
Exercises
  → GET /v1/exercises (listă globală + custom user)
  → (Opțional) POST /v1/exercises/custom — exercițiu custom
  → Folosit în: Workouts (când adaugi exercițiu la antrenament), Ranking (per exercise_id)
```

### 5.3 Dependențe
- **Auth** pentru custom exercises și pentru context.
- **Workouts** și **Ranking** depind de lista de exercises (ids, rank_model, etc.).

---

## 6. Ranking (ranguri, LP, explainability)

### 6.1 Unde pleacă
- **Entry:** Main → **Ranks**; după post workout (explicare „de ce” acel rang).

### 6.2 Flow logic
```
Ranking
  → Input: workout sets (weight_kg, reps 1–12, tag=WORK) + bodyweight_kg user
  → Algoritm: e1RM = weight_kg * (1 + reps/30); SR = best_e1RM / bodyweight_kg; LP = percentile_rank(...)
  → GET /v1/ranks/exercises/:id/explain — „de ce” am acest scor
  → Afișare: tier (Iron → Olympian), LP total, top 10 exercises
```

### 6.3 Dependențe
- **Auth.**
- **Profil: bodyweight_kg** — obligatoriu; fără → `BW_REQUIRED`, nu se calculează rang.
- **Workouts / Sets:** datele de forță (weight, reps) din workout-uri completate/postate.
- **Exercises:** pentru a ști exercise_id, rank_model (WEIGHTED etc.).

---

## 7. Social / Feed

### 7.1 Unde pleacă
- (Plan: tab Feed sau secțiune pe Home.)

### 7.2 Flow logic
```
Feed
  → Post = workout completat + vizibilitate (private|friends|public)
  → GET posts (prieteni / public după setări)
  → Likes, comments (backend: PostLike, PostComment)
  → Privacy: feed doar prieteni (spec); discovery opt-in
```

### 7.3 Dependențe
- **Auth.**
- **Workouts:** un post e legat de un workout.
- **Friendships:** pentru feed „prieteni”.
- **Profil:** privacy default, setări per-post (hide weights/reps/bodyweight).

---

## 8. Streak

### 8.1 Unde pleacă
- Backend: `getStreakStatus(userId)`; returnat la `GET /v1/me` în `streak`.
- (Plan: afișare pe Home sau în Profil.)

### 8.2 Logică
- 3 zile consecutive fără postare = break.
- Job „streak at risk” (notificare).

### 8.3 Dependențe
- **Auth.**
- **Posts / Workouts:** definiția „postare” pentru a nu rupe streak-ul.

---

## 9. Chestionar onboarding (Faza 3 din plan)

### 9.1 Unde pleacă
- După signup / după onboarding concept (în plan: înainte sau după avatar).
- FIG 8–19: unități, grupe musculare, obiectiv, gen, înălțime, greutate, vârstă, etc.

### 9.2 Dependențe
- **Auth.**
- **Backend:** model onboarding (Faza 0.2, 0.3) — tabele/endpoint pentru răspunsuri.
- **Profil:** multe răspunsuri (înălțime, greutate, vârstă, gen) se pot scrie în `UserProfile` sau în tabel dedicat onboarding.

---

## 10. Grafic dependențe (sumar)

```
                    ┌─────────┐
                    │  Auth   │
                    └────┬────┘
         ┌───────────────┼───────────────┬──────────────┐
         ▼               ▼               ▼              ▼
   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
   │  Profil  │   │ Workouts │   │ Exercises│   │  Social  │
   │ (BW, etc)│   │  (sets)  │   │ (listă)  │   │ (posts)  │
   └────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘
        │              │              │              │
        │              └──────┬───────┘              │
        │                     ▼                     │
        │              ┌─────────────┐               │
        └─────────────►│   Ranking   │◄─────────────┘
                       │ (needs BW)  │   (post = workout)
                       └─────────────┘

   Streak ← Auth + (Posts/Workouts)
   Paywall ← Auth
   Health ← Auth + OS permissions
```

---

## 11. Ce ai acum în cod (quick reference)

| Locație | Ce e |
|--------|------|
| **App** | `main.dart` (AuthGate, flow Start → Welcome → Login → Onboarding concept → Avatar → Main); `MainScreen` (butoane Workouts, Exercises, Profile, Ranks, Logout); `ProfileScreen` (greutate + înălțime, slidere, Save); `LoginScreen` (email, Google); ecrane entry/onboarding/avatar. |
| **Backend** | Auth (email + Google), GET/PATCH profile, exercises, workouts, posts, ranks (services: ranking, streak); Prisma: users, user_profiles (bodweightKg, birthYear, sex, unitSystem, etc.), workouts, workout_exercises, workout_sets, posts, user_exercise_ranks, etc. |
| **Lipsesc în UI** | Vârstă în Profil; consistency score, dietă, somn; Workouts/Exercises/Ranks (doar placeholders); Social, Paywall, Health, Reminder. |
| **Lipsesc în backend** | Câmp înălțime în `UserProfile` (poți adăuga `heightCm`); model/API onboarding dedicat (Faza 0.2/0.3). |

---

## 12. Ordine sugerată pentru „curățenie” și next steps

1. **Profil complet (input):** adaugă vârstă în `ProfileScreen`; opțional înălțime în backend (`UserProfile.heightCm`) ca să fie totul într-un loc.
2. **Backend:** erori în engleză, naming consistent; eventual layer clar routes → services → db.
3. **Flutter:** structură feature-first (ex: `lib/features/auth`, `lib/features/profile`, `lib/features/workouts`) + routing clar.
4. **Workouts flow:** prima funcționalitate „core” după Profil — listă, creare, adăugare sets, complete; apoi Ranking + Explain.
5. **Social / Streak UI:** după ce Workouts și Ranking merg.

Dacă vrei, următorul pas poate fi: fie extinderea **Profil** (vârstă + înălțime în backend), fie un **refactor de structură** (foldere + routing) ca să știi „unde stă” fiecare feature în cod.
