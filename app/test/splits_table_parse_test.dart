// Contract test for SplitsTable.parseSplits — the mapping that wires the
// backend `splits` payload (computed server-side from route_points) into the
// SplitData rows the table renders. No widget pumping here: parseSplits is a
// pure JSON→model reducer, so we pin its coercion + skip rules directly.
//
// Risky bits this covers: numbers arriving as int OR double OR numeric string
// (the app has been bitten by Prisma Decimals serialising as strings), the
// 1-based `index`→`km` mapping, `timeS` seconds→Duration, and malformed
// entries being skipped instead of crashing the summary screen.
import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/widgets/splits_table.dart';

void main() {
  group('SplitsTable.parseSplits', () {
    test('returns empty for non-list / null input', () {
      expect(SplitsTable.parseSplits(null), isEmpty);
      expect(SplitsTable.parseSplits('nope'), isEmpty);
      expect(SplitsTable.parseSplits(<String, dynamic>{}), isEmpty);
    });

    test('maps a backend split with numeric fields', () {
      final splits = SplitsTable.parseSplits([
        {
          'index': 1,
          'distanceM': 1000,
          'timeS': 284,
          'paceSecsPerKm': 284,
          'elevGainM': 12.5,
          'partial': false,
        },
      ]);
      expect(splits, hasLength(1));
      expect(splits.first.km, 1);
      expect(splits.first.time, const Duration(seconds: 284));
      expect(splits.first.paceSecsPerKm, 284);
      expect(splits.first.elevGainM, 12.5);
    });

    test('coerces string-encoded numbers (Decimal-as-string defence)', () {
      final splits = SplitsTable.parseSplits([
        {
          'index': '2',
          'timeS': '300',
          'paceSecsPerKm': '305.5',
          'elevGainM': '8',
        },
      ]);
      expect(splits, hasLength(1));
      expect(splits.first.km, 2);
      expect(splits.first.time, const Duration(seconds: 300));
      expect(splits.first.paceSecsPerKm, 305.5);
      expect(splits.first.elevGainM, 8);
    });

    test('preserves sub-second timeS via milliseconds', () {
      final splits = SplitsTable.parseSplits([
        {'index': 1, 'timeS': 12.5, 'paceSecsPerKm': 0, 'elevGainM': 0},
      ]);
      expect(splits.first.time, const Duration(milliseconds: 12500));
    });

    test('skips malformed entries but keeps valid ones', () {
      final splits = SplitsTable.parseSplits([
        'garbage',
        null,
        {'index': 3, 'timeS': 200, 'paceSecsPerKm': 200, 'elevGainM': 0},
      ]);
      expect(splits, hasLength(1));
      expect(splits.first.km, 3);
    });

    test('defaults unparseable fields to zero rather than throwing', () {
      final splits = SplitsTable.parseSplits([
        {'index': 1, 'timeS': 'abc', 'paceSecsPerKm': null, 'elevGainM': 'x'},
      ]);
      expect(splits, hasLength(1));
      expect(splits.first.time, Duration.zero);
      expect(splits.first.paceSecsPerKm, 0);
      expect(splits.first.elevGainM, 0);
    });
  });
}
