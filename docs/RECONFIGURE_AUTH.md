# Reconfiguring login / auth (your own Supabase & JWT)

Use this when you need to move from someone else’s Supabase/email to **your own** project (e.g. new Supabase project under your account).

---

## 1. Create your own Supabase project

1. Go to **[supabase.com](https://supabase.com)** and sign in with **your** account (your email).
2. Click **New project**.
3. Choose organization (or create one), name the project (e.g. `zvelt`), set a **database password** (save it somewhere safe), pick a region, then create.
4. Wait until the project is ready.

---

## 2. Get the database URLs

1. In the Supabase dashboard, open your project.
2. Go to **Settings** (gear) → **Database**.
3. Copy:
   - **Connection string → URI** (for pooled/transaction mode) → this is your `DATABASE_URL`.
   - **Connection string → Direct connection** (or the URI that uses port **5432** and no pooler) → this is your `DIRECT_URL`.

Replace the placeholder password in both URLs with your **database password** if it’s not already there.

- `DATABASE_URL` usually has a host like `aws-0-XX.pooler.supabase.com` and port **6543**.
- `DIRECT_URL` usually has a host like `db.XXXXX.supabase.co` and port **5432**.

---

## 3. Generate a new JWT secret

Use a long random string (e.g. 32+ characters). Example in PowerShell:

```powershell
[System.Convert]::ToBase64String((1..64 | ForEach-Object { [byte](Get-Random -Max 256) }))
```

Copy the output; you’ll use it as `JWT_SECRET`.

---

## 4. Update backend `.env`

1. Open `backend/.env` (create it from `backend/.env.example` if it doesn’t exist).
2. Set:

```env
DATABASE_URL="<paste your Supabase pooled URI here>"
DIRECT_URL="<paste your Supabase direct URI here>"
JWT_SECRET="<paste the generated secret here>"
JWT_EXPIRES_IN="15m"
REFRESH_TOKEN_EXPIRES_DAYS=30
PORT=3000
NODE_ENV=development
```

3. Save the file. Do **not** commit `.env` (it should be in `.gitignore`).

---

## 5. Apply schema and seed (new database)

From the project root:

```bash
cd backend
npm install
npm run db:generate
npm run db:push
npm run db:seed
```

- `db:push` applies the Prisma schema to your **new** Supabase database.
- `db:seed` inserts initial data (e.g. exercises, season) if you have a seed script.

---

## 6. Restart the backend

```bash
npm run dev
```

Backend will use the new database and new JWT secret. Existing tokens from the old project will be invalid (users must sign up or log in again).

---

## 7. Update the app (if any)

- If the app talks to the backend by URL, point it to the same backend (e.g. `http://localhost:3000` in dev). No change needed if it already uses that.
- If the app was pointing to a **deployed** backend that used the old Supabase, update the app’s API base URL to your new backend URL (or redeploy the backend with the new `.env` and keep the same URL).

---

## Summary checklist

- [ ] New Supabase project created under **your** account
- [ ] `DATABASE_URL` and `DIRECT_URL` in `backend/.env` point to that project
- [ ] New `JWT_SECRET` generated and set in `backend/.env`
- [ ] `npm run db:generate`, `db:push`, `db:seed` run successfully
- [ ] Backend restarted; login/signup tested

After this, login is reconfigured to use your own Supabase and your own JWT secret; the other person’s email is no longer tied to the project.
