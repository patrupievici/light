# Backend Deployment Verification

Render deploys the backend from GitHub `main`. The startup command applies
pending Prisma migrations before starting `dist/server.js`.

Release verification:

```powershell
npm.cmd run build
npm.cmd test
npm.cmd audit --omit=dev
npm.cmd run smoke:production
```

`GET /health` returns the active `release` commit prefix. Do not run production
smoke tests until that value matches the commit being verified.

User media is authorization-gated at `/uploads/*` and stored durably in the
`stored_media` PostgreSQL table. A deployment check should upload an avatar,
wait for a later release, fetch the same URL with its bearer session, and then
delete the test account.
