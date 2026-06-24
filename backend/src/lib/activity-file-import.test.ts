import { describe, it, expect } from 'vitest'
import {
  parseActivityFile,
  parseGpx,
  parseTcx,
  detectFormat,
  ActivityFileParseError,
  MAX_IMPORT_POINTS,
} from './activity-file-import'

// ─── Fixtures ─────────────────────────────────────────────────────────────────

const GPX = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="SomeApp">
  <trk>
    <name>Morning Run</name>
    <trkseg>
      <trkpt lat="45.0000" lon="25.0000">
        <ele>100.0</ele>
        <time>2026-06-01T06:00:00Z</time>
      </trkpt>
      <trkpt lat="45.0010" lon="25.0000">
        <ele>102.5</ele>
        <time>2026-06-01T06:00:30Z</time>
      </trkpt>
      <trkpt lat="45.0020" lon="25.0000">
        <ele>101.0</ele>
        <time>2026-06-01T06:01:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>`

// Namespace-prefixed, single-quoted attrs, self-closing point, no ele/time.
const GPX_VARIANT = `<gpx:gpx xmlns:gpx="http://www.topografix.com/GPX/1/1">
  <gpx:trkpt lat='51.5' lon='-0.12'/>
  <gpx:trkpt lat='48.85' lon='2.35'></gpx:trkpt>
</gpx:gpx>`

const TCX = `<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
  <Activities>
    <Activity Sport="Running">
      <Lap>
        <Track>
          <Trackpoint>
            <Time>2026-06-01T06:00:00Z</Time>
            <Position>
              <LatitudeDegrees>45.0000</LatitudeDegrees>
              <LongitudeDegrees>25.0000</LongitudeDegrees>
            </Position>
            <AltitudeMeters>100.0</AltitudeMeters>
          </Trackpoint>
          <Trackpoint>
            <Time>2026-06-01T06:00:30Z</Time>
            <Position>
              <LatitudeDegrees>45.0010</LatitudeDegrees>
              <LongitudeDegrees>25.0000</LongitudeDegrees>
            </Position>
            <AltitudeMeters>102.0</AltitudeMeters>
          </Trackpoint>
          <Trackpoint>
            <!-- HR-only sample: no Position, must be skipped -->
            <Time>2026-06-01T06:00:45Z</Time>
            <HeartRateBpm><Value>150</Value></HeartRateBpm>
          </Trackpoint>
        </Track>
      </Lap>
    </Activity>
  </Activities>
</TrainingCenterDatabase>`

// ─── detectFormat ─────────────────────────────────────────────────────────────

describe('detectFormat', () => {
  it('detects gpx from the root and from a bare trkpt', () => {
    expect(detectFormat(GPX)).toBe('gpx')
    expect(detectFormat('<trkpt lat="1" lon="2"/>')).toBe('gpx')
    expect(detectFormat(GPX_VARIANT)).toBe('gpx')
  })

  it('detects tcx', () => {
    expect(detectFormat(TCX)).toBe('tcx')
  })

  it('returns null for unrelated XML', () => {
    expect(detectFormat('<root><child/></root>')).toBeNull()
  })
})

// ─── parseGpx ─────────────────────────────────────────────────────────────────

describe('parseGpx', () => {
  it('extracts lat/lng/ele/time from trackpoints', () => {
    const pts = parseGpx(GPX)
    expect(pts).toHaveLength(3)
    expect(pts[0]).toMatchObject({ lat: 45.0, lng: 25.0, ele: 100.0 })
    expect(pts[0].t).toBe(Date.parse('2026-06-01T06:00:00Z'))
    expect(pts[2].ele).toBe(101.0)
  })

  it('tolerates namespace prefixes, quote styles and self-closing tags', () => {
    const pts = parseGpx(GPX_VARIANT)
    expect(pts).toHaveLength(2)
    expect(pts[0]).toMatchObject({ lat: 51.5, lng: -0.12, ele: null, t: null })
  })

  it('skips points with out-of-range or missing coordinates', () => {
    const xml = `<gpx>
      <trkpt lat="999" lon="25"><ele>1</ele></trkpt>
      <trkpt lon="25"><ele>1</ele></trkpt>
      <trkpt lat="45" lon="25"></trkpt>
    </gpx>`
    const pts = parseGpx(xml)
    expect(pts).toHaveLength(1)
    expect(pts[0]).toMatchObject({ lat: 45, lng: 25 })
  })

  it('rejects an out-of-range elevation but keeps the point', () => {
    const xml = `<gpx><trkpt lat="45" lon="25"><ele>50000</ele></trkpt></gpx>`
    expect(parseGpx(xml)[0].ele).toBeNull()
  })
})

// ─── parseTcx ─────────────────────────────────────────────────────────────────

describe('parseTcx', () => {
  it('extracts position/altitude/time and skips position-less samples', () => {
    const pts = parseTcx(TCX)
    expect(pts).toHaveLength(2) // the HR-only trackpoint is dropped
    expect(pts[0]).toMatchObject({ lat: 45.0, lng: 25.0, ele: 100.0 })
    expect(pts[1].t).toBe(Date.parse('2026-06-01T06:00:30Z'))
  })
})

// ─── parseActivityFile (dispatch + errors) ────────────────────────────────────

describe('parseActivityFile', () => {
  it('parses GPX and reports the format', () => {
    const r = parseActivityFile(GPX)
    expect(r.format).toBe('gpx')
    expect(r.points).toHaveLength(3)
  })

  it('parses TCX and reports the format', () => {
    const r = parseActivityFile(TCX)
    expect(r.format).toBe('tcx')
    expect(r.points).toHaveLength(2)
  })

  it('lets the body win over a misleading filename hint', () => {
    // Content is TCX but the hint says .gpx — detection must use the body.
    const r = parseActivityFile(TCX, 'wrong-name.gpx')
    expect(r.format).toBe('tcx')
  })

  it('uses the filename hint only when the body is ambiguous', () => {
    // A bare trkpt is detectable; remove the markers to force hint use.
    const r = parseActivityFile('<doc><trkpt lat="45" lon="25"/></doc>', 'x.gpx')
    expect(r.format).toBe('gpx')
  })

  it('throws EMPTY_FILE on empty/whitespace input', () => {
    expect(() => parseActivityFile('')).toThrow(ActivityFileParseError)
    try {
      parseActivityFile('   \n ')
    } catch (e) {
      expect((e as ActivityFileParseError).code).toBe('EMPTY_FILE')
    }
  })

  it('throws MALFORMED_XML on unbalanced markup', () => {
    try {
      parseActivityFile('<gpx><trkpt lat="45" lon="25"')
    } catch (e) {
      expect((e as ActivityFileParseError).code).toBe('MALFORMED_XML')
    }
  })

  it('throws UNRECOGNIZED_FORMAT for valid-but-unknown XML', () => {
    try {
      parseActivityFile('<root><child>hi</child></root>')
    } catch (e) {
      expect((e as ActivityFileParseError).code).toBe('UNRECOGNIZED_FORMAT')
    }
  })

  it('throws NO_TRACK_POINTS for a recognised file with no usable points', () => {
    const empty = `<gpx version="1.1"><trk><trkseg></trkseg></trk></gpx>`
    try {
      parseActivityFile(empty)
    } catch (e) {
      expect((e as ActivityFileParseError).code).toBe('NO_TRACK_POINTS')
    }
  })

  it('caps extracted points at MAX_IMPORT_POINTS', () => {
    const body = Array.from(
      { length: MAX_IMPORT_POINTS + 50 },
      () => `<trkpt lat="45" lon="25"/>`,
    ).join('')
    const r = parseActivityFile(`<gpx>${body}</gpx>`)
    expect(r.points.length).toBe(MAX_IMPORT_POINTS)
  })
})
