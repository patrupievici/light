# Apply schema when `db:push` can't connect

If your network blocks Supabase (ports 5432/6543) or you get P1001, apply the schema from the **Supabase Dashboard** instead of running `prisma db push` from your machine.

## Steps

1. **Open Supabase**  
   Go to [supabase.com](https://supabase.com) → your project.

2. **SQL Editor**  
   In the left sidebar click **SQL Editor** → **New query**.

3. **Paste and run**  
   Open the file `prisma/schema_for_supabase.sql` in this folder, copy **all** its contents, paste into the SQL Editor, and click **Run**.

4. **Regenerate Prisma client (no DB connection needed)**  
   On your machine:
   ```bash
   cd c:\proiect\backend
   npm run db:generate
   ```

5. **Backend at runtime**  
   Your app uses `DATABASE_URL` (pooler, port 6543) for queries. If that port works from your network, start the backend with:
   ```bash
   npm run dev
   ```
   You don't need `DIRECT_URL` for normal runs once the schema is applied.

## Seed (optional)

If you want the default exercises and season and your machine **can** reach the DB (e.g. from another network), run:

```bash
npm run db:seed
```

If you can't run the seed from your machine, you can add exercises and the season later via the app or by running equivalent `INSERT`s in the SQL Editor.
