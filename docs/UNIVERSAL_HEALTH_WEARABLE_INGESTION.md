# Universal Health + Wearable Ingestion

## Decision

Zvelt uses multiple health data paths:

- Health Connect / Apple Health for immediate on-device permission and recent foreground backfill.
- Terra as the primary cloud wearable aggregator for deep history and phone-independent reliability.
- Huawei-specific fallback through aggregator support, Health Sync bridge, or a future HMS Health Kit module.

Do not add direct vendor SDKs for Garmin/Fitbit/Oura/etc. The aggregator path owns that layer.

## First Connect

After native health permission is granted, run a foreground historical backfill immediately (first requesting `READ_HEALTH_DATA_HISTORY` so reads aren't clipped to 30 days on Android 14+).

Current app behavior:

- `HealthService.backfillRecentOnFirstGrant()` (requests historical access first)
- default window: ~90 days (`kRecentBackfillWindow`)
- local encrypted cache: `zvelt_health_records.db`
- source metadata: `source_path`, `provider`, `external_id`

A foreground import on first grant is much more reliable on Oppo, Realme, Xiaomi, Vivo, and other aggressive Android builds than waiting for background work.

## Deep History

The on-device first-grant backfill now pulls **~90 days** (`kRecentBackfillWindow`) and requests `READ_HEALTH_DATA_HISTORY` (`HealthService.requestHistoricalAccess()`) before reading, because Android 14+ silently clips Health Connect reads to the last 30 days without it. The persisted rows are surfaced in the **Imported history** screen (`ImportedHistoryScreen`, reachable from the Health screen). Even deeper / cross-vendor wearable history (beyond what the phone's Health Connect holds) still belongs to the future cloud aggregator path.

Reasons:

- Health Connect older-than-30-day behavior depends on Android version and extra user/source permissions.
- Huawei phones without Google services cannot use Health Connect normally.
- Aggregator webhooks continue server-to-server even if the phone kills background work.

## Backend Prep

Prepared routes:

- `GET /v1/integrations`
- `GET /v1/integrations/:provider/auth-url` backed by Terra direct provider authentication when credentials exist
- `POST /v1/integrations/:provider/sync`
- `DELETE /v1/integrations/:provider`
- `POST /v1/integrations/aggregator/webhook` with Terra `terra-signature` verification when `TERRA_WEBHOOK_SECRET` is set
- Terra data webhooks are persisted into `user_health_imports` as raw/semi-normalized records keyed by source/provider/type/external id

Prepared Prisma tables:

- `wearable_connections`
- `user_health_imports`
- `user_health_daily_metrics`

The routes intentionally return `AGGREGATOR_NOT_CONFIGURED` until Terra credentials are provided.

Required env:

```text
WEARABLE_AGGREGATOR_PROVIDER=terra
TERRA_DEV_ID=
TERRA_API_KEY=
TERRA_API_BASE_URL=https://api.tryterra.co/v2
TERRA_AUTH_SUCCESS_REDIRECT_URL=zvelt://integrations/terra/success
TERRA_AUTH_FAILURE_REDIRECT_URL=zvelt://integrations/terra/failure
TERRA_WEBHOOK_SECRET=
```

Spike remains the backup candidate if Terra coverage or commercial terms do not work for a required Huawei/provider path. ROOK stays third because Huawei-specific coverage needs to be verified before it can satisfy the "any phone" goal.

## Provider Coverage Target

Health Connect / Apple Health:

- Samsung Health / Galaxy Watch as a first-class path: Galaxy Watch syncs to Samsung Health on the phone, Samsung Health syncs to Health Connect, Zvelt reads Health Connect
- Fitbit / Pixel Watch where available
- other Android apps that write into Health Connect

Aggregator:

- Garmin
- Fitbit
- Oura
- Polar
- COROS
- WHOOP
- Suunto
- Withings
- Amazfit / Zepp
- Huawei Health when supported by selected provider

Huawei:

- Prefer aggregator with Huawei support.
- Otherwise use Health Sync bridge instructions.
- Only add native HMS Health Kit if product requirements demand it.

## Dedup Contract

Never double-count overlapping sources.

Stable import identity:

```text
user_id + source_path + provider + metric_type + external_id
```

Local Health Connect/Apple Health cache stores:

- source path
- inferred provider
- external id
- type
- start/end time
- value/unit
- raw payload JSON

Backend `user_health_imports` mirrors the same contract for aggregator and webhook imports.
