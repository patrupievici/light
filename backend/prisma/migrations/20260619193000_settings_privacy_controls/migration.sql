ALTER TABLE "user_profiles"
  ADD COLUMN "feed_friends_only" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN "discovery_opt_in" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "dm_friends_only" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN "show_body_stats" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN "show_activity_feed" BOOLEAN NOT NULL DEFAULT true;
