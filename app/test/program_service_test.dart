import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/program_service.dart';

void main() {
  group('ProgramSummary.fromJson', () {
    test('parses library metadata and the training-max flag', () {
      final s = ProgramSummary.fromJson({
        'id': 'nsuns_4day',
        'title': 'nSuns',
        'description': 'High volume',
        'level': 'advanced',
        'scheme': 'percentage',
        'split': 'upper_lower',
        'goalTags': ['strength', 'hypertrophy'],
        'weeksOptions': [4, 6, 8],
        'defaultWeeks': 6,
        'daysPerWeek': 4,
        'sessionsInRotation': 4,
        'requiresTrainingMax': true,
      });
      expect(s.id, 'nsuns_4day');
      expect(s.daysPerWeek, 4);
      expect(s.weeksOptions, [4, 6, 8]);
      expect(s.requiresTrainingMax, isTrue);
    });
  });

  group('ProgramSlotView set labels', () {
    ProgramSlotView slot(Map<String, dynamic> sets) =>
        ProgramSlotView.fromJson({'exercise': 'Squat', 'role': 'main', 'sets': sets, 'restSeconds': 180});

    test('straight → NxR', () {
      expect(slot({'kind': 'straight', 'sets': 5, 'reps': 5}).setsLabel, '5×5');
    });
    test('range → Nx min–max', () {
      expect(slot({'kind': 'range', 'sets': 4, 'minReps': 6, 'maxReps': 10}).setsLabel, '4×6–10');
    });
    test('waves map to readable names', () {
      expect(slot({'kind': 'wave', 'wave': '531_main'}).setsLabel, '5/3/1');
      expect(slot({'kind': 'wave', 'wave': 'nsuns_t1'}).setsLabel, 'nSuns T1');
      expect(slot({'kind': 'wave', 'wave': '531_bbb'}).setsLabel, '5×10 BBB');
    });
  });

  group('MaterializedDay.fromJson', () {
    test('parses targets, per-set detail and warmups', () {
      final day = MaterializedDay.fromJson({
        'dayKey': 'B3',
        'title': 'Bench day',
        'week': 2,
        'weekInCycle': 2,
        'isDeload': false,
        'exercises': [
          {
            'name': 'Bench Press',
            'sets': 3,
            'reps': 3,
            'suggestedWeightKg': 90,
            'setsDetail': [
              {'weightKg': 70, 'reps': 3},
              {'weightKg': 80, 'reps': 3},
              {'weightKg': 90, 'reps': 3, 'amrap': true},
            ],
            'warmups': [
              {'weightKg': 20, 'reps': 8},
              {'weightKg': 50, 'reps': 5},
            ],
            'notes': '531_main · TM 100kg',
          },
        ],
      });
      expect(day.week, 2);
      expect(day.isDeload, isFalse);
      expect(day.exercises, hasLength(1));
      final ex = day.exercises.first;
      expect(ex.setsDetail, hasLength(3));
      expect(ex.setsDetail.last.amrap, isTrue);
      expect(ex.warmups, hasLength(2));
      expect(ex.suggestedWeightKg, 90);
    });

    test('tolerates missing weights (no training max set)', () {
      final day = MaterializedDay.fromJson({
        'dayKey': 'N1',
        'title': 'Bench',
        'exercises': [
          {
            'name': 'Bench Press',
            'sets': 9,
            'reps': 5,
            'suggestedWeightKg': null,
            'setsDetail': [
              {'weightKg': null, 'reps': 5},
            ],
          },
        ],
      });
      expect(day.exercises.first.suggestedWeightKg, isNull);
      expect(day.exercises.first.setsDetail.first.weightKg, isNull);
    });
  });

  group('ActiveProgram.fromJson', () {
    test('parses week progress and numeric training maxes only', () {
      final p = ActiveProgram.fromJson({
        'id': 'p1',
        'templateId': '531_bbb',
        'title': '5/3/1 BBB',
        'progressionScheme': 'percentage',
        'status': 'active',
        'totalWeeks': 8,
        'daysPerWeek': 4,
        'deloadCadence': 4,
        'currentWeek': 3,
        'sessionIndex': 9,
        'trainingMaxes': {'Squat': 140, 'Bench Press': 100.5, 'bad': 'x'},
      });
      expect(p.currentWeek, 3);
      expect(p.totalWeeks, 8);
      expect(p.trainingMaxes['Squat'], 140);
      expect(p.trainingMaxes['Bench Press'], 100.5);
      expect(p.trainingMaxes.containsKey('bad'), isFalse);
    });
  });
}
