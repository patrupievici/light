# Zvelt — Schelet logic (fără grafică, animații, sunet)

**Scop:** Lista exactă de ecrane, ce conțin (minim) și cum treci de la unul la altul. Pentru aliniere cu prietenul și pentru implementare „gol” (doar structură + navigare).

---

## 1. Lista ecranelor (ID + nume)

| ID | Nume ecran | Scop (1 frază) |
|----|------------|----------------|
| **ENTRY** | | |
| E1 | Start | Primul ecran: branding, CTA „Get started”. |
| E2 | Welcome | Mesaj scurt, CTA „Continue”. |
| E3 | Login | Email + parolă, opțiune Google (și Apple dacă e cazul), link Sign up. |
| E4 | Sign up | Creare cont (email/Google/Apple), Terms & Privacy. |
| **ONBOARDING** (după login, o dată) | | |
| O1 | Onboarding concept 1 | Text + CTA „Continue”. |
| O2 | Onboarding concept 2 | Text + CTA „Continue”. |
| O3 | Onboarding concept 3 | Text + CTA „Continue”. |
| O4 | Chestionar start | Alegere unități (metric/imperial) + Continue. |
| O5 | Chestionar – grupe musculare | Select carduri, Continue. |
| O6 | Chestionar – obiectiv | Select obiectiv, Continue. |
| O7 | Chestionar – gen | Select gen, Continue. |
| O8 | Chestionar – înălțime | Input înălțime, Continue. |
| O9 | Chestionar – greutate | Input greutate, Continue. |
| O10 | Chestionar – vârstă | Input vârstă, Continue. |
| O11 | Chestionar – final | Mesaj + CTA „Let’s go”. |
| O12 | Avatar intro | Text despre avatar + Continue. |
| O13 | Avatar select | Grid opțiuni, select una, Next. |
| O14 | Avatar confirm | Confirmare + Continue. |
| O15 | Plan antrenament – ai plan? | Da/Nu + Continue. |
| O16 | Plan – loc | Unde te antrenezi (skip). |
| O17 | Plan – echipament | Multi-select echipament (skip). |
| O18 | Plan – durată | Durată sesiune (skip). |
| O19 | Plan – zile/săpt | Câte ori pe săpt (skip). |
| O20 | Reminder | Remind me / Maybe later. |
| O21 | Health permisiuni | Intro + cerere permisiuni (skip ok). |
| **MAIN APP** (tab bar) | | |
| M1 | Home | Dashboard: streak, obiectiv, date recente, CTA Start workout, Discover. |
| M2 | Workouts | Listă antrenamente + buton New/Start. |
| M3 | Ranks | Listă/dashboard rank + explain per exercițiu. |
| M4 | Profile | Listă secțiuni: Date fizice, Consistență, Dietă, Somn, Avatar, Setări. |
| **WORKOUTS** | | |
| W1 | Workout list | Listă workout-uri (sau gol); buton „New workout”. |
| W2 | Workout tracker | Exerciții + sets (weight, reps, RPE); Complete. |
| W3 | Workout detail | Detalii un workout (opțional, sau merge cu W1). |
| **RANKS** | | |
| R1 | Ranks overview | Scor total, top exerciții, tier. |
| R2 | Rank explain | „De ce” acest scor pentru un exercițiu. |
| **PROFILE & SUB** | | |
| P1 | Profile main | Vezi M4. |
| P2 | Profile – date fizice | Vârstă, greutate, înălțime (input/slider), Save. |
| P3 | Profile – consistență | Scor consistență (afișare). |
| P4 | Profile – dietă | Dietă recomandată (afișare / simplu). |
| P5 | Profile – somn | Ore somn (input sau afișare). |
| P6 | Profile – avatar | Schimbare avatar (reutilizare O12–O14). |
| P7 | Setări | Listă: Unități, Privacy, Reminder, Health, Strava, Premium, Log out. |
| **SOCIAL** | | |
| S1 | Feed | Listă posturi (prieteni); like, comentarii. |
| S2 | Post detail | Un post + comentarii. |
| **PREMIUM / ALTELE** | | |
| X1 | Paywall / Premium | Plan lunar/anual, beneficii, CTA. |
| X2 | Bodyrank explainer | Ce e Bodyrank, cum se construiește (1–3 ecrane). |
| X3 | Exercises list | Listă exerciții (global + custom). |
| X4 | Strava connect | Conectare Strava (OAuth). |

---

## 2. Conținut minim per ecran (ce există, fără design)

Doar tipuri de elemente. Fără culori, fonturi, animații.

- **E1 Start:** Titlu app, tagline, 1 buton (Get started).
- **E2 Welcome:** Titlu, text scurt, 1 buton (Continue).
- **E3 Login:** 2 câmpuri (email, parolă), 1 buton (Login), 1 link (Sign up), opțiune (Continue with Google).
- **E4 Sign up:** Câmpuri/link-uri sign up, Terms/Privacy, Submit.
- **O1–O3:** Titlu, text, 1 buton (Continue).
- **O4:** Select unități, Continue.
- **O5–O7, O12–O14:** Select (carduri sau listă), Continue/Next.
- **O8–O10:** Input numeric + unitate, Continue.
- **O11:** Text, buton Let’s go.
- **O15:** 2 opțiuni (Da/Nu), Continue.
- **O16–O19, O20, O21:** Input/select + Skip sau Continue.
- **M1 Home:** Text/valori: streak, obiectiv, „date recente” (listă scurtă sau placeholder). 1 buton mare (Start workout). Secțiune Discover (listă sau link).
- **M2 Workouts:** Listă (items sau gol), 1 buton (New workout / Start).
- **M3 Ranks:** Valori: scor, tier; listă exerciții cu scor; tap pe unul → explain.
- **M4 Profile:** Listă rânduri: Date fizice → P2, Consistență → P3, Dietă → P4, Somn → P5, Avatar → P6, Setări → P7.
- **W1:** Listă workout-uri, buton New.
- **W2:** Listă exerciții; per exercițiu: listă sets (weight, reps, RPE); buton Complete.
- **P2:** Câmpuri/slidere: vârstă, greutate, înălțime; Save.
- **P3, P4, P5:** Text/valori afișate (poate și input pentru P5).
- **P7:** Listă: Unități, Privacy, Reminder, Health, Strava, Premium, Log out; fiecare → ecran sau acțiune.
- **S1:** Listă posturi; fiecare → like, comentarii, tap → S2.
- **X1:** Text beneficii, prețuri, CTA Subscribe.
- **X2:** 1–3 ecrane text + Continue.
- **X3:** Listă exerciții, opțional Add custom.
- **X4:** Buton Connect Strava, status.

---

## 3. Harta de navigare (de unde pleci → unde ajungi)

**Reguli:**  
- „→” = un tap (buton sau item în listă).  
- Tab bar = M1, M2, M3, M4 mereu accesibile când ești în „main app”.

```
APP LAUNCH
  └─ [fără token] → E1 → E2 → E3 (sau E4)
       E3 → E4 (Sign up)
       E3 / E4 [success] → O1
  └─ [cu token, onboarding neterminat] → O1

ONBOARDING (secvențial)
  O1 → O2 → O3 → O4 → O5 → O6 → O7 → O8 → O9 → O10 → O11
  O11 → O12 → O13 → O14
  O14 → O15 → O16 → O17 → O18 → O19 (skip-uri posibile)
  O19 → O20 → O21 (skip-uri posibile)
  O21 [done] → M1 (Home)

MAIN APP (tab bar: Home | Workouts | Ranks | Profile)
  M1 (Home)
    ├─ buton „Start workout” → W2 (tracker) sau W1
    ├─ Discover / item → S1 sau post
    └─ (alte link-uri pe Home)
  M2 (Workouts)
    ├─ buton New / Start → W2
    └─ item listă → W3 sau W2
  M3 (Ranks)
    └─ item exercițiu → R2 (explain)
  M4 (Profile)
    ├─ Date fizice → P2
    ├─ Consistență → P3
    ├─ Dietă → P4
    ├─ Somn → P5
    ├─ Avatar → P6 (sau O12–O14)
    └─ Setări → P7

W1 (Workout list)
  └─ New → W2
  └─ item → W3 sau W2

W2 (Tracker)
  └─ Complete → înapoi la W1 sau M2 (sau dialog Post?)

P2, P3, P4, P5, P6
  └─ Back / Save → M4 (Profile)

P7 (Setări)
  ├─ Unități → ecran select
  ├─ Privacy → ecran select
  ├─ Reminder → O20 sau ecran
  ├─ Health → O21 sau ecran
  ├─ Strava → X4
  ├─ Premium → X1
  └─ Log out → E3 (și clear token)

S1 (Feed)
  └─ item post → S2

R2, X1, X2, X3, X4
  └─ Back → ecranul anterior
```

---

## 4. Ordinea de implementare schelet (recomandat)

Fără grafică/detalii, doar ecrane goale + navigare.

1. **Entry:** E1 → E2 → E3 (E4 opțional); după login → O1.
2. **Onboarding scurt:** O1 → O2 → O3 → O14 (să sari chestionarul la început) → M1.
3. **Main app:** Tab bar cu M1, M2, M3, M4; fiecare ecran = titlu + text placeholder.
4. **Profile sub-ecrane:** M4 listă rânduri; P2, P7 implementate minimal (restul „coming soon”).
5. **Workouts:** W1 (listă goală) + W2 (placeholder exerciții/sets) + buton Complete → înapoi.
6. **Ranks:** M3 placeholder; R2 simplu (titlu + text).
7. **Restul:** S1, X1, X2, X3, X4, P3–P6 ca ecrane goale cu Back.

După ce acest schelet rulează și prietenul confirmă flow-ul, adaugi date reale (API), apoi grafica și detaliile.

---

## 5. Ce NU face parte din schelet

- Illustrații, imagini, iconițe fancy.  
- Animații, tranziții (poți folosi push/pop simple).  
- Sunet.  
- Validări complexe (poți lăsa required câmpuri, fără mesaje elaborate).  
- Stil vizual (culori/fonturi doar ca să fie lizibil, nu design final).  
- Conținut real (poți folosi „Streak: --”, „Obiectiv: --”, listă goală).

---

## 6. Rezumat pentru mâine

- **Ecrane:** ~45 de „ecrane” logice (mulți sunt pași în flow-uri: onboarding, chestionar, profil).  
- **După login:** Tab bar cu 4 tab-uri: Home, Workouts, Ranks, Profile.  
- **Home** = punct central; Workouts = listă + tracker; Ranks = overview + explain; Profile = hub către date fizice, consistență, dietă, somn, setări.  
- **Navigare:** doar butoane și liste; fără meniu dropdown pentru navigarea principală.  
- **Implementare:** mai întâi entry + onboarding scurt + tab bar + ecrane goale; apoi profile sub-ecrane, workouts, ranks; la final feed, premium, Strava, etc.

Cu acest doc poți verifica mâine cu prietenul: „Uite lista de ecrane și flow-ul; ce schimbăm sau ce lipsește?” După confirmare, implementezi scheletul în cod (ecrane goale + navigare), apoi completezi cu logică și date.

---

## 7. Schelet în cod (deja implementat)

În proiect există deja un **schelet minimal** pentru main app:

- **MainScreen** = shell cu **bottom navigation** (4 tab-uri): Home | Workouts | Ranks | Profile.
- **Tab-uri:**
  - **Home (M1):** Streak/Objective placeholders, buton „Start workout” (duce la tab Workouts).
  - **Workouts (M2):** Text „No workouts yet”, buton „New workout” (placeholder).
  - **Ranks (M3):** Rank/Tier placeholders, buton „Explain rank” (placeholder).
  - **Profile (M4):** Listă secțiuni: Date fizice → deschide ecranul existent (greutate/înălțime); Consistență, Dietă, Somn, Avatar, Setări → placeholder; Log out.
- **Fișiere:** `screens/main_screen.dart` (shell + IndexedStack), `screens/skeleton/skeleton_*_tab.dart` (câte unul per tab).

Mâine poți rula app-ul, parcurge tab-urile și lista din Profile și verifica cu prietenul dacă structura și flow-ul sunt ok. Apoi extinzi treptat (ecrane noi, API, etc.) fără grafică/animatii la început.
