import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/nutrition_service.dart';

void main() {
  const goals = NutritionGoals(
    calories: 2400,
    proteinG: 180,
    carbsG: 290,
    fatG: 70,
    waterMl: 3000,
    goal: 'gain',
  );

  List<NutritionPlanDay> matchingPlan() {
    return List.generate(
      7,
      (index) => NutritionPlanDay(
        day: '2026-07-0${index + 1}',
        calories: goals.calories,
        proteinG: goals.proteinG,
        carbsG: goals.carbsG,
        fatG: goals.fatG,
        waterMl: goals.waterMl,
        goal: goals.goal,
      ),
    );
  }

  test('accepts a complete weekly plan with the canonical profile targets', () {
    expect(nutritionPlanMatchesGoals(goals, matchingPlan()), isTrue);
  });

  test('rejects a stale calorie target or legacy goal label', () {
    final wrongCalories = matchingPlan();
    wrongCalories[0] = NutritionPlanDay(
      day: wrongCalories[0].day,
      calories: 2280,
      proteinG: goals.proteinG,
      carbsG: goals.carbsG,
      fatG: goals.fatG,
      waterMl: goals.waterMl,
      goal: goals.goal,
    );
    expect(nutritionPlanMatchesGoals(goals, wrongCalories), isFalse);

    final legacyGoal = matchingPlan();
    legacyGoal[0] = NutritionPlanDay(
      day: legacyGoal[0].day,
      calories: goals.calories,
      proteinG: goals.proteinG,
      carbsG: goals.carbsG,
      fatG: goals.fatG,
      waterMl: goals.waterMl,
      goal: 'maintenance',
    );
    expect(nutritionPlanMatchesGoals(goals, legacyGoal), isFalse);
  });

  test('rejects an incomplete weekly response', () {
    expect(nutritionPlanMatchesGoals(goals, matchingPlan().take(6).toList()),
        isFalse);
  });
}
