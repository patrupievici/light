# Zvelt — CLAUDE.md

Aplicatie mobila fitness cross-platform (iOS/Android) orientata pe forta.
Spec completa: `C:\Users\razva\Downloads\forge_spec.txt` | Detalii: memory/forge_project.md

## Stack
- **Mobile:** Flutter (Dart) — decizie finala de confirmat
- **Backend:** REST + JSON, PostgreSQL
- **Billing:** RevenueCat (StoreKit2 iOS + Play Billing Android)
- **Integrari:** iOS HealthKit, Android Health Connect, Strava OAuth2
- **Infra:** containerized, dev/staging/prod, Terraform (TBD)
- **DB migrations:** Flyway sau Liquibase

## Arhitectura backend
Microservicii separate, toate in spatele unui API Gateway:
- Auth Service
- Workout Service
- Ranking Service
- Social/Feed Service
- Economy Service
- Integrations Service (Strava, RevenueCat webhooks)
- Event Bus → Warehouse/BI + Notifications

## Principii non-negociabile
1. **Privacy by default** — feed doar prieteni; discovery opt-in explicit
2. **Offline-first** — workout tracking functional fara internet (sync la reconectare)
3. **Explainability** — orice rang sau recomandare afiseaza "de ce"
4. **Safety guardrails** — limite progres, avertizari RPE/volum
5. **Accessibility** — dynamic text, semantics, contrast WCAG

## Algoritm ranking
```
e1RM = weight_kg * (1 + reps / 30)   // Epley; doar reps in [1..12]; doar tag=WORK
SR   = best_e1RM / bodyweight_kg
LP   = floor(percentile_rank(SR, exercise_id, bw_band, sex) * 100)
```
- `lp_total` cumulativ; tier nou la fiecare 100 LP
- Tiers: Iron → Bronze → Silver → Gold → Platinum → Diamond → Olympian
- Overall score = sum(top 10 exercise scores, ponderate)
- Warmup/Drop sets excluse din calcul
- BW lipsa → eroare `BW_REQUIRED`, nu se calculeaza rang

## Anti-cheat (server-side)
- Max 3 editari/24h per post
- Audit log before/after pe orice editare set
- Jump SR >20% vs best 30 zile → flag "anomaly"
- Weight >2× max istoric personal + <7 zile → confirm + nota obligatorie
- "Trusted tier" doar conturi >30 zile pe leaderboard seasonal

## Schema DB (tabele principale)
```
users, auth_identities, user_profiles
exercises
workouts, workout_exercises, workout_sets
posts, post_privacy_settings, post_likes, post_comments
friendships
user_exercise_ranks, seasons, user_season_stats
wallets, shop_items, wallet_transactions
analytics_events
```
- UUID primary keys peste tot
- Greutati stocate canonical in `weight_kg` / `bodyweight_kg`
- Conversie unitati (kg/lb) se face in client; serverul valideaza

## API conventions
- Base URL: `/v1`
- Auth: `Authorization: Bearer <access_token>`
- Error response: `{ error, message, request_id, details? }`
- Paginare pe toate listele
- Rate limiting pe auth endpoints (per IP + per email)

## Endpoints principale
```
POST   /v1/auth/email/signup|refresh|logout
GET    /v1/me
PATCH  /v1/me/profile
GET    /v1/exercises
POST   /v1/exercises/custom
POST   /v1/workouts
POST   /v1/workouts/{id}/exercises/{we_id}/sets
POST   /v1/workouts/{id}/complete
POST   /v1/posts                              // declanseaza RankingService
GET    /v1/ranks/exercises/{id}/explain
POST   /v1/integrations/strava/exchange
```

## Validari obligatorii
| Camp | Regula |
|---|---|
| `bodyweight_kg` | 30–250 kg (30–250 configurable) |
| `weight_kg` (set) | 0.0–500.0 |
| `reps` | int 1–50 (doar 1–12 pentru e1RM) |
| `rpe` | 1.0–10.0 |
| `caption` | max 500 chars |
| `comment.body` | max 500 chars, sanitizat |
| `password` | 8–128 chars |

## Design system (tokens)
```
color.bg.primary      = #0B0D10
color.bg.elevated     = #121621
color.text.primary    = #FFFFFF
color.text.secondary  = #A9B0C0
color.accent.blue     = #2F6BFF
color.success         = #2EEA7A
color.warning         = #FFB020
color.error           = #FF4D4D
color.border          = #232B3A

font.size: xs=12, sm=14, md=16, lg=20, xl=28
font.weight: regular=400, semibold=600, bold=700
grid: 8pt | radius: 12 (cards), 16 (modals), 999 (chips)
touch targets: min 44×44pt (iOS) / 48dp (Android)
```

## Gamification
- **Streak:** 3 zile consecutive fara postare = break; job zilnic "streak at risk"
- **Sezoane:** reset la 4 luni (3 resetari/an); ranguri istorice raman in profil
- **Quests:** MVP basic; extins post-launch

## Monetizare
- **Free:** tracking complet, ranguri top 10 exercitii, social friends feed, quests basic
- **Pro:** ranguri nelimitate, explainability avansata, program builder, analytics extins
- **Consumabile (non-p2w):** StreakBuffer (max 2/luna), ThemePack, ProfileBanner, BoostXP (cosmetic)
- RevenueCat entitlement: `pro` | products: `zvelt_pro_monthly`, `zvelt_pro_annual` (configure IDs în dashboard dacă diferă)

## Obiective KPI (MVP)
| Metric | Tinta |
|---|---|
| Activation (primul workout) | ≥45% din instalari |
| Core activation (primul rang) | ≥30% |
| D7 retention | ≥22% |
| D30 retention | ≥10% |
| Trial start rate | ≥8% din activi |
| Trial → paid | ≥35% |

## SLOs
- API availability: 99.9% / 30 zile
- p95 latency read: <300ms
- p95 latency post/ranking: <800ms (async fallback)
- Crash-free sessions: ≥99.5%
- Webhook processing: 99% <60 sec

## Privacy & GDPR
- TLS 1.2+ in transit; coloane sensibile (tokens) encrypt at rest
- Health data: consimtamant explicit, fine-grained (per data type)
- Right to erasure: hard delete/anonimizare in 30 zile
- Retention: workouts pana la stergere cont | analytics raw 13 luni | security logs 90 zile
- App Privacy Details (iOS) si Data Safety (Android) mentinute up-to-date

## Roadmap (Gantt)
```
2026-03-15  MVP: Tracker + Offline-first        (45 zile)
2026-03-20  MVP: Ranking + Explainability        (50 zile)
2026-04-01  MVP: Social + Privacy controls       (45 zile)
2026-04-05  MVP: RevenueCat + Paywall            (35 zile)
2026-04-10  MVP: Integrari health + Strava       (40 zile)
2026-06-10  *** PUBLIC LAUNCH ***
2026-07-01  Program Builder v1                   (75 zile)
2026-08-15  Challenges de grup                   (60 zile)
2026-10-01  Creator plans marketplace            (90 zile)
2026-11-15  Companion Watch (optional)
```

## Personas
| ID | Nume | Varsta | Motivatie principala |
|---|---|---|---|
| A | Gamer de progres | 18-30 | Rang, niveluri, climb |
| B | Builder ocupat | 25-40 | Claritate, minim input, log rapid |
| C | Atletul de date | 20-50 | Grafice, e1RM, integrari |
| D | Incepator in sala | 16-28 | Tutoriale, programe simple |
| E | Revenit dupa pauza | 25-55 | Progres sigur, fara dureri |
| F | Social lifter | 18-35 | Prieteni, feed, provocari |
| G | Privatul | 18-45 | Tracking personal, fara social |
| H | Competitor | 18-40 | Leaderboard, anti-cheat, fairness |
