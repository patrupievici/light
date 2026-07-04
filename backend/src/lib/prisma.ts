import { PrismaClient, Prisma } from '@prisma/client'

// ─────────────────────────────────────────────────────────────────────────────
// Decimal → JSON number (global, once at import).
//
// Postgres `Decimal` columns (weightKg, bodyweightKg, rpe, bestE1rmKg,
// strengthRatio, macros, wallet amount, …) come back as Prisma.Decimal, whose
// default toJSON() returns a STRING. That forced every client reader to parse
// defensively and crashed any that used a raw `as num` cast (the gray-box +
// "nothing loads" bugs). Every Decimal column here fits losslessly in a
// float64, so emit a JSON number instead — fixes the whole class at the source
// for all endpoints, present and future. Clients already tolerate both shapes,
// so this is backward-compatible.
;(Prisma.Decimal.prototype as unknown as { toJSON: () => number }).toJSON =
  function (this: Prisma.Decimal): number {
    return this.toNumber()
  }

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient }

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({
    // Never log 'query': it emits raw SQL with bound params (PII/secrets) to
    // stdout. Keep error/warn in dev; errors only in prod.
    log: process.env.NODE_ENV === 'development' ? ['error', 'warn'] : ['error'],
  })

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma
