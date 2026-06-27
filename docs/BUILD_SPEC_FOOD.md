# Zvelt — Food Build Spec (MyFitnessPal parity)

Status: **Phase 1 done** (2026-06-26). Backend: UserCustomFood/UserFavoriteFood/UserRecipe
models + migration; `/v1/nutrition` routes (custom-foods CRUD, favorite-foods add/list/delete,
recipes CRUD with server-computed totals, recent-foods derived from diary) in
`src/routes/nutrition-foods.ts`. Verified: tsc clean, prisma valid, 732 backend tests (incl.
10 new route tests). Next: P2 Flutter service → P3 add-food sheet → P4 recipe builder + copy-day.

Brings the Food tab to ~80-90% MyFitnessPal on top of the existing nutrition stack
(USDA+OFF search, barcode, meal diary, macro goals, water/weight, AI weekly plan,
offline-first sync, meal-template backend). ~60% → parity.

## Decisions (locked with user)
- **Full logging pack:** recent + favorite + custom foods, quick-add calories, copy day/meal, recipe builder, + wire the existing meal-template backend to a UI.
- **Data source:** Open Food Facts prioritized for barcoded/EU products + USDA for generic (today USDA is primary; flip the merge so OFF leads for branded/barcode).
- **Custom foods + recipes:** yes, both (new DB models).
- **Macros only:** calories + protein/carbs/fat. No micronutrients.

## Storage strategy
- **Custom foods / favorites / recipes → backend tables** (durable, cross-device).
- **Recent foods → derived from diary history** (no new table; query recent NutritionLogDay entries, dedup by name+brand, recency-sorted).
- **Quick-add + copy day/meal → client-side** (reuse existing `addEntry` / `PUT /day`).
- **Meal templates → already on backend**; just build the UI.

## New DB models (Phase 1)
```
UserCustomFood   { id, userId FK, name, brand?, {cal,protein,carbs,fat}Per100g, servingGrams?, servingLabel?, created/updated }  @@index(userId)
UserFavoriteFood { id, userId FK, foodId (off:|usda_fdc_|custom:UUID), name, brand?, {..}Per100g, servingGrams?, created }       @@unique(userId,foodId)
UserRecipe       { id, userId FK, name, ingredientsJson [{name,grams,..Per100g}], servings, total{Cal,Protein,Carbs,Fat}, created/updated } @@index(userId)
```
All cascade on user delete (+ GDPR erasure allowlist). Diary entries may reference
`foodId='custom:UUID'` (resolved client-side from the user's custom catalog).

## Backend routes (Phase 1) — prefix `/v1/nutrition`
- `GET/POST/PUT/DELETE /custom-foods` — user custom food catalog.
- `GET /favorite-foods`, `POST /favorite-foods` (add), `DELETE /favorite-foods/:foodId` (toggle off).
- `GET/POST/PUT/DELETE /recipes` + `POST /recipes/:id/apply { date, servings, meal? }`.
- `GET /recent-foods?limit=20` — derived from diary history.
- (templates GET/POST/DELETE/apply already exist — UI only.)
All Zod-validated, Bearer auth, error shape `{error,message,request_id}`. Macros are
canonical per-100g (matches the diary FoodItem shape).

## Flutter (Phases 2-4)
- **P2 service:** extend `nutrition_service.dart` — models + methods for custom/favorite/recipe/recent/templates; flip search to OFF-first for branded/barcode.
- **P3 add-food sheet:** segmented tabs **Caută · Recente · Favorite · Custom** in `_AddFoodSheet`; star toggle on results; "Quick-add calorii" + "Creează aliment custom" entries; wire templates list ("Mesele mele") + apply.
- **P4 recipes + copy:** recipe builder screen (pick ingredients → live macro rollup → save → apply N servings); copy-day / duplicate-meal action; save-current-day-as-template.

## Phases
P1 backend (models+migration+routes+tests) → P2 Flutter service → P3 add-food sheet
(recent/favorites/custom/quick-add/templates) → P4 recipe builder + copy-day → P5
adversarial review + verify.

## Verification gate per phase
Backend: `tsc` + `vitest` + `prisma validate` (+ migration file). App: `flutter analyze` + `flutter test` + `flutter build apk --release`.
