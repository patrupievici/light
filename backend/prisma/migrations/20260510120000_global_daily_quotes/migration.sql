CREATE TABLE IF NOT EXISTS "global_daily_quotes" (
  "calendar_day" VARCHAR(10) NOT NULL,
  "quote" TEXT NOT NULL,
  "author" VARCHAR(120) NOT NULL DEFAULT 'Zvelt Coach',
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "global_daily_quotes_pkey" PRIMARY KEY ("calendar_day")
);
