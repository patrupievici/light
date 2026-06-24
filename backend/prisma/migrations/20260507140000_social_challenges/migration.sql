-- Social challenges — creator_id aligns with TEXT user ids from Prisma.
CREATE TABLE "challenges" (
    "id" TEXT NOT NULL,
    "creator_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "custom_title" VARCHAR(200),
    "visibility" TEXT NOT NULL,
    "target_hint" VARCHAR(120),
    "duration_days" INTEGER NOT NULL,
    "ends_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "challenges_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "challenges_creator_id_ends_at_idx" ON "challenges"("creator_id", "ends_at");
CREATE INDEX "challenges_visibility_ends_at_idx" ON "challenges"("visibility", "ends_at");

ALTER TABLE "challenges" ADD CONSTRAINT "challenges_creator_id_fkey" FOREIGN KEY ("creator_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
