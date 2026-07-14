CREATE TABLE "stored_media" (
    "key" VARCHAR(512) NOT NULL,
    "owner_user_id" TEXT NOT NULL,
    "kind" VARCHAR(16) NOT NULL,
    "content_type" VARCHAR(32) NOT NULL,
    "data" BYTEA NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "stored_media_pkey" PRIMARY KEY ("key")
);

CREATE INDEX "stored_media_owner_user_id_kind_idx"
    ON "stored_media"("owner_user_id", "kind");

ALTER TABLE "stored_media"
    ADD CONSTRAINT "stored_media_owner_user_id_fkey"
    FOREIGN KEY ("owner_user_id") REFERENCES "users"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
