// Pure-logic contract test for RestAdherence — the comparison that backs the
// prescribed rest-timer's adherence verdict and the future explainability line
// ("Rested 45s vs 90s prescribed"). No DB / no network, so the math and the
// tolerance band can be pinned exactly.
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/rest_interval_store.dart';

void main() {
  group('RestAdherence', () {
    test('no prescription → no verdict, no explain line', () {
      final a = RestAdherence.compare(actualSeconds: 60, prescribedSeconds: 0);
      expect(a.hasPrescription, isFalse);
      expect(a.withinTarget, isFalse);
      expect(a.tooShort, isFalse);
      expect(a.tooLong, isFalse);
      expect(a.explainLine, isNull);
    });

    test('exact match is within target', () {
      final a = RestAdherence.compare(actualSeconds: 90, prescribedSeconds: 90);
      expect(a.deltaSeconds, 0);
      expect(a.withinTarget, isTrue);
      expect(a.tooShort, isFalse);
      expect(a.tooLong, isFalse);
    });

    test('within tolerance band counts as on-target (boundary inclusive)', () {
      // +/- toleranceSeconds is "on target".
      final under = RestAdherence.compare(
        actualSeconds: 90 - RestAdherence.toleranceSeconds,
        prescribedSeconds: 90,
      );
      final over = RestAdherence.compare(
        actualSeconds: 90 + RestAdherence.toleranceSeconds,
        prescribedSeconds: 90,
      );
      expect(under.withinTarget, isTrue, reason: 'edge of band is on target');
      expect(over.withinTarget, isTrue, reason: 'edge of band is on target');
      expect(under.tooShort, isFalse);
      expect(over.tooLong, isFalse);
    });

    test('past tolerance band flags too short / too long', () {
      final short = RestAdherence.compare(actualSeconds: 45, prescribedSeconds: 90);
      expect(short.tooShort, isTrue);
      expect(short.tooLong, isFalse);
      expect(short.withinTarget, isFalse);
      expect(short.deltaSeconds, -45);

      final long = RestAdherence.compare(actualSeconds: 150, prescribedSeconds: 90);
      expect(long.tooLong, isTrue);
      expect(long.tooShort, isFalse);
      expect(long.withinTarget, isFalse);
      expect(long.deltaSeconds, 60);
    });

    test('explain line reads "Rested Xs vs Ys prescribed"', () {
      final a = RestAdherence.compare(actualSeconds: 45, prescribedSeconds: 90);
      expect(a.explainLine, 'Rested 45s vs 90s prescribed');
    });

    test('negative actual is clamped to zero (never claims negative rest)', () {
      final a = RestAdherence.compare(actualSeconds: -3, prescribedSeconds: 90);
      expect(a.actualSeconds, 0);
      expect(a.explainLine, 'Rested 0s vs 90s prescribed');
    });
  });
}
