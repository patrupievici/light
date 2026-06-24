// ─── GPS file import (GPX / TCX) ──────────────────────────────────────────────
//
// Clean-room parsers for the two common XML route formats so a user can import a
// recorded outdoor session from another app/device. Both formats are XML; rather
// than pull in a heavy XML/DOM dependency we do a small, tolerant tag scan that
// extracts only the handful of fields a route needs: latitude, longitude and the
// optional per-point elevation + timestamp.
//
// The parsers are deliberately strict at the boundary (clear, typed errors on
// malformed input) but tolerant of the cosmetic variation real exporters emit
// (attribute quote style, self-closing tags, namespace prefixes, extra fields).
// Output is the same `{ lat, lng, ele?, t? }` RoutePoint shape the existing
// metric recompute consumes, so an imported track flows through the identical
// trusted distance/duration/elevation pipeline as a live recording.

/** One parsed sample. Matches the RoutePoint shape used by the metric recompute. */
export type ImportedPoint = {
  lat: number
  lng: number
  /** Altitude in metres (when the source carried it). */
  ele?: number | null
  /** Epoch milliseconds (when the source carried a timestamp). */
  t?: number | null
}

/** Supported file formats. FIT (binary) is intentionally excluded — see route. */
export type ActivityFileFormat = 'gpx' | 'tcx'

/** Result of a successful parse: the points plus the format we detected. */
export type ParsedActivityFile = {
  format: ActivityFileFormat
  points: ImportedPoint[]
}

/**
 * Thrown when a file cannot be parsed into a usable route. `code` is a stable
 * machine string the route maps onto an HTTP status + body; `message` is safe to
 * surface to the importing user.
 */
export class ActivityFileParseError extends Error {
  readonly code: ActivityFileParseErrorCode
  constructor(code: ActivityFileParseErrorCode, message: string) {
    super(message)
    this.name = 'ActivityFileParseError'
    this.code = code
  }
}

export type ActivityFileParseErrorCode =
  | 'EMPTY_FILE'
  | 'UNRECOGNIZED_FORMAT'
  | 'MALFORMED_XML'
  | 'NO_TRACK_POINTS'

/** Hard cap on extracted points so a hostile/huge file can't exhaust memory. */
export const MAX_IMPORT_POINTS = 100_000

const LAT_MIN = -90
const LAT_MAX = 90
const LNG_MIN = -180
const LNG_MAX = 180
const ELE_MIN = -500
const ELE_MAX = 9_000

function finiteInRange(n: number, min: number, max: number): boolean {
  return Number.isFinite(n) && n >= min && n <= max
}

/**
 * Parse an ISO-8601 timestamp (the format both GPX `<time>` and TCX `<Time>` use)
 * into epoch milliseconds, or null when absent/unparseable. We never throw on a
 * bad timestamp — timing is optional and the metric pipeline degrades gracefully
 * without it.
 */
function parseIsoMillis(raw: string | null | undefined): number | null {
  if (raw == null) return null
  const trimmed = raw.trim()
  if (trimmed === '') return null
  const ms = Date.parse(trimmed)
  return Number.isFinite(ms) ? ms : null
}

/**
 * Pull the text content of the first child element named `tag` inside `xml`.
 * Namespace-tolerant: matches `<tag>`, `<ns:tag>` and self-attributed variants.
 * Returns null when the element is absent. Used for per-point ele/time only, so a
 * linear scan over the (small) trackpoint slice is fine.
 */
function firstChildText(xml: string, tag: string): string | null {
  const re = new RegExp(
    `<(?:[\\w.-]+:)?${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</(?:[\\w.-]+:)?${tag}>`,
    'i',
  )
  const m = re.exec(xml)
  return m ? decodeXmlEntities(m[1].trim()) : null
}

/** Decode the five predefined XML entities (enough for numeric/time payloads). */
function decodeXmlEntities(s: string): string {
  return s
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&')
}

/** Read a numeric attribute (e.g. `lat="45.1"`) from an opening tag, or null. */
function attrNumber(openTag: string, name: string): number | null {
  const re = new RegExp(`\\b${name}\\s*=\\s*["']([^"']*)["']`, 'i')
  const m = re.exec(openTag)
  if (!m) return null
  const n = Number(m[1])
  return Number.isFinite(n) ? n : null
}

/**
 * Detect the format from the document body. We look at element names rather than
 * the filename so a mislabelled upload still routes to the right parser. Returns
 * null when neither a GPX nor a TCX marker is present.
 */
export function detectFormat(xml: string): ActivityFileFormat | null {
  if (/<(?:[\w.-]+:)?gpx[\s>]/i.test(xml) || /<(?:[\w.-]+:)?trkpt[\s>]/i.test(xml)) {
    return 'gpx'
  }
  if (
    /<TrainingCenterDatabase[\s>]/i.test(xml) ||
    /<(?:[\w.-]+:)?Trackpoint[\s>]/i.test(xml)
  ) {
    return 'tcx'
  }
  return null
}

/** Rough well-formedness guard: balanced angle brackets and a closing tag. */
function looksLikeXml(xml: string): boolean {
  const opens = (xml.match(/</g) ?? []).length
  const closes = (xml.match(/>/g) ?? []).length
  return opens > 0 && opens === closes && /<\/[\w.-]+/.test(xml)
}

/**
 * Parse a GPX document into route points. GPX stores coordinates as attributes on
 * `<trkpt lat=".." lon="..">` (also `<rtept>`/`<wpt>`, which we accept), with an
 * optional `<ele>` child and `<time>` child. Points missing a valid lat/lon pair
 * are skipped rather than failing the whole import.
 */
export function parseGpx(xml: string): ImportedPoint[] {
  const points: ImportedPoint[] = []
  // Match each point element with its inner body so we can read ele/time.
  const re =
    /<(?:[\w.-]+:)?(?:trkpt|rtept|wpt)\b([^>]*?)(?:\/>|>([\s\S]*?)<\/(?:[\w.-]+:)?(?:trkpt|rtept|wpt)>)/gi
  let m: RegExpExecArray | null
  while ((m = re.exec(xml)) !== null) {
    if (points.length >= MAX_IMPORT_POINTS) break
    const openAttrs = m[1] ?? ''
    const inner = m[2] ?? ''
    const lat = attrNumber(openAttrs, 'lat')
    const lng = attrNumber(openAttrs, 'lon')
    if (lat == null || lng == null) continue
    if (!finiteInRange(lat, LAT_MIN, LAT_MAX) || !finiteInRange(lng, LNG_MIN, LNG_MAX)) {
      continue
    }
    const eleRaw = firstChildText(inner, 'ele')
    const ele = eleRaw != null ? Number(eleRaw) : NaN
    const t = parseIsoMillis(firstChildText(inner, 'time'))
    points.push({
      lat,
      lng,
      ele: finiteInRange(ele, ELE_MIN, ELE_MAX) ? ele : null,
      t,
    })
  }
  return points
}

/**
 * Parse a TCX document into route points. TCX nests coordinates in a
 * `<Trackpoint>` with a `<Position><LatitudeDegrees>/<LongitudeDegrees>` pair,
 * an optional `<AltitudeMeters>` and a `<Time>`. Trackpoints without a position
 * (e.g. a HR-only sample) are skipped.
 */
export function parseTcx(xml: string): ImportedPoint[] {
  const points: ImportedPoint[] = []
  const re = /<(?:[\w.-]+:)?Trackpoint\b[^>]*>([\s\S]*?)<\/(?:[\w.-]+:)?Trackpoint>/gi
  let m: RegExpExecArray | null
  while ((m = re.exec(xml)) !== null) {
    if (points.length >= MAX_IMPORT_POINTS) break
    const inner = m[1] ?? ''
    const latRaw = firstChildText(inner, 'LatitudeDegrees')
    const lngRaw = firstChildText(inner, 'LongitudeDegrees')
    if (latRaw == null || lngRaw == null) continue
    const lat = Number(latRaw)
    const lng = Number(lngRaw)
    if (!finiteInRange(lat, LAT_MIN, LAT_MAX) || !finiteInRange(lng, LNG_MIN, LNG_MAX)) {
      continue
    }
    const eleRaw = firstChildText(inner, 'AltitudeMeters')
    const ele = eleRaw != null ? Number(eleRaw) : NaN
    const t = parseIsoMillis(firstChildText(inner, 'Time'))
    points.push({
      lat,
      lng,
      ele: finiteInRange(ele, ELE_MIN, ELE_MAX) ? ele : null,
      t,
    })
  }
  return points
}

/**
 * Parse a GPX or TCX file (auto-detecting the format) into route points.
 *
 * Throws `ActivityFileParseError` with a stable `code` for the importing route to
 * map onto an HTTP response:
 *  - EMPTY_FILE          — nothing to parse
 *  - MALFORMED_XML       — not well-formed enough to scan
 *  - UNRECOGNIZED_FORMAT — neither a GPX nor TCX marker present
 *  - NO_TRACK_POINTS     — recognised format but zero usable coordinates
 *
 * `hint` (e.g. a filename or declared format) only nudges detection; the document
 * body always wins so a mislabelled `.gpx` that is actually TCX still parses.
 */
export function parseActivityFile(
  content: string,
  hint?: string | null,
): ParsedActivityFile {
  if (content == null || content.trim() === '') {
    throw new ActivityFileParseError('EMPTY_FILE', 'Fișierul este gol')
  }
  if (!looksLikeXml(content)) {
    throw new ActivityFileParseError(
      'MALFORMED_XML',
      'Fișierul nu este XML valid (GPX/TCX)',
    )
  }

  let format = detectFormat(content)
  if (format == null && hint) {
    const h = hint.toLowerCase()
    if (h.endsWith('.gpx') || h === 'gpx') format = 'gpx'
    else if (h.endsWith('.tcx') || h === 'tcx') format = 'tcx'
  }
  if (format == null) {
    throw new ActivityFileParseError(
      'UNRECOGNIZED_FORMAT',
      'Format nerecunoscut — se acceptă doar GPX sau TCX',
    )
  }

  const points = format === 'gpx' ? parseGpx(content) : parseTcx(content)
  if (points.length === 0) {
    throw new ActivityFileParseError(
      'NO_TRACK_POINTS',
      'Fișierul nu conține puncte de traseu valide',
    )
  }

  return { format, points }
}
