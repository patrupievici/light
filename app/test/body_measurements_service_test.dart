import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/body_measurements_service.dart';

void main() {
  group('BodyMeasurement JSON round-trip (offline store shape)', () {
    test('only present fields are serialized; round-trips losslessly', () {
      final m = BodyMeasurement(
        date: DateTime(2026, 6, 13),
        chestCm: 102.5,
        bodyFatPct: 18.4,
      );
      final json = m.toJson();
      expect(json.containsKey('chestCm'), isTrue);
      expect(json.containsKey('bodyFatPct'), isTrue);
      // Absent fields must NOT be written (keeps null vs 0 distinct).
      expect(json.containsKey('waistCm'), isFalse);
      expect(json.containsKey('armsCm'), isFalse);

      final back = BodyMeasurement.fromJson(json);
      expect(back.chestCm, 102.5);
      expect(back.bodyFatPct, 18.4);
      expect(back.waistCm, isNull);
      expect(back.date, DateTime(2026, 6, 13));
    });

    test('isEmpty is true only when every field is null', () {
      expect(BodyMeasurement(date: DateTime(2026, 1, 1)).isEmpty, isTrue);
      expect(
        BodyMeasurement(date: DateTime(2026, 1, 1), waistCm: 80).isEmpty,
        isFalse,
      );
    });
  });

  group('latestWithDelta — reconciliation over the merged list', () {
    test('returns latest value and delta vs the previous log of that field', () {
      // Newest-first, as the service stores it after a sync.
      final list = [
        BodyMeasurement(date: DateTime(2026, 6, 13), waistCm: 82),
        BodyMeasurement(date: DateTime(2026, 6, 6), waistCm: 84),
        BodyMeasurement(date: DateTime(2026, 5, 30), chestCm: 100),
      ];
      final r = BodyMeasurementsService.latestWithDelta(list, (m) => m.waistCm);
      expect(r, isNotNull);
      expect(r!.value, 82);
      expect(r.delta, -2); // 82 - 84
    });

    test('null delta when the field was logged only once', () {
      final list = [
        BodyMeasurement(date: DateTime(2026, 6, 13), bodyFatPct: 17),
      ];
      final r =
          BodyMeasurementsService.latestWithDelta(list, (m) => m.bodyFatPct);
      expect(r!.value, 17);
      expect(r.delta, isNull);
    });

    test('null when the field was never logged', () {
      final list = [
        BodyMeasurement(date: DateTime(2026, 6, 13), chestCm: 100),
      ];
      expect(
        BodyMeasurementsService.latestWithDelta(list, (m) => m.thighsCm),
        isNull,
      );
    });
  });
}
