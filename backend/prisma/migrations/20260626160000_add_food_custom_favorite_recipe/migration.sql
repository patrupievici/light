-- Food MyFitnessPal-parity: user-created foods, starred favorites, and recipes.
-- Macros are canonical per-100g to match the diary FoodItem shape. All cascade
-- on user delete (GDPR erasure). Recent foods are DERIVED from diary history
-- (no table); quick-add + copy-day are client-side over the existing diary API.

CREATE TABLE IF NOT EXISTS "user_custom_foods" (
  "id"                TEXT NOT NULL,
  "user_id"           TEXT NOT NULL,
  "name"              VARCHAR(120) NOT NULL,
  "brand"             VARCHAR(120),
  "calories_per_100g" DOUBLE PRECISION NOT NULL,
  "protein_per_100g"  DOUBLE PRECISION NOT NULL,
  "carbs_per_100g"    DOUBLE PRECISION NOT NULL,
  "fat_per_100g"      DOUBLE PRECISION NOT NULL,
  "serving_grams"     DOUBLE PRECISION,
  "serving_label"     VARCHAR(60),
  "created_at"        TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at"        TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "user_custom_foods_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "user_custom_foods_user_id_idx" ON "user_custom_foods" ("user_id");

CREATE TABLE IF NOT EXISTS "user_favorite_foods" (
  "id"                TEXT NOT NULL,
  "user_id"           TEXT NOT NULL,
  "food_id"           VARCHAR(120) NOT NULL,
  "name"              VARCHAR(120) NOT NULL,
  "brand"             VARCHAR(120),
  "calories_per_100g" DOUBLE PRECISION NOT NULL,
  "protein_per_100g"  DOUBLE PRECISION NOT NULL,
  "carbs_per_100g"    DOUBLE PRECISION NOT NULL,
  "fat_per_100g"      DOUBLE PRECISION NOT NULL,
  "serving_grams"     DOUBLE PRECISION,
  "created_at"        TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "user_favorite_foods_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "user_favorite_foods_user_id_food_id_key" ON "user_favorite_foods" ("user_id", "food_id");
CREATE INDEX IF NOT EXISTS "user_favorite_foods_user_id_idx" ON "user_favorite_foods" ("user_id");

CREATE TABLE IF NOT EXISTS "user_recipes" (
  "id"               TEXT NOT NULL,
  "user_id"          TEXT NOT NULL,
  "name"             VARCHAR(120) NOT NULL,
  "ingredients_json" JSONB NOT NULL,
  "servings"         INTEGER NOT NULL DEFAULT 1,
  "total_calories"   DOUBLE PRECISION NOT NULL,
  "total_protein"    DOUBLE PRECISION NOT NULL,
  "total_carbs"      DOUBLE PRECISION NOT NULL,
  "total_fat"        DOUBLE PRECISION NOT NULL,
  "created_at"       TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at"       TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "user_recipes_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "user_recipes_user_id_idx" ON "user_recipes" ("user_id");

ALTER TABLE "user_custom_foods"   DROP CONSTRAINT IF EXISTS "user_custom_foods_user_id_fkey";
ALTER TABLE "user_custom_foods"   ADD CONSTRAINT "user_custom_foods_user_id_fkey"   FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "user_favorite_foods" DROP CONSTRAINT IF EXISTS "user_favorite_foods_user_id_fkey";
ALTER TABLE "user_favorite_foods" ADD CONSTRAINT "user_favorite_foods_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "user_recipes"        DROP CONSTRAINT IF EXISTS "user_recipes_user_id_fkey";
ALTER TABLE "user_recipes"        ADD CONSTRAINT "user_recipes_user_id_fkey"        FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
