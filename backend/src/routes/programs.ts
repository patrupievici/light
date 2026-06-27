import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { prisma } from '../lib/prisma'
import { authenticate } from '../middleware/auth'
import { getProgramTemplate } from '../programming/program-templates'
import {
  startProgram,
  getActiveProgram,
  getLatestCompletedProgram,
  setProgramTrainingMaxes,
  materializeCurrentDay,
  startProgramDay,
  advanceProgram,
  readState,
  getEnrichedTemplateSummaries,
  ProgramError,
} from '../services/program.service'

const StartSchema = z.object({
  templateId: z.string().min(1).max(64),
  weeks: z.number().int().min(1).max(16).optional(),
  equipmentTags: z.array(z.string().max(40)).max(20).optional(),
  oneRepMaxes: z.record(z.string().max(80), z.number().min(1).max(600)).optional(),
})

const PatchSchema = z
  .object({
    status: z.enum(['archived']).optional(),
    oneRepMaxes: z.record(z.string().max(80), z.number().min(1).max(600)).optional(),
  })
  .refine((v) => v.status !== undefined || v.oneRepMaxes !== undefined, {
    message: 'Nimic de actualizat (status sau oneRepMaxes)',
  })

function serializeProgram(p: {
  id: string
  templateId: string
  title: string
  totalWeeks: number
  daysPerWeek: number
  progressionScheme: string
  deloadCadence: number
  status: string
  currentWeek: number
  stateJson: unknown
  equipmentTags: unknown
  startedAt: Date
  completedAt: Date | null
}) {
  const st = readState(p.stateJson)
  return {
    id: p.id,
    templateId: p.templateId,
    title: p.title,
    totalWeeks: p.totalWeeks,
    daysPerWeek: p.daysPerWeek,
    progressionScheme: p.progressionScheme,
    deloadCadence: p.deloadCadence,
    status: p.status,
    currentWeek: p.currentWeek,
    sessionIndex: st.sessionIndex,
    trainingMaxes: st.tm,
    equipmentTags: Array.isArray(p.equipmentTags) ? p.equipmentTags : [],
    startedAt: p.startedAt.toISOString(),
    completedAt: p.completedAt ? p.completedAt.toISOString() : null,
  }
}

export async function programRoutes(app: FastifyInstance) {
  // GET /v1/programs/templates — the program library (summaries + card metadata:
  // exercise GIF thumbnails, equipment, time + exercises/day).
  app.get('/templates', { preHandler: authenticate }, async (_request, reply) => {
    return reply.send({ data: await getEnrichedTemplateSummaries() })
  })

  // GET /v1/programs/templates/:id — full template (weeks × days × slots) for preview.
  app.get('/templates/:id', { preHandler: authenticate }, async (request, reply) => {
    const { id } = request.params as { id: string }
    const tpl = getProgramTemplate(id)
    if (!tpl) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Program negăsit', requestId: request.id })
    }
    return reply.send({ template: tpl })
  })

  // POST /v1/programs/start — start a template (archives any active program).
  app.post('/start', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const parsed = StartSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide pentru pornirea programului',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    try {
      const program = await startProgram(userId, parsed.data)
      return reply.code(201).send({ program: serializeProgram(program) })
    } catch (err) {
      if (err instanceof ProgramError && err.code === 'TEMPLATE_NOT_FOUND') {
        return reply.code(404).send({ error: 'NOT_FOUND', message: err.message, requestId: request.id })
      }
      throw err
    }
  })

  // GET /v1/programs/active — current active program + today's materialized day.
  app.get('/active', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const program = await getActiveProgram(userId)
    if (!program) {
      // No active program — surface the most recent COMPLETED one so the UI can
      // show a "program finished" card instead of a bare empty state.
      const completed = await getLatestCompletedProgram(userId)
      return reply.send({
        program: completed ? serializeProgram(completed) : null,
        today: null,
        completed: completed != null,
      })
    }
    const today = await materializeCurrentDay(userId, program)
    return reply.send({ program: serializeProgram(program), today, completed: false })
  })

  // GET /v1/programs/:id/day — materialize the program's current day (preview).
  app.get('/:id/day', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const program = await prisma.userProgram.findFirst({ where: { id, userId } })
    if (!program) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Program negăsit', requestId: request.id })
    }
    const day = await materializeCurrentDay(userId, program)
    return reply.send({ day })
  })

  // POST /v1/programs/:id/start-day — materialize today into a live draft Workout.
  app.post('/:id/start-day', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const program = await prisma.userProgram.findFirst({ where: { id, userId } })
    if (!program) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Program negăsit', requestId: request.id })
    }
    if (program.status !== 'active') {
      return reply.code(409).send({ error: 'NOT_ACTIVE', message: 'Programul nu este activ', requestId: request.id })
    }
    const result = await startProgramDay(userId, program)
    return reply.code(201).send(result)
  })

  // POST /v1/programs/:id/advance — mark the current session done, advance state.
  app.post('/:id/advance', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const program = await prisma.userProgram.findFirst({ where: { id, userId } })
    if (!program) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Program negăsit', requestId: request.id })
    }
    if (program.status !== 'active') {
      return reply.code(409).send({ error: 'NOT_ACTIVE', message: 'Programul nu este activ', requestId: request.id })
    }
    const updated = await advanceProgram(userId, program)
    return reply.send({ program: serializeProgram(updated) })
  })

  // PATCH /v1/programs/:id — archive and/or set training maxes (from 1RMs).
  app.patch('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const parsed = PatchSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'Date invalide',
        requestId: request.id,
        details: parsed.error.flatten(),
      })
    }
    const program = await prisma.userProgram.findFirst({ where: { id, userId } })
    if (!program) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Program negăsit', requestId: request.id })
    }
    let updated = program
    if (parsed.data.oneRepMaxes && Object.keys(parsed.data.oneRepMaxes).length > 0) {
      updated = await setProgramTrainingMaxes(updated, parsed.data.oneRepMaxes)
    }
    if (parsed.data.status === 'archived') {
      updated = await prisma.userProgram.update({ where: { id }, data: { status: 'archived' } })
    }
    return reply.send({ program: serializeProgram(updated) })
  })

  // DELETE /v1/programs/:id — remove a program the user no longer wants.
  app.delete('/:id', { preHandler: authenticate }, async (request, reply) => {
    const { userId } = request.user
    const { id } = request.params as { id: string }
    const program = await prisma.userProgram.findFirst({ where: { id, userId } })
    if (!program) {
      return reply.code(404).send({ error: 'NOT_FOUND', message: 'Program negăsit', requestId: request.id })
    }
    await prisma.userProgram.delete({ where: { id } })
    return reply.code(204).send()
  })
}
