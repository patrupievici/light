ALTER TABLE "activities"
    ADD COLUMN "activity_type" VARCHAR(16);

ALTER TABLE "activities"
    ADD CONSTRAINT "activities_activity_type_check"
    CHECK ("activity_type" IS NULL OR "activity_type" IN ('run', 'ride', 'walk', 'swim', 'cardio'));
