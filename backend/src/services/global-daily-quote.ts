import cron from 'node-cron'
import type { FastifyBaseLogger } from 'fastify'
import { prisma } from '../lib/prisma'
import { deepSeekChat } from './deepseek.service'

/** Cron + stored quotes use UK civil date (Europe/London). */
export const UK_TIMEZONE = 'Europe/London'

const RETRY_GAP_MS = 3_600_000 // 1h between attempts after first failure

const LAST_RESORT = {
  quote: 'Track it, adjust it, own the process.',
  author: 'Zvelt Coach',
} as const

export function ukCalendarYmd(d = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: UK_TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(d)
  const y = parts.find((p) => p.type === 'year')?.value
  const m = parts.find((p) => p.type === 'month')?.value
  const day = parts.find((p) => p.type === 'day')?.value
  if (!y || !m || !day) throw new Error('ukCalendarYmd: invalid Intl parts')
  return `${y}-${m}-${day}`
}

function sleep(ms: number) {
  return new Promise<void>((r) => setTimeout(r, ms))
}

async function fetchQuoteFromDeepSeek(): Promise<{ quote: string; author: string }> {
  const prompt = `Generate ONE motivational fitness quote. Max 15 words. English only.
Format exactly: "Quote text" — Author
Return nothing else.`

  const result = await deepSeekChat([{ role: 'user', content: prompt }], {
    maxTokens: 80,
    temperature: 0.85,
  })

  const full = result.text.trim()
  if (full.length < 4) throw new Error('empty quote')

  let quote = full
  let author = 'Zvelt Coach'
  const parts = full.split(/\s*[—–-]\s*/)
  if (parts.length >= 2) {
    quote = parts.slice(0, -1).join('—').trim()
    author = parts[parts.length - 1].trim()
  }
  quote = quote.replace(/^["']|["']$/g, '').trim()
  author = author.replace(/^["']|["']$/g, '').trim()
  if (author.length > 80) author = 'Zvelt Coach'
  if (quote.length < 4) throw new Error('parsed quote too short')
  return { quote, author }
}

/** 00:00 UK → generate quote for that calendar day. Up to 3 DeepSeek tries: now, +1h, +1h. */
export async function generateUkDailyQuoteJob(log: FastifyBaseLogger): Promise<void> {
  const day = ukCalendarYmd(new Date())
  for (let attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) {
      log.warn({ day, attempt: attempt + 1 }, 'daily quote: retry in 1h')
      await sleep(RETRY_GAP_MS)
    }
    try {
      const { quote, author } = await fetchQuoteFromDeepSeek()
      await prisma.globalDailyQuote.upsert({
        where: { calendarDay: day },
        create: { calendarDay: day, quote, author },
        update: { quote, author },
      })
      log.info({ day }, 'global daily quote saved')
      return
    } catch (err) {
      log.warn({ err, day, attempt: attempt + 1 }, 'global daily quote DeepSeek failed')
    }
  }
  log.error({ day }, 'global daily quote: gave up after 3 tries (API serves previous day)')
}

export function startGlobalDailyQuoteCron(log: FastifyBaseLogger): void {
  cron.schedule(
    '0 0 * * *',
    () => {
      void generateUkDailyQuoteJob(log)
    },
    { timezone: UK_TIMEZONE },
  )
  log.info({ tz: UK_TIMEZONE }, 'cron: global daily quote @ 00:00 UK')
}

/** Read-only. UK „today”; missing row → newest row before today → hardcoded line. */
export async function loadDailyQuoteForApi(): Promise<{
  quote: string
  author: string
  quoteForDay: string
  reusedPreviousDay: boolean
}> {
  const todayUk = ukCalendarYmd(new Date())
  const todayRow = await prisma.globalDailyQuote.findUnique({
    where: { calendarDay: todayUk },
  })
  if (todayRow) {
    return {
      quote: todayRow.quote,
      author: todayRow.author,
      quoteForDay: todayUk,
      reusedPreviousDay: false,
    }
  }

  const prev = await prisma.globalDailyQuote.findFirst({
    where: { calendarDay: { lt: todayUk } },
    orderBy: { calendarDay: 'desc' },
  })
  if (prev) {
    return {
      quote: prev.quote,
      author: prev.author,
      quoteForDay: todayUk,
      reusedPreviousDay: true,
    }
  }

  return {
    quote: LAST_RESORT.quote,
    author: LAST_RESORT.author,
    quoteForDay: todayUk,
    reusedPreviousDay: false,
  }
}
