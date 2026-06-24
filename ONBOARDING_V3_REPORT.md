# Onboarding V3 — raport de implementare (2026-06-12, tura de noapte)

Sursa: `onboarding.zip` (handoff-ul lui Răzvan, 28 ecrane / 5 acte).
Implementare: `app/lib/screens/onboarding/onboarding_v3.dart` + `onboarding_v3_screens.dart` (~2.600 linii), legat în `main.dart`. **Toate cele 28 de ecrane sunt implementate.** V2 rămâne pe disc (nefolosit) — cine a terminat V2 nu e forțat să refacă V3.

---

## ✅ Cerința ta principală: AI-ul mutat la început

În V2, AI-ul pornea la pasul ~12 și ecranul de loading bloca până termina. Acum:

1. **Ecranul 6/28 (Goal)** — la Continue pornește `prewarmPlanFromGoal` → DeepSeek începe să macine când userul abia și-a ales obiectivul. **22 de ecrane de avans.**
2. **Ecranul 10/28 (Building)** — pornește sync-ul complet real (PATCH profil → PATCH settings → plan AI). Checklist-ul animat din design e legat de **fazele reale** (`onPhase`), nu de un timer fals.
3. **CTA-ul se deblochează când profilul+settings au ajuns pe server** (~2-4s) — NU așteaptă planul. Eticheta spune onest „Continue — plan finishing in background". Planul continuă prin Actele 3-5 (18 ecrane de prezentare = minute de buffer).
4. **Ecranul 28 (Enter Zvelt)** — dacă sync-ul încă rulează, așteaptă max 8s apoi intră oricum (planul se termină server-side; tab-urile au fallback de auto-generare). Eșec total → fallback-ul existent re-rulează sync-ul.
5. Back în ecranul Building **re-atașează** la același Future — nu dublează PATCH-uri sau call-uri AI.

## ✅ Alte lucruri reale (nu butoane decorative)

- **Notificări (ecranul 23)**: cere permisiunea FCM reală; „Not now" sare onest.
- **Connect (ecranul 24)**: rândul de health e LIVE — probează `hasPermissions`, „Connect" cere permisiunile real (+ acces istoric 30 zile), chip-ul devine „Connected" doar dacă chiar e.
- **Username**: PATCH best-effort separat (payload-ul de onboarding nu-l ducea); dacă e luat, userul îl schimbă din profil.
- **Persistență**: pasul + răspunsurile se salvează în SharedPreferences (contractul localStorage din handoff) — kill la app → reia de unde a rămas; se curăță la finalizare.
- **Mapările pe enum-ul backend**: muscle→hypertrophy, fat→fat_loss, strong→strength, health→maintenance; beg/int/adv→beginner/intermediate/advanced; dieta → tag dietary (high_protein/plant_based/low_carb).

## ➕ O abatere deliberată (de aprobat de voi doi)

**Câmp liber opțional sub cardurile de Goal** („In your own words — e.g. dunk a basketball again"). Motiv: motorul determinist de workout rutează pe `goalText` (calea test-coverată „dunk → pliometrie, nu forță generică"). Doar picker-ul cu 4 opțiuni ar fi omorât feature-ul pentru toți userii noi. E discret, opțional, și textul apare apoi pe ecranul Commit. Dacă Răzvan nu-l vrea, se șterge într-un minut.

## ❌ Ce NU am implementat + de ce

| Element din design | Motiv |
|---|---|
| **„Join the challenge" real (ecranul 21)** | Cardul „7-Day Movement Streak · 12.480 people" e demo; nu există acest challenge pe server. A înscrie userul într-un race aleator existent ar fi fost mincinos. Ambele CTA-uri continuă. **Fix corect:** Răzvan creează challenge-ul oficial de onboarding pe server → îi legăm id-ul (5 min de cod). |
| **Rândul „Whoop 4.0" din Connect (24)** | Nu există integrare Whoop (API închis, nu e în backend). L-am înlocuit cu rândul onest „Strava, Garmin & more — connect anytime from Settings". |
| **Badge-ul „First Step" persistat (22)** | Nu există sistem de badges în backend. Ecranul rămâne ca moment ceremonial (e în design), dar badge-ul nu se salvează nicăieri — chip-ul „Tier I · First Step" de pe ecranul final e tot ceremonial. |
| **Avatar cu poză (ecranul 5, butonul de cameră)** | Nici designul nu are handler pe el; nu există endpoint de avatar-upload. Badge-ul de cameră e vizual; avatarul arată inițialele numelui live. |
| **„4 sessions / week" dinamic (Commit/Summary)** | Designul îl are hardcodat; noul flow nu mai întreabă cadența (V2 o întreba). L-am lăsat ca în design. Dacă vreți cadență reală → un ecran în plus sau un picker pe Commit. |
| **„Matched to 3 active groups" (Summary)** | Nu există matching de grupuri în backend; am înlocuit cu „Feed & challenges unlocked" (adevărat). |

## ⚠️ Conținut demo păstrat ca-n design (decizia lui Răzvan, listat pentru transparență)

Statisticile de comunitate (248k members, 12.4M workouts, 4.9 rating, 63 countries), testimonialele (Yusuf/Anna/Marco), feed-ul demo (Lucas/Anna), leaderboard-ul demo, ringurile 62/68/84 de pe preview-ul Biology, streak-ul 12 zile / +18% / heatmap-ul de pe Tracking. Toate sunt **previews de produs / marketing**, implementate fidel. Singura mențiune: 248k members e un claim concret pre-launch — de discutat între voi înainte de store review (politicile Apple/Google la claims înșelătoare).

## 🧪 Stare

- `flutter analyze`: 0 erori · `flutter test`: 25/25
- Gating: `kOnboardingV3CompletedKey` per user; cine avea V2 completat nu revede flow-ul
- **Necomis** — verificați-l întâi pe telefon (28 de ecrane = mult de văzut cu ochii)

## 📋 De testat pe telefon

1. Cont nou → tot flow-ul cap-coadă; verifică că la Building CTA-ul se deblochează în câteva secunde, nu așteaptă AI-ul
2. Kill app la ecranul 15 → redeschide → reia de la 15 cu răspunsurile intacte
3. La final, tab-ul Nutrition ar trebui să aibă planul gata (sau aproape) — ăsta e câștigul mutării AI-ului
4. Notificări + Health connect pe device real (emulatorul minte la permisiuni)
