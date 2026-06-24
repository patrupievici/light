-- Anti-cheat set-edit audit trail + per-type health consent ledger.
-- Additive only: new tables + indexes. No column drops/renames.

-- ─── set_edit_audits ──────────────────────────────────────────────────────────
CREATE TABLE "set_edit_audits" (
    "id" TEXT NOT NULL,
    "set_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "workout_id" TEXT NOT NULL,
    "before" JSONB NOT NULL,
    "after" JSONB NOT NULL,
    "note" VARCHAR(500),
    "flagged" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "set_edit_audits_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "set_edit_audits_user_id_created_at_idx" ON "set_edit_audits"("user_id", "created_at" DESC);
CREATE INDEX "set_edit_audits_set_id_idx" ON "set_edit_audits"("set_id");

ALTER TABLE "set_edit_audits"
    ADD CONSTRAINT "set_edit_audits_set_id_fkey"
    FOREIGN KEY ("set_id") REFERENCES "workout_sets"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ─── health_consents ──────────────────────────────────────────────────────────
CREATE TABLE "health_consents" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "consent_type" VARCHAR(64) NOT NULL,
    "granted" BOOLEAN NOT NULL DEFAULT true,
    "consent_version" VARCHAR(16) NOT NULL DEFAULT '1',
    "source" VARCHAR(32),
    "granted_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revoked_at" TIMESTAMP(3),

    CONSTRAINT "health_consents_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "health_consents_user_id_consent_type_key" ON "health_consents"("user_id", "consent_type");
CREATE INDEX "health_consents_user_id_idx" ON "health_consents"("user_id");

ALTER TABLE "health_consents"
    ADD CONSTRAINT "health_consents_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
