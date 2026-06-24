# Zvelt — Navigare, ecrane principale și structură

Ghid pentru a înțelege: **ce elemente vrea prietenul tău în app**, **ce e principal** pe ecranul de start, **cum ajungi la restul** (butoane, meniuri, tabs), și **cum organizezi folderele** în cod. Poți folosi acest doc când te uiți mâine la o aplicație de referință (orice app/joc): vezi cum ei au organizat ecranul principal vs restul, și îți faci imaginea pentru Zvelt.

---

## 1. Lista completă: ce vrea prietenul tău în aplicație

Toate elementele din plan (slide-uri FIG) și din spec, grupate pe **zone logice**. Fiecare zonă îți spune: „asta există în app” și „unde ar putea apărea în meniu”.

| Zonă | Elemente (ecrane / funcționalități) | Sursa (FIG / spec) |
|------|-------------------------------------|---------------------|
| **Entry (înainte de login)** | Start (branding), Welcome, Login, Sign up (Apple/Google/Email), Confirmare profil | FIG 1–4, 57–58 |
| **Onboarding (după login, o dată)** | Concept ranking (3 ecrane), Chestionar (unități, grupe musculare, obiectiv, gen, înălțime, greutate, vârstă, etc.), Avatar (intro → alegere → confirmare), Plan antrenament (ai plan?, loc, echipament, durată, zile/săpt.), Reminder (notificări), Widget setup, Health permisiuni | FIG 5–7, 8–19, 20–24, 25–30, 31–35, 53–56 |
| **Home (ecran principal)** | Dashboard: obiectiv, date recente, streak, discover, acces rapid la workout | FIG 69–71 |
| **Workouts (core)** | Listă rutine, Start workout, Tracker (exerciții + sets: weight, reps, RPE), Complete, Post pe feed | FIG 72–73 + spec |
| **Ranking / Bodyrank** | Ce e Bodyrank, cum se construiește, focus grupe slabe, trial, Primul rank obținut, Procesare profil, Explain („de ce” acel scor) | FIG 36–40, 41–44 |
| **Premium** | Trial, reminder trial, selectare plan (lună/an), beneficii Pro (fără reclame, rank, generator, Calorie Lens, etc.) | FIG 45–49, 62–68 |
| **Streak** | Primul streak, Alegere goal (ex: 3/5/7 zile), Confirmare | FIG 50–52 |
| **Profil** | Date fizice (vârstă, greutate, înălțime), Scor consistență, Dietă recomandată, Ore somn, Avatar, Unități, Privacy, Setări | Spec + FIG + FEATURE_STRUCTURE |
| **Social / Feed** | Feed prieteni, posturi, like, comentarii, discover (opt-in) | Spec |
| **Altele** | Exercises (listă + custom), Ranks/Leaderboard, Conectare Strava, Plan 30 zile, Widget | FIG 60–61, spec |

Din asta reiese:
- **Un singur ecran principal** (Home) unde utilizatorul „trăiește” după onboarding.
- **Acțiuni frecvente**: Start workout, vezi streak, vezi obiectiv → deci pe Home sau foarte aproape (1 tap).
- **Restul**: Profil, Ranking explicat, Exercises, Feed, Premium, Setări → pot fi în **meniu secundar** (tab bar, drawer sau „More”).

---

## 2. Ce e principal vs ce e secundar

| Nivel | Ce e | Exemple în Zvelt |
|-------|------|-------------------|
| **Principal (mereu vizibil / 1 tap)** | Acțiunea cea mai des făcută + starea curentă | **Home** (dashboard: streak, obiectiv, „Start workout”), **Workouts** (listă + tracker) |
| **Secundar (2 taps sau un meniu)** | Consultare, configurare, explorare | **Profil**, **Ranking/Ranks**, **Exercises**, **Feed** |
| **Terțiar (din setări sau flow-uri speciale)** | Setări, premium, conectări, onboarding | **Setări**, **Premium/Paywall**, **Strava**, **Reminder**, **Health**, **Widget** |

**Regulă practică:** Pe **ecranul principal** (Home) pui:  
- ce vrea userul să vadă imediat (streak, progres, obiectiv),  
- și un CTA mare: **„Start workout”** sau **„Continuă antrenamentul”**.  
Restul (Profil, Ranks, Exercises, Feed) sunt **destinații** unde ajungi din tab bar, din drawer sau dintr-un buton „More”.

---

## 3. Cum organizezi butoanele și navigarea — 3 variante

### Varianta A: Bottom navigation (tab bar) — **recomandat**

- **3–5 tab-uri** în partea de jos: de ex. **Home** | **Workouts** | **Feed** (opțional) | **Ranks** | **Profil**.
- **Home** = ecran principal (dashboard).
- **Workouts** = listă + intră în tracker (flow-ul de antrenament).
- **Profil** = date fizice, consistență, dietă, somn, setări (sau link către Setări).
- **Ranks** = leaderboard + explain.
- **Feed** = social (dacă vrei tab dedicat; altfel poate fi pe Home ca „Discover”).

**Avantaj:** Clar, familiar, totul la maxim 1 tap. Foarte potrivit pentru o app de fitness unde acțiunile principale sunt „vezi starea” și „fă workout”.

### Varianta B: Un singur Home + meniu (hamburger / „More”)

- **Un ecran principal** (Home) cu carduri: Streak, Obiectiv, „Start workout”, poate un rând „Discover”.
- **Un buton meniu** (hamburger sau „More” / iconiță profil) care deschide: **Profil**, **Workouts**, **Exercises**, **Ranks**, **Feed**, **Setări**.
- Workouts poate fi și un card mare pe Home: „Start workout” / „Listă antrenamente”.

**Avantaj:** Un singur „hub”; meniul ascunde complexitatea. Dezavantaj: Workouts și Ranks sunt la 2 tap-uri.

### Varianta C: Home + bottom bar minimal (2–3 tab-uri)

- **Home** (dashboard + card „Workouts” / „Start”) + **Profil** (sau „More”).
- Restul (Workouts ca ecran full, Ranks, Exercises, Feed) → intri din **Home** (carduri) sau din **Profil** ca „Ranks”, „Exercises”, „Setări”.

**Avantaj:** Foarte simplu. Dezavantaj: mai multe tap-uri pentru Ranks/Exercises.

---

## 4. Recomandare pentru Zvelt

- **Ecran principal:** **Home** (dashboard: streak, obiectiv, date recente, CTA „Start workout”, eventual Discover).
- **Navigare:** **Bottom navigation** cu 4 tab-uri: **Home** | **Workouts** | **Ranks** | **Profil** (Feed poate fi secțiune pe Home sau tab 5).
- **Profil:** Pagină cu secțiuni: Date fizice (vârstă, greutate, înălțime), Consistență, Dietă, Somn, Avatar, Setări (unități, privacy, reminder, Health, Strava, Premium). Fiecare secțiune = listă de rânduri care duc la ecrane dedicate sau la slide-uri.
- **Workouts:** Tab = listă de antrenamente + buton „Start” / „New”; tap pe unul = detalii sau continuare; „Start” = intră în Tracker (exerciții + sets).
- **Ranks:** Listă/dashboard rank + „Explain” per exercițiu.
- **Restul** (Exercises, Setări, Premium, Strava, Widget, etc.) → din **Profil** sau din **Setări** (sub-ecran al Profilului).

Astfel ai o **imagine mentală clară**: un ecran principal (Home), patru zone mari (Home, Workouts, Ranks, Profil), iar restul sunt sub-ecrane sau flow-uri (onboarding, paywall, reminder).

---

## 5. Diagramă: de unde pleacă fiecare element

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          APP LAUNCH                                      │
│  [Fără token] → Start → Welcome → Login/Sign up → Onboarding → Avatar    │
│  [Cu token]   → Onboarding? → Avatar? → HOME (tab bar)                  │
└─────────────────────────────────────────────────────────────────────────┘
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
            ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
            │    HOME      │    │   WORKOUTS   │    │    RANKS     │
            │  (principal) │    │   (tab)      │    │   (tab)      │
            │              │    │              │    │              │
            │ • Streak     │    │ • Listă      │    │ • Leaderboard│
            │ • Obiectiv   │    │ • Start new  │    │ • Explain    │
            │ • Start      │    │ • Tracker    │    │ • Bodyrank   │
            │   workout    │    │ • Complete   │    │   explainer  │
            │ • Discover   │    │ • Post       │    │              │
            └──────┬───────┘    └──────────────┘    └──────────────┘
                   │
                   │  (optional: tab Feed între Home și Workouts)
                   │
            ┌──────▼───────┐
            │   PROFIL     │
            │   (tab)      │
            │              │
            │ • Date       │──→ (ecran) Greutate, înălțime, vârstă
            │   fizice     │
            │ • Consistență│──→ (afișare) Scor + detalii
            │ • Dietă      │──→ (ecran) Recomandare
            │ • Somn       │──→ (ecran) Ore somn
            │ • Avatar     │──→ (ecran) Schimbare avatar
            │ • Setări     │──→ Reminder, Health, Strava, Unități,
            │              │    Privacy, Premium, Log out
            └──────────────┘
```

**Rezumat:**  
- **Principal** = Home (un singur „home screen”).  
- **Tab-uri** = Home, Workouts, Ranks, Profil (și opțional Feed).  
- **Fără** multiple „home screen-uri” separate; unul singur, restul sunt secțiuni/sub-ecrane.  
- **Dropdown-uri** pot fi folosite în interiorul ecranelor (ex: filtre pe Ranks, tip workout), nu pentru navigarea principală.

---

## 6. Checklist pentru mâine: cum să te uiți la app-ul de referință

Când te vezi cu prietenul și vă uitați la o aplicație (orice: fitness, joc, productivitate), poți nota:

1. **Ce e pe primul ecran după login?**  
   Un singur ecran principal sau mai multe? Ce butoane/carduri mari sunt?

2. **Cum ajungi la celelalte funcții?**  
   Tab bar jos? Meniu hamburger? Iconițe în header? Listă de „opțiuni” într-un ecran „Profil” sau „Setări”?

3. **Ce acțiune e cea mai evidentă?**  
   Un singur buton mare (ex: „Start”) sau mai multe opțiuni egale?

4. **Unde sunt setările și profilul?**  
   Tab separat, ultimul tab, sau ascunse într-un meniu?

5. **Cum arată „listele” (ex: antrenamente, istoric)?**  
   Full screen cu listă, sau carduri pe ecranul principal?

6. **Există „flow-uri lungi” (onboarding, checkout)?**  
   Câți pași și cum revii înapoi (X, Back, sau „Skip”)?

Poți completa acest checklist în **APP_NAVIGATION_AND_STRUCTURE.md** (secțiune nouă „Note din referință”) după ce vă uitați la app, ca să decideți împreună: „Vrem tab bar ca la X” sau „Vrem un singur Home cu meniu ca la Y”.

---

## 7. Structură foldere în proiect (Flutter)

Organizare **feature-first**: fiecare zonă mare are propriul folder, ca să știi „unde stă” fiecare element.

```
app/
  lib/
    main.dart
    app.dart                    # MaterialApp, theme, routes
    routes.dart                 # Nume rute (opțional)

    core/                       # Shared: nu ține de un feature
      theme/
        app_theme.dart
      config/
        api_config.dart
      l10n/
        app_strings.dart
        auth_error_messages.dart

    features/
      auth/
        screens/
          login_screen.dart
        auth_gate.dart          # logică „unde trimitem userul”
        services/               # dacă e nevoie, altfel folosești lib/services
      entry/                    # Start, Welcome (înainte de login)
        screens/
          start_screen.dart
          welcome_screen.dart
      onboarding/
        screens/
          onboarding_concept_flow.dart
          onboarding_concept_screen.dart
        questionnaire/          # (viitor) FIG 8–19
        avatar/
          avatar_flow.dart
          avatar_intro_screen.dart
          avatar_selection_screen.dart
          avatar_confirm_screen.dart
      home/                     # Dashboard principal
        home_screen.dart
        widgets/                # carduri streak, obiectiv, CTA
      workouts/
        screens/
          workout_list_screen.dart
          workout_tracker_screen.dart
        widgets/
      ranks/
        screens/
          ranks_screen.dart
          rank_explain_screen.dart
      profile/
        screens/
          profile_screen.dart
          profile_edit_screen.dart   # date fizice, etc.
        widgets/
      social/
        screens/
          feed_screen.dart
      settings/                 # Reminder, Health, Strava, Unități, etc.
        screens/
      premium/                   # Paywall, trial
        screens/

    shared/                     # Componente refolosite peste tot
      widgets/
        main_button.dart
        section_card.dart
      services/
        auth_service.dart
        profile_service.dart
```

**Reguli:**  
- **features/** = câte un folder per „zonă” din diagramă (auth, entry, onboarding, home, workouts, ranks, profile, social, settings, premium).  
- În fiecare feature: **screens/** (ecrane), eventual **widgets/** și **services/** dacă sunt specifice.  
- **core/** = theme, config, l10n.  
- **shared/** = componente UI și servicii folosite în mai multe features.  
- **Un ecran principal** = unul din `features/home/` (HomeScreen), restul sunt ecrane secundare sau flow-uri.

Dacă vrei să simplifici la început, poți păstra doar:  
`core/`, `shared/`, `features/auth/`, `features/entry/`, `features/onboarding/`, `features/home/` (aici pui și MainScreen până ai tab bar), `features/workouts/`, `features/ranks/`, `features/profile/`.  
Social, settings, premium le adaugi când le implementezi.

---

## 8. Rezumat rapid

| Întrebare | Răspuns |
|-----------|---------|
| **Ce e principal?** | Un singur ecran: **Home** (dashboard cu streak, obiectiv, „Start workout”). |
| **Cum ajung la restul?** | **Bottom navigation**: Home, Workouts, Ranks, Profil (și opțional Feed). Restul (Exercises, Setări, Premium, etc.) din Profil/Setări. |
| **Multiple home screen-uri sau unul?** | **Unul**. Restul sunt tab-uri sau sub-ecrane. |
| **Dropdown-uri?** | Da, pentru filtre/opțiuni în ecrane (ex: Ranks, Workouts), nu pentru navigarea principală. |
| **Cum organizez folderele?** | **Feature-first**: `core/`, `shared/`, `features/<auth|entry|onboarding|home|workouts|ranks|profile|...>`. |
| **Pentru mâine** | Folosește **checklist-ul** din secțiunea 6 pe app-ul de referință și notează ce vă place la structura lor; apoi aliniați Zvelt la varianta A (tab bar) sau B (meniu), cu acest doc ca bază. |

Dacă vrei, putem urca un pas și să desenăm **exact** ecranul Home (ce carduri, ce butoane) și ce conține fiecare tab, ca să ai și wireframe-ul mental pentru discuție cu prietenul.
