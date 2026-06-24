import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/health_service.dart';

// Pure guards for the on-device -> server health import push (B2). These lock in
// the contract POSTed to /v1/me/health/import: canonical metricType + unit, UTC
// ISO timestamps, and a stable externalId for server-side dedup. No plugin / DB
// / network is touched so they stay deterministic.
HealthImportedRecord _rec({
  int id = 1,
  String uuid = 'u1',
  String type = 'STEPS',
  String startAt = '2026-06-01T00:00:00.000Z',
  String endAt = '2026-06-01T01:00:00.000Z',
  double? value = 1234,
  String unit = 'COUNT',
  String externalId = 'ext-1',
}) =>
    HealthImportedRecord.fromRow(<String, Object?>{
      'id': id,
      'uuid': uuid,
      'type': type,
      'start_at': startAt,
      'end_at': endAt,
      'value': value,
      'unit': unit,
      'source_app': 'Samsung Health',
      'source_path': 'health_connect',
      'provider': 'samsung_health',
      'external_id': externalId,
      'payload_json': '{}',
    });

void main() {
  group('healthMetricTypeFor', () {
    test('maps known on-device types to canonical server metricType', () {
      expect(healthMetricTypeFor('STEPS'), 'steps');
      expect(healthMetricTypeFor('RESTING_HEART_RATE'), 'resting_heart_rate');
      expect(healthMetricTypeFor('HEART_RATE'), 'heart_rate');
      expect(healthMetricTypeFor('WEIGHT'), 'weight');
      expect(healthMetricTypeFor('BODY_FAT_PERCENTAGE'), 'body_fat');
      expect(healthMetricTypeFor('SLEEP_SESSION'), 'sleep');
      expect(healthMetricTypeFor('SLEEP_ASLEEP'), 'sleep');
    });

    test('both HRV platform variants collapse to one metric', () {
      expect(healthMetricTypeFor('HEART_RATE_VARIABILITY_RMSSD'), 'hrv');
      expect(healthMetricTypeFor('HEART_RATE_VARIABILITY_SDNN'), 'hrv');
    });

    test('both distance platform variants collapse to one metric', () {
      expect(healthMetricTypeFor('DISTANCE_DELTA'), 'distance');
      expect(healthMetricTypeFor('DISTANCE_WALKING_RUNNING'), 'distance');
    });

    test('unknown/future types degrade to lower-case, never dropped', () {
      expect(healthMetricTypeFor('SOME_FUTURE_TYPE'), 'some_future_type');
    });
  });

  group('canonicalHealthUnit', () {
    test('normalizes the unit label without rescaling values', () {
      expect(canonicalHealthUnit('weight', 'KILOGRAM'), 'kg');
      expect(canonicalHealthUnit('heart_rate', 'BEATS_PER_MINUTE'), 'bpm');
      expect(canonicalHealthUnit('hrv', 'MILLISECONDS'), 'ms');
      expect(canonicalHealthUnit('calories', 'KILOCALORIE'), 'kcal');
      expect(canonicalHealthUnit('steps', 'COUNT'), 'count');
      expect(canonicalHealthUnit('blood_oxygen', 'PERCENT'), 'percent');
    });

    test('falls back to lower-cased plugin unit when unmapped', () {
      expect(canonicalHealthUnit('mystery', 'WEIRD_UNIT'), 'weird_unit');
      expect(canonicalHealthUnit('mystery', '   '), 'unit');
    });
  });

  group('buildHealthImportRows', () {
    test('produces the exact server payload shape with UTC ISO times', () {
      final rows = buildHealthImportRows(
        [_rec(value: 80, type: 'HEART_RATE', unit: 'BEATS_PER_MINUTE')],
        source: 'health_connect',
      );
      expect(rows, hasLength(1));
      final r = rows.single;
      expect(r.keys.toSet(), {
        'metricType',
        'value',
        'unit',
        'startAt',
        'endAt',
        'source',
        'externalId',
      });
      expect(r['metricType'], 'heart_rate');
      expect(r['unit'], 'bpm');
      expect(r['value'], 80);
      expect(r['source'], 'health_connect');
      expect(r['externalId'], 'ext-1');
      expect(r['startAt'], '2026-06-01T00:00:00.000Z');
      expect(r['endAt'], '2026-06-01T01:00:00.000Z');
    });

    test('timestamps are converted to UTC', () {
      final rows = buildHealthImportRows(
        [_rec(startAt: '2026-06-01T03:00:00.000+03:00')],
        source: 'healthkit',
      );
      expect(rows.single['startAt'], '2026-06-01T00:00:00.000Z');
      expect(rows.single['source'], 'healthkit');
    });

    test('stable externalId carries through for idempotent re-push', () {
      final first = buildHealthImportRows([_rec()], source: 'health_connect');
      final second = buildHealthImportRows([_rec()], source: 'health_connect');
      expect(first.single['externalId'], second.single['externalId']);
    });

    test('falls back to uuid when external_id column is blank', () {
      // fromRow already maps a blank/absent external_id to uuid, so the row
      // arrives with externalId == uuid; the builder must keep it pushable.
      final rec = HealthImportedRecord.fromRow(const <String, Object?>{
        'id': 9,
        'uuid': 'uuid-only',
        'type': 'WEIGHT',
        'start_at': '2026-06-01T07:00:00.000Z',
        'end_at': '2026-06-01T07:00:00.000Z',
        'value': 81.5,
        'unit': 'KILOGRAM',
        'source_app': '',
        'source_path': 'health_connect',
        'provider': '',
        'external_id': null,
        'payload_json': null,
      });
      final rows = buildHealthImportRows([rec], source: 'health_connect');
      expect(rows.single['externalId'], 'uuid-only');
      expect(rows.single['metricType'], 'weight');
      expect(rows.single['unit'], 'kg');
    });

    test('null-valued non-window samples are still pushed (server keeps window)',
        () {
      // We do NOT drop null values here; the server can store a window-only
      // sample. Only rows with no usable externalId are skipped.
      final rows = buildHealthImportRows(
        [_rec(value: null)],
        source: 'health_connect',
      );
      expect(rows.single['value'], isNull);
    });
  });
}
