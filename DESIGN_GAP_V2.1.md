# Zvelt — Design V2.1 vs App · Gap list (2026-06-12)

Comparație design complet (`Zvelt V2.1.zip`) vs aplicația Flutter. Două rubrici: **SE POATE** (avem date/cod sau e pur UI) și **NU SE POATE încă** (cu motivul exact). 
---

## ✅ SE POATE — avem sursa de date

### Ecrane de detaliu metrice (cel mai mare chunk lipsă — `METRIC_CONFIG` din screens-modals.jsx)
Avem doar 3 din 16 (strain/recovery/sleep, făcute azi). Se pot construi pe modelul `MetricDetailScreen` existent:
| Metrică | Sursă |
|---|---|
| **Volume** (12 săpt., bar chart + breakdown) | `StatsChartsService.getWeeklyEffort(weeks:12)` |
| **Strength progression** (trend e1RM) | `getWeeklyEffort` + `getRankLp`; StrengthAnalyticsScreen are deja istoricul per exercițiu |
| **Top exercises** (30d) | `getTopExercises(days:30)` |
| **Consistency** (365d, streak + breakdown pe zile) | `getDailyTraining(days:365)` |
| **Steps detail** (7d chart + breakdown) | `getDailyStepsHistory` |
| **Calories detail** (14d chart) | `getDailyCaloriesBurnedHistory` |
| **Sleep detail extins** (stages breakdown) | `getSleepDetails` — doar noaptea trecută (istoricul pe 7 nopți → vezi rubrica gri) |
| **STR (character stat) detail** | parțial — e1RM pe compounds există server-side |

### Train tab
- **Performance trend cu toggle 30D/60D/90D** — widgetul suportă scope; de legat la `getDailyTraining` cu days variabil
- **Data + ziua sub greeting** („Mon · 24 May") — trivial
- **Resume în Quick Launch** („Resume Hypertrophy · Day 12") — `WorkoutDraftStore` are draftul

### Nutrition
- **Banner „AI plan ready"** — status din `getWeeklyPlan()`
- **„Calculate from bodyweight & activity"** în Goals — Mifflin-St Jeor pe device din bodyweight (Profile) + nivel activitate; transparent, explicabil
- **Favorites / Recent foods** în Add Food — store local nou (SharedPreferences/SQLite), fezabil
- **Manual entry** (aliment custom cu macros) — formular simplu, local

### Social
- **Unread badge pe conversații** + preview bold la necitit — `MessagesService`
- **Buton compose-DM** în header Conversations — alegi prietenul → `openConversation`
- **Avatar stack pe hero-ul Race of the Week** („+243 more") — endpoint-ul de participants întoarce lista, folosim primele 3-4 avatare
- **Privacy label pe PostDetail** („2h ago · friends") — `post.visibility` există în model
- **Share button direct pe card** — `share_plus` e deja în app
- **Story reply** (input jos în viewer) — se trimite ca DM către autor prin `MessagesService` (fără backend nou)
- **Gallery filter icon** — UI-only

---

## ❌ NU SE POATE încă

### Blocate de backend →  (UI-ul e gata sau trivial, lipsesc câmpurile)
1. `likedByMe` pe posts — inimile goale după reload (știut)
2. `stats {sessions, prs, streak}` + `tier` pe `GET /users/:id` — cardul de profil arată „—" (știut)
3. `isLive` pe stories + glow-ul de „LIVE" din rail
4. **Total friends count** — „Your tribe · 247 friends" în header feed
5. **Rank în race** — „#14 / 248" pe hero card (endpoint de plasament)
6. **Race chat real** — v1.1 (notes-urile private există, onest local-only)
7. **Comment likes + replies** — designul are Like/Reply sub comentarii; nu există endpoint
8. **Mutual friends** („Mutual: Maya, Ravi") — nu vine în response-ul de friends/search
9. **User presence** („Active now" în DM) — nu există presence API
10. **DM attachments** (butonul „+" din composer) — cere upload endpoint
11. **Mute thread** — cere endpoint de mute
12. **Badges system** (grid-ul earned/locked din Hall of Fame) — nu există în backend

### Date care nu există nicăieri (senzor/tracking lipsă) — nu le putem fabrica
1. **Rest time between sets** (metrică + trend 12 săpt.) — nu cronometrăm repausul per set; ar cere logging nou în tracker ÎNTÂI, istoric DUPĂ (azi: zero date)
2. **Stress metric** (hourly) — nu există senzor; HRV singur nu e stres
3. **Calories breakdown pe activitate** (strength/cardio/movement) — Health dă doar totalul
4. **Mobility & Power character details** — cer ROM, jump height, bar speed; nu avem niciuna
5. **Body battery / ECG** — proprietar Garmin / hardware dedicat (scoase deja din Biology)
6. **Micronutrienți, food-photo recognition** — USDA nu dă, n-avem ML pipeline

### 🟡 Gri — posibil, dar cu cod nou de platformă (de decis dacă merită)
- **Sleep history 7 nopți** (chart în sleep detail) — health package poate interoga range-uri; trebuie scrisă metoda
- **HR pe ore + zone** (heart detail screen) — la fel, query nou pe samples HR
- **HRV/RHR history charts** — la fel

---


Designul arată „plin" pentru că TOATE valorile lui sunt demo hardcodat: 84k lb volume, +18% strength, 247 sessions, „Push · Day 12", Maya/Ravi/Ela prin tot socialul, PR 87.5kg, „Garmin Forerunner 965 · 87% battery", toate chart-urile din METRIC_CONFIG. **App-ul pe un cont gol nu va arăta NICIODATĂ ca mockup-ul** — nu pentru că lipsește UI, ci pentru că principiul nostru e date reale sau stare onestă de gol. Diferența e, în mare parte, diferența dintre un cont demo populat și un cont real nou. Soluția corectă nu e UI fals, ci un **cont de test populat cu date reale** (workouts logate, prieteni, postări) pentru comparații vizuale.

---

*Generat din analiza a 5 agenți pe screens-train/nutrition/social/social-modals/modals .jsx vs lib/, corectat manual. Handoff-urile recovery-card.md și progress-tab.md erau deja implementate la zi.*
