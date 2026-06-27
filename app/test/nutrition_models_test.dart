import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/services/nutrition_service.dart';

void main() {
  group('Recipe', () {
    final recipe = Recipe.fromJson({
      'id': 'r1',
      'name': 'Oats bowl',
      'servings': 2,
      'ingredientsJson': [
        {'name': 'Oats', 'grams': 100, 'caloriesPer100g': 380, 'proteinPer100g': 13, 'carbsPer100g': 60, 'fatPer100g': 7},
        {'name': 'Milk', 'grams': 200, 'caloriesPer100g': 50, 'proteinPer100g': 3.4, 'carbsPer100g': 5, 'fatPer100g': 2},
      ],
      'totalCalories': 480,
      'totalProtein': 19.8,
      'totalCarbs': 70,
      'totalFat': 11,
    });

    test('parses ingredients, servings and totals', () {
      expect(recipe.ingredients, hasLength(2));
      expect(recipe.servings, 2);
      expect(recipe.totalCalories, 480);
      expect(recipe.ingredients.first.calories, 380); // 100g of 380/100g
    });

    test('per-serving macros split the totals', () {
      expect(recipe.perServingCalories, 240);
      expect(recipe.perServingProtein, closeTo(9.9, 0.001));
    });

    test('toMealEntry encodes the logged servings so diary macros are exact', () {
      final one = recipe.toMealEntry(meal: 'breakfast', servingsToLog: 1);
      expect(one.meal, 'breakfast');
      expect(one.calories, 240); // 1 serving
      final two = recipe.toMealEntry(meal: 'breakfast', servingsToLog: 2);
      expect(two.calories, 480); // 2 servings
    });
  });

  group('MealTemplateItem', () {
    test('derives per-100g from grams+totals so the diary entry is exact', () {
      final item = MealTemplateItem.fromJson({
        'name': 'Chicken breast',
        'grams': 150,
        'calories': 300,
        'proteinG': 45,
        'carbsG': 0,
        'fatG': 6,
        'meal': 'lunch',
      });
      final entry = item.toMealEntry('dinner');
      expect(entry.grams, 150);
      expect(entry.meal, 'lunch'); // item meal wins over fallback
      expect(entry.calories, closeTo(300, 0.001));
      expect(entry.protein, closeTo(45, 0.001));
      expect(entry.fat, closeTo(6, 0.001));
    });

    test('falls back to 100g when no grams given', () {
      final item = MealTemplateItem.fromJson({'name': 'Snack', 'calories': 120, 'proteinG': 5});
      final entry = item.toMealEntry('snack');
      expect(entry.grams, 100);
      expect(entry.calories, closeTo(120, 0.001));
      expect(entry.meal, 'snack'); // fallback used
    });
  });

  group('RecipeIngredient.fromFood', () {
    test('carries the food macros + grams', () {
      const food = FoodItem(
        id: 'off:1', name: 'Yogurt', brand: 'X',
        caloriesPer100g: 60, proteinPer100g: 10, fatPer100g: 0.2, carbsPer100g: 4,
      );
      final ing = RecipeIngredient.fromFood(food, 200);
      expect(ing.grams, 200);
      expect(ing.calories, 120); // 200g of 60/100g
      expect(ing.foodId, 'off:1');
    });
  });
}
