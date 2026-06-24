import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/health_service.dart';

// Regression guards for the Health-history import fix. These are deliberately
// pure (no plugin/DB) so they stay reliable: they lock in the two values the
// fix hinges on — the 90-day first-grant window and the imported-record model
// shape that the new history surface depends on.
void main() {
  test('first-grant backfill window is 90 days (not the old 7)', () {
    expect(HealthService.kRecentBackfillWindow, const Duration(days: 90));
  });

  test('HealthImportedRecord.fromRow maps a Health Connect row faithfully', () {
    final r = HealthImportedRecord.fromRow(const <String, Object?>{
      'id': 1,
      'uuid': 'abc',
      'type': 'RESTING_HEART_RATE',
      'start_at': '2026-06-01T07:00:00.000Z',
      'end_at': '2026-06-01T07:05:00.000Z',
      'value': 54.0,
      'unit': 'bpm',
      'source_app': 'Samsung Health',
      'source_path': 'health_connect',
      'provider': 'samsung',
      'external_id': 'ext-1',
      'payload_json': '{}',
    });
    expect(r.type, 'RESTING_HEART_RATE');
    expect(r.value, 54.0);
    expect(r.unit, 'bpm');
    expect(r.sourceApp, 'Samsung Health');
    expect(r.endAt.isAfter(r.startAt), isTrue);
  });

  test('HealthImportedRecord.fromRow applies defensive fallbacks for null cols',
      () {
    // Health Connect rows can omit columns; these fallback branches are the
    // higher-risk paths, so pin them explicitly.
    final r = HealthImportedRecord.fromRow(const <String, Object?>{
      'id': 2,
      'uuid': 'u2',
      'type': 'STEPS',
      'start_at': '2026-06-01T00:00:00.000Z',
      'end_at': '2026-06-01T01:00:00.000Z',
      'value': null,
      'unit': null,
      'source_app': null,
      'source_path': null,
      'provider': null,
      'external_id': null,
      'payload_json': null,
    });
    expect(r.value, isNull);
    expect(r.unit, '');
    expect(r.sourceApp, '');
    expect(r.sourcePath, 'health_connect'); // default when null
    expect(r.externalId, 'u2'); // falls back to uuid
    expect(r.payloadJson, '{}');
  });
}
