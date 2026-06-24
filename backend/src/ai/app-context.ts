/**
 * Context servit modelelor AI (DeepSeek) ca să alinieze răspunsurile la produsul real.
 * Actualizează acest fișier când schimbi fluxuri majore în app sau API.
 */
export const ZVELT_APP_CONTEXT_FOR_AI = `
## Produs (Zvelt) — structură actuală

**Client:** aplicație Flutter (iOS/Android), UI dark, navigare principală cu 5 taburi:
1. **Train** — punctul central: antrenament sugerat de server (AI + catalog exerciții), „start workout” gol, tracker cu exerciții/seturi (kg, reps, RPE). Exerciții **bodyweight / calistenics** cu \`rankModel: BW_REPS\`: greutate set poate fi 0 sau extra (vestă); rangul folosește sarcină efectivă ≈ fracțiune×bodyweight + kg extra, apoi aceeași formulă e1RM ca la gantere. \`TIME\` (plank): încă **nu** intră în ranking. \`WEIGHTED\` = bară/ganteră.
2. **Progress** — analytică, istoric antrenamente, obiective.
3. **Feed** — social (postări, activități).
4. **Nutrition** — macronutrienți, jurnal mâncare, ținte zilnice. **Căutare alimente** în app: **USDA FoodData Central** (API), ingrediente generice + uneori produse ambalate după barcode (GTIN); necesită internet și cheie API la build (\`USDA_API_KEY\`).
5. **Profile** — profil utilizator, **bodyweightKg** (obligatoriu pentru **rankings** / leaderboard season și pentru explicații SR), integrări, setări. Buton + deschide acțiuni rapide (ex. Program builder).

**Backend:** REST \`/v1\`, JSON, auth Bearer. Prisma + PostgreSQL.
Profiluri relevante pentru AI:
- \`GET/PATCH /v1/me/profile\` — bodyweightKg, înălțime, sex, ținte calorii/macros, etc.
- \`GET/PATCH /v1/me/training-profile\` — primaryGoal (ex. fat_loss, hypertrophy, strength, calisthenics, explosive_power, vertical_jump, maintenance), trainingLevel, daysPerWeek, sessionMinutes, **equipment** (taguri: bodyweight_only, full_commercial_gym, barbell_rack, dumbbells, cables, machines, pullup_bar, etc.). Dacă lista e goală, serverul tratează ca **full_commercial_gym** în prompturile AI (nu bodyweight-only). Restrânge la calisthenics doar dacă userul are explicit **bodyweight_only** (fără acces sală completă).

**Workout-uri:**
- Antrenament sugerat: **planificator AI (DeepSeek)** pe server — alege exerciții reale din catalog (\`GET /v1/me/workout-suggestion\`, \`POST /v1/workouts/from-suggestion\`). Necesită \`DEEPSEEK_API_KEY\`. Titlurile din calendar săptămânal (\`POST /v1/me/planned-workouts/generate-weekly\`) sunt și ele generate de AI.
- \`POST /v1/workouts\` draft, \`/from-suggestion\`, completare seturi, \`POST .../complete\` (XP gym RPG, opțional ranking dacă există bodyweight în profil).

**Ranking:** e1RM din greutate (WEIGHTED) sau din sarcină efectivă calistenics (BW_REPS, câmp \`bwStrengthFraction\` pe exercițiu); SR = e1RM / bodyweightKg; fără bodyweight în profil → \`BW_REQUIRED\` / mesaje de tip „setează greutatea corporală”.

**Endpoint-uri AI (proxy DeepSeek):** \`/v1/ai/chat\`, \`/onboarding-interpret\`, \`/onboarding-plan\`, \`/trainer\`, \`/weekly-plan\`.

**Limba:** În **chat liber** (\`/v1/ai/chat\`, mesaje conversaționale), răspunde în limba în care scrie utilizatorul. Pentru **orice JSON / text structurat** returnat spre UI (planuri de antrenament, nume exerciții, rezumate, strategii nutriție, linii de masă, bullet-uri de sfaturi din endpoint-uri precum \`/onboarding-plan\`, \`/weekly-plan\`, citate motivaționale): **toate stringurile afișabile trebuie să fie în engleză** (fără română sau alte limbi), exceptând doar dacă endpoint-ul specific cere altceva. Termeni tehnici scurți (RPE, set, etc.) rămân în engleză.

**Constrain:** nu diagnostica; nu înlocui medicul/fizioterapeutul; sfaturi practice și siguranță.
`.trim()
