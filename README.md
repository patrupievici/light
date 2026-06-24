# Zvelt — Fitness App

## Setup Backend (prima data)

### 1. Instaleaza dependentele
```bash
cd backend
npm install
```

### 2. Creeaza contul Supabase
- Du-te la https://supabase.com si creeaza un proiect gratuit
- Din dashboard: Settings → Database → copiaza "Connection string (URI)"

### 3. Configureaza variabilele de mediu
```bash
# In backend/.env: DATABASE_URL, DIRECT_URL, JWT_SECRET (vezi .env.example daca exista)
# Optional - Login cu Google: adauga GOOGLE_CLIENT_ID="xxx.apps.googleusercontent.com"
#   (Client ID de la Google Cloud Console → APIs & Services → Credentials → OAuth 2.0 Client ID Android/Web)
```

### 4. Genereaza clientul Prisma si ruleaza migrarile
```bash
npm run db:generate
npm run db:push
npm run db:seed
```

### 5. Porneste serverul
```bash
npm run dev
```
Serverul porneste la http://localhost:3000

### Verificare
```
GET http://localhost:3000/health
```

---

## Structura backend

```
backend/
├── prisma/
│   ├── schema.prisma     # Schema DB completa
│   └── seed.ts           # Date initiale (exercitii, sezon)
├── src/
│   ├── lib/
│   │   └── prisma.ts     # Client Prisma singleton
│   ├── middleware/
│   │   └── auth.ts       # JWT auth middleware
│   ├── routes/
│   │   ├── auth.ts       # signup/login/refresh/logout
│   │   ├── profile.ts    # GET /me, PATCH /me/profile
│   │   ├── exercises.ts  # GET /exercises, POST custom
│   │   ├── workouts.ts   # CRUD workouts + sets
│   │   ├── posts.ts      # Post workout + feed + likes/comments
│   │   └── ranks.ts      # Ranguri + leaderboard + explain
│   ├── services/
│   │   ├── ranking.service.ts  # Algoritm e1RM + LP + tiers
│   │   └── streak.service.ts   # Calcul streak
│   ├── types/
│   │   └── index.ts
│   └── server.ts         # Entry point Fastify
├── .env.example
├── package.json
└── tsconfig.json
```

## API Endpoints

| Method | Path | Descriere |
|--------|------|-----------|
| POST | /v1/auth/signup | Inregistrare |
| POST | /v1/auth/login | Autentificare |
| POST | /v1/auth/refresh | Refresh token |
| POST | /v1/auth/logout | Deconectare |
| GET | /v1/me | Profil + streak |
| PATCH | /v1/me/profile | Update profil |
| GET | /v1/exercises | Lista exercitii |
| POST | /v1/exercises/custom | Exercitiu custom |
| POST | /v1/workouts | Creeaza workout |
| GET | /v1/workouts | Lista workouturi |
| POST | /v1/workouts/:id/exercises | Adauga exercitiu |
| POST | /v1/workouts/:id/exercises/:weId/sets | Adauga set |
| POST | /v1/workouts/:id/complete | Finalizeaza workout |
| POST | /v1/posts | Posteaza + calculeaza rang |
| GET | /v1/posts/feed | Feed prieteni |
| POST | /v1/posts/:id/likes | Toggle like |
| POST | /v1/posts/:id/comments | Adauga comentariu |
| GET | /v1/ranks/me | Toate rangurile mele |
| GET | /v1/ranks/exercises/:id/explain | Card explicatie rang |
| GET | /v1/ranks/leaderboard | Leaderboard sezon |
"# beastpack" 
