// Pure-getter contract test for MuscleStatus.label.
//
// `label` is what the muscle-map UI renders under each muscle group. It's a
// pure function of (state, hoursRemaining) — no network — so it's cheap to pin
// down exactly. The risky bits: the state→string mapping and the `ceil()` on a
// fractional hours-remaining (a recovering muscle with 1.1h left must read
// "2h left", never "1h" or "1.1h").
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/muscle_recovery_service.dart';

MuscleStatus _status(
  MuscleState state, {
  double hoursRemaining = 0,
  int recoveryHours = 48,
}) {
  return MuscleStatus(
    slug: 'chest',
    state: state,
    lastTrainedAt: state == MuscleState.untrained ? null : DateTime(2026, 6, 19),
    recoveryHours: recoveryHours,
    hoursRemaining: hoursRemaining,
  );
}

void main() {
  group('MuscleStatus.label', () {
    test('untrained → "Not trained"', () {
      expect(_status(MuscleState.untrained).label, 'Not trained');
    });

    test('ready → "Ready"', () {
      expect(_status(MuscleState.ready).label, 'Ready');
    });

    test('recovering → ceil()ed hours, never rounded down or fractional', () {
      // 1.1h remaining must surface as "2h left" — rounding down would tell the
      // user a muscle is recoverable an hour early.
      expect(
        _status(MuscleState.recovering, hoursRemaining: 1.1).label,
        '2h left',
      );
      expect(
        _status(MuscleState.recovering, hoursRemaining: 12.0).label,
        '12h left',
      );
      expect(
        _status(MuscleState.recovering, hoursRemaining: 0.2).label,
        '1h left',
      );
    });
  });
}
