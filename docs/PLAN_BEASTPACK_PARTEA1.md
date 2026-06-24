# Plan implementare — Beast Pack / Primal Fitness (Partea 1)

Bazat pe slide-ul „Planning BeastPack Partea 1” (FIG.1–FIG.73). Obiectiv: implementare **unu câte unu**, în ordine logică și reutilizabilă.

---

## Principii de development (din slide)

- **Design system**: componente reutilizabile; state-uri definite: default, selected, disabled, loading, error.
- **Progres**: salvare după fiecare pas important (reluare ușoară).
- **Chestionar**: validare în timp real; CTA dezactivat până la input/selectie validă; Skip unde e cazul.
- **Carduri**: afișare clară, selectie evidentă (border/fill/glow); single/multi-select conform note-urilor.

---

## Faze de implementare

### **FAZA 0 — Pregătire (înainte de FIG)**

| # | Task | Descriere | Depinde de |
|---|------|------------|------------|
| 0.1 | Design system / theme | Tokeni vizuali (culori, fonturi, spacing, radius), componente de bază: butoane, carduri, input-uri, CTA (toate cu state-uri). | — |
| 0.2 | Model onboarding în backend | Tabel/schema pentru răspunsuri onboarding (grupe musculare, obiectiv, gen, înălțime, greutate, vârstă, echipament, etc.) legat de `user_profiles` sau user. | Backend existent |
| 0.3 | API salvare pas onboarding | Endpoint(e) pentru a salva pas cu pas răspunsurile (ex: `PATCH /v1/me/onboarding` sau per-pas). | 0.2 |

**Livrabil**: Theme + componente de bază în Flutter; backend poate persista onboarding; app-ul poate trimite răspunsuri.

---

### **FAZA 1 — Entry, auth și primul flow (FIG 1–4, 57–58)**

| # | FIG | Ecran | Prioritate | Note |
|---|-----|--------|------------|------|
| 1.1 | 1 | Ecran de start / identitate | P1 | Branding, CTA „Get Started” / „Continue”. Reutilizare componente din 0.1. |
| 1.2 | 2 | Ecran de bine venit | P1 | Similar cu 1; CTA „Continue”. |
| 1.3 | 4 | Introducere utilizatori noi | P1 | Flow pentru „noi”; CTA „Continue” → următorul pas (onboarding sau signup). |
| 1.4 | 3 | Login utilizatori existenți | P1 | Deja parțial implementat; aliniere la design nou (welcome back, trust). |
| 1.5 | 57 | Creare cont (Apple / Google / Email) | P1 | Unificare sign up: Apple, Google, Email. Terms & Privacy vizibile. |
| 1.6 | 58 | Confirmare creare profil | P2 | Confirmare vizuală + CTA „Continue”. |

**Ordine sugerată**: 0.1 → 1.1 → 1.2 → 1.3 → 1.4 → 1.5 → 1.6.  
**Livrabil**: Un flow clar: Start → Welcome → Intro → Login sau Sign up (Apple/Google/Email) → Confirmare profil.

---

### **FAZA 2 — Onboarding conceptual (FIG 5–7)**

| # | FIG | Ecran | Prioritate | Note |
|---|-----|--------|------------|------|
| 2.1 | 5 | Concept ranking pe grupe musculare | P1 | Un concept per ecran; text + exemplu vizual; CTA „Continue”. |
| 2.2 | 6 | App ca instrument pentru obiective | P1 | Beneficiu clar; CTA „Continue”. |
| 2.3 | 7 | Prezentare generală experiență | P1 | Overview; CTA „Continue”. |

**Ordine**: 2.1 → 2.2 → 2.3.  
**Livrabil**: Trei ecrane de „educație” înainte de chestionar, cu același pattern (titlu, mesaj, vizual, CTA).

---

### **FAZA 3 — Chestionar de personalizare (FIG 8–19)**

| # | FIG | Ecran | Tip | Prioritate |
|---|-----|--------|-----|------------|
| 3.1 | 8 | Începere chestionar | Input (unități) | P1 |
| 3.2 | 9 | Grupe musculare principale | Select (carduri) | P1 |
| 3.3 | 10 | Obiectiv principal fitness | Select | P1 |
| 3.4 | 11 | Confirmare motivatională obiectiv | Confirmare | P2 |
| 3.5 | 12 | Angajament personal (Tap and Hold Jymbo) | Interacțiune | P2 |
| 3.6 | 13 | Cum a aflat despre app | Select, Skip | P2 |
| 3.7 | 14 | Gen | Select | P1 |
| 3.8 | 15 | Înălțime | Input (unități) | P1 |
| 3.9 | 16 | Greutate curentă | Input (unități) | P1 |
| 3.10 | 17 | Vârstă | Input | P1 |
| 3.11 | 18–19 | Tranziții emotionale | Mesaj + CTA „Let's Go!” | P2 |

**Implementare**:  
- Un **widget reutilizabil** pentru „selectie din carduri” (FIG 9, 10, 13, 14).  
- Un **widget reutilizabil** pentru „input numeric + unități” (FIG 8, 15, 16, 17).  
- Persistență locală între pași + trimitere la backend la final sau per-pas (0.2, 0.3).  

**Ordine sugerată**: 3.1 → 3.2 → 3.3 → 3.7 → 3.8 → 3.9 → 3.10 → 3.4 → 3.5 → 3.6 → 3.11.  
**Livrabil**: Chestionar complet, cu salvare și validări.

---

### **FAZA 4 — Avatar (FIG 20–24)**

| # | FIG | Ecran | Prioritate |
|---|-----|--------|------------|
| 4.1 | 20–22 | Intro avatar + progres + personalizare | P2 |
| 4.2 | 23 | Alegere avatar de start | P1 |
| 4.3 | 24 | Confirmare avatar | P2 |

**Note**: Avatarul poate fi un set de imagini/icone; selectie single din carduri (același pattern ca la chestionar).  
**Livrabil**: Flow scurt intro → alegere → confirmare; salvare în profil.

---

### **FAZA 5 — Plan și context antrenament (FIG 25–30)**

| # | FIG | Ecran | Prioritate |
|---|-----|--------|------------|
| 5.1 | 25 | Există plan de antrenament? | P1 |
| 5.2 | 26 | Confirmare plan | P2 |
| 5.3 | 27 | Unde se antrenează | P1 (Skip) |
| 5.4 | 28 | Echipamente disponibile | P1 (multi-select) |
| 5.5 | 29 | Durata obișnuită antrenament | P1 (Skip) |
| 5.6 | 30 | Câte ori pe săptămână | P1 (Skip) |

**Backend**: Extindere profil/onboarding cu: `has_plan`, `training_location`, `equipment[]`, `session_duration`, `sessions_per_week`.  
**Livrabil**: Date suficiente pentru personalizare și (ulterior) workout generator.

---

### **FAZA 6 — Reminder și widget (FIG 31–35)**

| # | FIG | Ecran | Prioritate |
|---|-----|--------|------------|
| 6.1 | 31 | Reminder zile active | P1 (Remind Me / Maybe Later) |
| 6.2 | 32–35 | Setup widget (suport, long press, Add Widget, search Liftoff) | P2 |

**Note**: Reminder = permisiuni notificări + salvare preferință oră. Widget = instructiuni step-by-step; platform-specific (Android/iOS).  
**Livrabil**: Utilizatorul poate seta reminder; poate parcurge flow-ul de setup widget (instructiuni).

---

### **FAZA 7 — Primul rank și procesare (FIG 36–40)**

| # | FIG | Ecran | Prioritate |
|---|-----|--------|------------|
| 7.1 | 36 | Tranziție către primul rank | P2 |
| 7.2 | 37 | Primul rank obținut | P1 |
| 7.3 | 38 | Predicție progres | P2 |
| 7.4 | 39 | Alegere Pro vs Free | P1 |
| 7.5 | 40 | Procesare profil + calcul | P1 |

**Note**: Rank-uri există deja în backend (Zvelt). „Procesare profil” = loading steps vizual; la final, redirect către Bodyrank explainer sau Home.  
**Livrabil**: Primul rank afișat; mini-flow Pro vs Free; ecran de procesare.

---

### **FAZA 8 — Bodyrank explainer și trial (FIG 41–44)**

| # | FIG | Ecran | Prioritate |
|---|-----|--------|------------|
| 8.1 | 41 | Ce este Bodyrank | P1 |
| 8.2 | 42 | Cum se construiește Bodyrank | P1 |
| 8.3 | 43 | Focus grupe slabe | P1 |
| 8.4 | 44 | Trial gratuit pentru rank | P1 |

**Livrabil**: Utilizatorul înțelege Bodyrank; ofertă trial clară.

---

### **FAZA 9 — Premium / paywall (FIG 45–49, 62–68)**

| # | FIG | Ecran | Prioritate |
|---|-----|--------|------------|
| 9.1 | 45–49 | Trial, reminder trial, timeline billing, selectare plan, confirmare | P1 |
| 9.2 | 62–68 | Intro Pro, beneficii (fără reclame, rank, generator, Calorie Lens, identity, commitment) | P1 |

**Note**: Integrare RevenueCat (sau similar); afișare prețuri locale; A/B test pe ordine/beneficii.  
**Livrabil**: Flow complet de trial și subscribe; ecrane beneficii Pro reutilizabile.

---

### **FAZA 10 — Streak (FIG 50–52)**

| # | FIG | Ecran | Prioritate |
|---|-----|--------|------------|
| 10.1 | 50 | Primul workout streak | P1 |
| 10.2 | 51 | Alegere streak goal | P1 |
| 10.3 | 52 | Confirmare streak goal | P2 |

**Backend**: Streak există parțial în Zvelt; goal streak (ex: 3/5/7 zile) salvat în profil.  
**Livrabil**: Streak afișat; utilizatorul alege un goal și confirmă.

---

### **FAZA 11 — Health / Apple Health & Android Health Connect (FIG 53–56)**

| # | FIG | Ecran | Prioritate |
|---|-----|--------|------------|
| 11.1 | 53 | Intro Health Connect | P1 |
| 11.2 | 54–56 | Cerere permisiuni (initial, write, read) | P1 |

**Note**: Explicativ înainte de dialog nativ; tratare refuz + fallback; reluare din setări.  
**Livrabil**: Flow clar pentru permisiuni Health; app funcționează și fără (fallback).

---

### **FAZA 12 — Post-onboarding și Home (FIG 59–61, 69–73)**

| # | FIG | Ecran | Prioritate |
|---|-----|--------|------------|
| 12.1 | 59 | Plan primele 30 zile | P2 |
| 12.2 | 60 | Adăugare streak widget | P2 |
| 12.3 | 61 | Conectare Strava | P2 |
| 12.4 | 69 | Home dashboard după onboarding | P1 |
| 12.5 | 70 | Monitorizare obiectiv + date recente | P1 |
| 12.6 | 71 | Discover section pe Home | P2 |
| 12.7 | 72 | Pagină Workout / Tracker | P1 |
| 12.8 | 73 | Listă rutine + Start | P1 |

**Note**: Home = carduri modulare, skeleton/empty states; navigare inferioară stabilă. Workout/Tracker și listă rutine se leagă de API-urile existente Zvelt.  
**Livrabil**: Utilizatorul ajunge pe Home complet; poate vedea streak, obiectiv, discover; poate deschide Workout și lista de rutine și porni un workout.

---

## Ordine recomandată (rezumat)

1. **Faza 0** — Design system + model/API onboarding.  
2. **Faza 1** — Entry + auth (FIG 1–4, 57–58).  
3. **Faza 2** — Concept (FIG 5–7).  
4. **Faza 3** — Chestionar (FIG 8–19).  
5. **Faza 4** — Avatar (FIG 20–24).  
6. **Faza 5** — Plan și context (FIG 25–30).  
7. **Faza 6** — Reminder + widget (FIG 31–35).  
8. **Faza 7** — Primul rank + procesare (FIG 36–40).  
9. **Faza 8** — Bodyrank + trial (FIG 41–44).  
10. **Faza 9** — Premium / paywall (FIG 45–49, 62–68).  
11. **Faza 10** — Streak (FIG 50–52).  
12. **Faza 11** — Health (FIG 53–56).  
13. **Faza 12** — Home și Workout (FIG 59–61, 69–73).

---

## Cum lucrăm „unu câte unu”

- La fiecare **FIG** (sau grup de FIG-uri foarte apropiate) definim:  
  - **Task-uri clare** (UI + eventual backend).  
  - **Acceptance**: ce vede/utilizatorul face.  
- După fiecare livrabil: build, test pe device/emulator, apoi trecem la următorul.  
- Design system (Faza 0) se folosește de la FIG 1 încolo; îl putem refina incremental.

Dacă vrei, următorul pas concret poate fi: **Faza 0** (design system + schema onboarding) sau **FIG 1** (ecran de start), și îți scriu pașii exact de cod pentru proiectul tău Zvelt/Flutter + backend.
