import type { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { authenticate } from '../middleware/auth'

/**
 * Proxy OpenWeatherMap (free tier) — cheie doar pe server.
 * https://openweathermap.org/api (task Excel #22)
 */
export async function weatherRoutes(app: FastifyInstance) {
  app.get('/current', { preHandler: authenticate }, async (request, reply) => {
    const key = process.env.OPENWEATHER_API_KEY
    if (!key) {
      return reply.code(503).send({
        error: 'WEATHER_DISABLED',
        message: 'Seteaza OPENWEATHER_API_KEY in .env',
        requestId: request.id,
      })
    }

    const q = request.query as { lat?: string; lon?: string }
    const lat = z.coerce.number().min(-90).max(90).safeParse(q.lat)
    const lon = z.coerce.number().min(-180).max(180).safeParse(q.lon)
    if (!lat.success || !lon.success) {
      return reply.code(400).send({
        error: 'VALIDATION_ERROR',
        message: 'lat si lon sunt obligatorii',
        requestId: request.id,
      })
    }

    const url = new URL('https://api.openweathermap.org/data/2.5/weather')
    url.searchParams.set('lat', String(lat.data))
    url.searchParams.set('lon', String(lon.data))
    url.searchParams.set('appid', key)
    url.searchParams.set('units', 'metric')

    const res = await fetch(url)
    if (!res.ok) {
      const t = await res.text()
      app.log.warn({ status: res.status, t }, 'OpenWeather error')
      return reply.code(502).send({
        error: 'WEATHER_UPSTREAM',
        message: 'Meteo indisponibil',
        requestId: request.id,
      })
    }

    const data = (await res.json()) as any
    return reply.send({
      tempC: data.main?.temp,
      feelsLikeC: data.main?.feels_like,
      humidity: data.main?.humidity,
      description: data.weather?.[0]?.description,
      icon: data.weather?.[0]?.icon,
      windMs: data.wind?.speed,
      location: data.name,
    })
  })
}
