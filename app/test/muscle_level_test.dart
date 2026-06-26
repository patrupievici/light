import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/muscle_recovery_service.dart';

void main() {
  group('MuscleLevel.fromJson', () {
    test('parses a muscle-levels row', () {
      final m = MuscleLevel.fromJson({
        'slug': 'chest',
        'level': 8,
        'volumeXp': 50000,
        'volumeKg': 50000,
        'workSets': 120,
        'bestLp': 350,
        'tier': 'Gold',
        'lastTrainedAt': '2026-06-20T10:00:00.000Z',
      });
      expect(m.slug, 'chest');
      expect(m.level, 8);
      expect(m.tier, 'Gold');
      expect(m.bestLp, 350);
      expect(m.lastTrainedAt, isNotNull);
    });

    test('tolerates missing fields and null lastTrainedAt', () {
      final m = MuscleLevel.fromJson({'slug': 'abs'});
      expect(m.slug, 'abs');
      expect(m.level, 0);
      expect(m.tier, 'Iron');
      expect(m.lastTrainedAt, isNull);
    });
  });
}
