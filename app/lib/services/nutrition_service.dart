import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart' show v1Base;
import '_crash_reporter.dart';
import 'auth_service.dart';
import 'http_client.dart';
import 'local_food_database.dart';
import 'nutrition_food_labels.dart';
import 'open_food_facts_client.dart';
import 'usda_fdc_client.dart';

String _nutritionApiErrorDetail(http.Response res) {
  try {
    final dynamic m = jsonDecode(res.body);
    if (m is Map<String, dynamic>) {
      final msg = m['message']?.toString();
      if (msg != null && msg.isNotEmpty) return msg;
      final err = m['error']?.toString();
      if (err != null && err.isNotEmpty) return err;
    }
  } catch (e) {
    debugPrint(
        '[NutritionService._nutritionApiErrorDetail] decode best-effort skip: $e');
  }
  final b = res.body.trim();
  if (b.length > 280) return '${b.substring(0, 280)}…';
  if (b.isNotEmpty) return b;
  return 'HTTP ${res.statusCode}';
}

/// User-facing nutrition error. `toString()` is the friendly message only — no
/// `Exception:` prefix, no server stack — so it is safe to show directly in UI.
class NutritionPlanException implements Exception {
  const NutritionPlanException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

class FoodItem {
  const FoodItem({
    required this.id,
    required this.name,
    required this.brand,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
    this.imageUrl,
    this.barcode,
    this.category,
    this.servingGrams,
    this.servingLabel,
    this.portionUnitKey,
  });

  final String id;
  final String name;
  final String brand;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
  final String? imageUrl;
  final String? barcode;
  final String? category;

  /// Grame într-o porție (euristică USDA / etichetă). `null` = doar introdus manual în g.
  final double? servingGrams;
  final String? servingLabel;

  /// `egg`, `slice`, `serving` … — pentru „3 eggs”.
  final String? portionUnitKey;

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'caloriesPer100g': caloriesPer100g,
        'proteinPer100g': proteinPer100g,
        'fatPer100g': fatPer100g,
        'carbsPer100g': carbsPer100g,
        'imageUrl': imageUrl,
        'barcode': barcode,
        'category': category,
        'servingGrams': servingGrams,
        'servingLabel': servingLabel,
        'portionUnitKey': portionUnitKey,
      };

  static FoodItem fromJson(Map<String, dynamic> j) => FoodItem(
        id: j['id'] as String,
        name: j['name'] as String,
        brand: j['brand'] as String? ?? '',
        caloriesPer100g: _d(j['caloriesPer100g']),
        proteinPer100g: _d(j['proteinPer100g']),
        fatPer100g: _d(j['fatPer100g']),
        carbsPer100g: _d(j['carbsPer100g']),
        imageUrl: j['imageUrl'] as String?,
        barcode: j['barcode'] as String?,
        category: j['category'] as String?,
        servingGrams: () {
          final v = j['servingGrams'];
          if (v == null) return null;
          final d = _d(v);
          return d > 0 ? d : null;
        }(),
        servingLabel: j['servingLabel'] as String?,
        portionUnitKey: j['portionUnitKey'] as String?,
      );
}

/// Rezultat căutare după nume (USDA FoodData Central).
typedef FoodNameSearchResult = ({List<FoodItem> items, String? errorMessage});

class MealEntry {
  MealEntry({
    required this.id,
    required this.food,
    required this.grams,
    required this.meal,
    required this.loggedAt,
  });

  final String id;
  final FoodItem food;
  final double grams;
  final String meal;
  final DateTime loggedAt;

  double get calories => food.caloriesPer100g * grams / 100;
  double get protein => food.proteinPer100g * grams / 100;
  double get fat => food.fatPer100g * grams / 100;
  double get carbs => food.carbsPer100g * grams / 100;

  Map<String, dynamic> toJson() => {
        'id': id,
        'food': food.toJson(),
        'grams': grams,
        'meal': meal,
        'loggedAt': loggedAt.toIso8601String(),
      };

  static MealEntry fromJson(Map<String, dynamic> j) => MealEntry(
        id: j['id'] as String,
        food: FoodItem.fromJson(j['food'] as Map<String, dynamic>),
        grams: (j['grams'] as num).toDouble(),
        meal: j['meal'] as String,
        loggedAt: DateTime.parse(j['loggedAt'] as String),
      );
}

class DailyNutrition {
  const DailyNutrition({
    required this.entries,
    required this.waterMl,
    required this.weightKg,
  });

  final List<MealEntry> entries;
  final int waterMl;
  final double? weightKg;

  double get totalCalories => entries.fold(0, (s, e) => s + e.calories);
  double get totalProtein => entries.fold(0, (s, e) => s + e.protein);
  double get totalFat => entries.fold(0, (s, e) => s + e.fat);
  double get totalCarbs => entries.fold(0, (s, e) => s + e.carbs);

  static const DailyNutrition empty = DailyNutrition(
    entries: [],
    waterMl: 0,
    weightKg: null,
  );
}

/// Rezumat pe zi pentru grafice (istoric local SharedPreferences).
class NutritionDaySnapshot {
  NutritionDaySnapshot({
    required this.date,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.waterMl,
    this.weightKg,
  });

  final DateTime date;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final int waterMl;
  final double? weightKg;
}

class NutritionGoals {
  const NutritionGoals({
    this.calories = 2000,
    this.proteinG = 150,
    this.fatG = 65,
    this.carbsG = 250,
    this.waterMl = 2500,
  });

  final int calories;
  final int proteinG;
  final int fatG;
  final int carbsG;
  final int waterMl;

  Map<String, dynamic> toJson() => {
        'calories': calories,
        'proteinG': proteinG,
        'fatG': fatG,
        'carbsG': carbsG,
        'waterMl': waterMl,
      };

  static NutritionGoals fromJson(Map<String, dynamic> j) => NutritionGoals(
        calories: (j['calories'] as num?)?.toInt() ?? 2000,
        proteinG: (j['proteinG'] as num?)?.toInt() ?? 150,
        fatG: (j['fatG'] as num?)?.toInt() ?? 65,
        carbsG: (j['carbsG'] as num?)?.toInt() ?? 250,
        waterMl: (j['waterMl'] as num?)?.toInt() ?? 2500,
      );

  /// Maps `GET /v1/me` → `profile` fields (`dailyCalories`, `dailyProtein`, …).
  static NutritionGoals? fromServerProfile(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    final dc = profile['dailyCalories'];
    if (dc == null) return null;
    int n(String key, int fallback) {
      final v = profile[key];
      if (v == null) return fallback;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    return NutritionGoals(
      calories: dc is num ? dc.toInt() : int.tryParse(dc.toString()) ?? 2000,
      proteinG: n('dailyProtein', 150),
      fatG: n('dailyFat', 65),
      carbsG: n('dailyCarbs', 250),
      waterMl: n('dailyWaterMl', 2500),
    );
  }
}

class NutritionPlanDay {
  const NutritionPlanDay({
    required this.day,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.waterMl,
    required this.goal,
    this.mealPlan,
  });
  final String day;
  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final int waterMl;
  final String goal;
  final NutritionDayMealPlan? mealPlan;

  factory NutritionPlanDay.fromApiMap(Map<String, dynamic> e) {
    final rawMeal = e['mealPlan'] ?? e['meal_plan'];
    return NutritionPlanDay(
      day: e['day']?.toString() ?? '',
      calories: (e['calories'] as num?)?.toInt() ?? 0,
      proteinG: (e['proteinG'] as num?)?.toInt() ?? 0,
      carbsG: (e['carbsG'] as num?)?.toInt() ?? 0,
      fatG: (e['fatG'] as num?)?.toInt() ?? 0,
      waterMl: (e['waterMl'] as num?)?.toInt() ?? 0,
      goal: e['goal']?.toString() ?? 'maintenance',
      mealPlan: NutritionDayMealPlan.tryParse(rawMeal),
    );
  }
}

class MealItemMacros {
  const MealItemMacros({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;

  static MealItemMacros? tryParse(dynamic raw) {
    if (raw == null || raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final p = (m['proteinG'] as num?)?.round() ?? 0;
    final c = (m['carbsG'] as num?)?.round() ?? 0;
    final f = (m['fatG'] as num?)?.round() ?? 0;
    final explicit = (m['calories'] as num?)?.round();
    final cal = explicit ?? (p * 4 + c * 4 + f * 9).round();
    return MealItemMacros(calories: cal, proteinG: p, carbsG: c, fatG: f);
  }

  Map<String, dynamic> toJson() => {
        'calories': calories,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
      };
}

class NutritionMealPlanItem {
  const NutritionMealPlanItem({
    required this.text,
    this.portion,
    this.macros,
    this.proteinChoices,
    this.selectedProtein,
  });

  final String text;

  /// Explicit metric portion from AI (grams/ml/count).
  final String? portion;
  final MealItemMacros? macros;
  final List<String>? proteinChoices;
  final String? selectedProtein;

  bool get hasProteinPicker =>
      proteinChoices != null && proteinChoices!.length > 1;

  NutritionMealPlanItem copyWith({
    String? text,
    String? portion,
    MealItemMacros? macros,
    List<String>? proteinChoices,
    String? selectedProtein,
  }) {
    return NutritionMealPlanItem(
      text: text ?? this.text,
      portion: portion ?? this.portion,
      macros: macros ?? this.macros,
      proteinChoices: proteinChoices ?? this.proteinChoices,
      selectedProtein: selectedProtein ?? this.selectedProtein,
    );
  }

  Map<String, dynamic> toPatchJson() {
    final m = <String, dynamic>{'text': text};
    if (portion != null && portion!.trim().isNotEmpty) {
      m['portion'] = portion!.trim();
    }
    if (macros != null) {
      m['macros'] = macros!.toJson();
    }
    if (proteinChoices != null && proteinChoices!.isNotEmpty) {
      m['proteinChoices'] = proteinChoices;
      m['selectedProtein'] = _resolvedSelected();
    }
    return m;
  }

  String _resolvedSelected() {
    final c = proteinChoices;
    if (c == null || c.isEmpty) return selectedProtein ?? '';
    final s = selectedProtein;
    if (s != null && s.isNotEmpty) {
      for (final x in c) {
        if (x.toLowerCase() == s.toLowerCase()) return x;
      }
    }
    return c.first;
  }

  factory NutritionMealPlanItem.fromJson(Map<String, dynamic> j) {
    final rawChoices = j['proteinChoices'];
    List<String>? choices;
    if (rawChoices is List) {
      choices = rawChoices
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (choices.isEmpty) choices = null;
    }
    final sel = j['selectedProtein']?.toString().trim();
    final portionRaw = j['portion'];
    final portionStr = portionRaw == null ? '' : portionRaw.toString().trim();
    final portion = portionStr.isEmpty ? null : portionStr;
    return NutritionMealPlanItem(
      text: j['text']?.toString() ?? '',
      portion: portion,
      macros: MealItemMacros.tryParse(j['macros']),
      proteinChoices: choices,
      selectedProtein:
          sel ?? (choices?.isNotEmpty == true ? choices!.first : null),
    );
  }
}

class NutritionPlannedMeal {
  const NutritionPlannedMeal({required this.mealKey, required this.items});

  final String mealKey;
  final List<NutritionMealPlanItem> items;

  String get mealLabel {
    switch (mealKey) {
      case 'breakfast':
        return 'Breakfast';
      case 'lunch':
        return 'Lunch';
      case 'dinner':
        return 'Dinner';
      case 'snack':
        return 'Snack';
      default:
        if (mealKey.isEmpty) return 'Meal';
        return mealKey[0].toUpperCase() + mealKey.substring(1);
    }
  }

  Map<String, dynamic> toPatchJson() => {
        'meal': mealKey,
        'items': items.map((e) => e.toPatchJson()).toList(),
      };

  factory NutritionPlannedMeal.fromJson(Map<String, dynamic> j) {
    final meal = j['meal']?.toString() ?? '';
    final items = (j['items'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map(
            (e) => NutritionMealPlanItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return NutritionPlannedMeal(mealKey: meal, items: items);
  }

  NutritionPlannedMeal copyUpdatingItem(int index, NutritionMealPlanItem next) {
    final list = List<NutritionMealPlanItem>.from(items);
    if (index < 0 || index >= list.length) {
      return NutritionPlannedMeal(mealKey: mealKey, items: list);
    }
    list[index] = next;
    return NutritionPlannedMeal(mealKey: mealKey, items: list);
  }
}

class NutritionDayMealPlan {
  const NutritionDayMealPlan({required this.meals});

  final List<NutritionPlannedMeal> meals;

  Map<String, dynamic> toPatchJson() =>
      {'meals': meals.map((m) => m.toPatchJson()).toList()};

  factory NutritionDayMealPlan.fromJson(Map<String, dynamic> j) {
    final raw = j['meals'] as List<dynamic>? ?? const [];
    final meals = raw
        .whereType<Map>()
        .map((e) => NutritionPlannedMeal.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return NutritionDayMealPlan(meals: meals);
  }

  factory NutritionDayMealPlan.deepCopy(NutritionDayMealPlan other) {
    return NutritionDayMealPlan(
      meals: other.meals
          .map(
            (m) => NutritionPlannedMeal(
              mealKey: m.mealKey,
              items: m.items
                  .map(
                    (it) => NutritionMealPlanItem(
                      text: it.text,
                      portion: it.portion,
                      macros: it.macros == null
                          ? null
                          : MealItemMacros(
                              calories: it.macros!.calories,
                              proteinG: it.macros!.proteinG,
                              carbsG: it.macros!.carbsG,
                              fatG: it.macros!.fatG,
                            ),
                      proteinChoices: it.proteinChoices == null
                          ? null
                          : List<String>.from(it.proteinChoices!),
                      selectedProtein: it.selectedProtein,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );
  }

  NutritionDayMealPlan copyUpdatingMeal(
      int mealIndex, NutritionPlannedMeal nextMeal) {
    final copy = List<NutritionPlannedMeal>.from(meals);
    if (mealIndex < 0 || mealIndex >= copy.length) {
      return NutritionDayMealPlan(meals: copy);
    }
    copy[mealIndex] = nextMeal;
    return NutritionDayMealPlan(meals: copy);
  }

  static NutritionDayMealPlan? tryParse(dynamic raw) {
    if (raw == null) return null;
    if (raw is String && raw.trim().isEmpty) return null;
    Map<String, dynamic>? m;
    if (raw is Map<String, dynamic>) {
      m = raw;
    } else if (raw is Map) {
      m = Map<String, dynamic>.from(raw);
    } else if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) m = decoded;
      } catch (e) {
        debugPrint('[NutritionService] plan raw decode best-effort skip: $e');
        return null;
      }
    }
    if (m == null) return null;
    try {
      final plan = NutritionDayMealPlan.fromJson(m);
      return plan.meals.isEmpty ? null : plan;
    } catch (e) {
      debugPrint('[NutritionService] plan parse best-effort skip: $e');
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

/// Result returned by [NutritionService.claimDayXp]. Stub class retained for
/// build compatibility after Razvan removed the nutrition-xp backend service.
/// The feature is currently inert — `claimDayXp` always returns a result with
/// 0 XP. Re-wire when the backend XP claim endpoint is restored.
class NutritionXpClaimResult {
  const NutritionXpClaimResult({
    required this.xpAwarded,
    required this.totalXp,
    required this.lines,
    this.alreadyClaimed = false,
    this.ageMultiplier = 1.0,
    this.bonusApplied = false,
    this.message,
    this.breakdown = const <NutritionXpClaimLine>[],
  });
  final int xpAwarded;
  final int totalXp;
  final List<NutritionXpClaimLine> lines;
  final bool alreadyClaimed;
  final double ageMultiplier;
  final bool bonusApplied;
  final String? message;

  /// Per-macro breakdown (alias to lines for legacy widget readers).
  final List<NutritionXpClaimLine> breakdown;
}

/// Single line in the XP-claim breakdown card.
class NutritionXpClaimLine {
  const NutritionXpClaimLine({
    required this.label,
    required this.xp,
    this.detail,
    this.pctOfTarget = 0,
    this.hit = false,
    this.macro = '',
  });
  final String label;
  final int xp;
  final String? detail;
  final int pctOfTarget;
  final bool hit;

  /// Macro key (calories|protein|carbs|fat) — used by widget to pick a label.
  final String macro;
}

double? _nullableDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// One ingredient in a recipe (macros canonical per-100g, like FoodItem).
class RecipeIngredient {
  const RecipeIngredient({
    required this.name,
    required this.grams,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.foodId,
  });

  final String name;
  final double grams;
  final double caloriesPer100g, proteinPer100g, carbsPer100g, fatPer100g;
  final String? foodId;

  double get calories => caloriesPer100g * grams / 100;
  double get protein => proteinPer100g * grams / 100;
  double get carbs => carbsPer100g * grams / 100;
  double get fat => fatPer100g * grams / 100;

  Map<String, dynamic> toJson() => {
        'name': name,
        'grams': grams,
        if (foodId != null) 'foodId': foodId,
        'caloriesPer100g': caloriesPer100g,
        'proteinPer100g': proteinPer100g,
        'carbsPer100g': carbsPer100g,
        'fatPer100g': fatPer100g,
      };

  static RecipeIngredient fromJson(Map<String, dynamic> j) => RecipeIngredient(
        name: j['name'] as String? ?? '',
        grams: FoodItem._d(j['grams']),
        caloriesPer100g: FoodItem._d(j['caloriesPer100g']),
        proteinPer100g: FoodItem._d(j['proteinPer100g']),
        carbsPer100g: FoodItem._d(j['carbsPer100g']),
        fatPer100g: FoodItem._d(j['fatPer100g']),
        foodId: j['foodId'] as String?,
      );

  static RecipeIngredient fromFood(FoodItem f, double grams) =>
      RecipeIngredient(
        name: f.name,
        grams: grams,
        caloriesPer100g: f.caloriesPer100g,
        proteinPer100g: f.proteinPer100g,
        carbsPer100g: f.carbsPer100g,
        fatPer100g: f.fatPer100g,
        foodId: f.id,
      );
}

/// A saved multi-ingredient recipe. Per-serving macros derived from totals.
class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.servings,
    required this.ingredients,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
  });

  final String id, name;
  final int servings;
  final List<RecipeIngredient> ingredients;
  final double totalCalories, totalProtein, totalCarbs, totalFat;

  double get perServingCalories =>
      servings > 0 ? totalCalories / servings : totalCalories;
  double get perServingProtein =>
      servings > 0 ? totalProtein / servings : totalProtein;
  double get perServingCarbs =>
      servings > 0 ? totalCarbs / servings : totalCarbs;
  double get perServingFat => servings > 0 ? totalFat / servings : totalFat;

  /// Client-side apply: build a diary entry for `servingsToLog` servings. The
  /// logged amount is encoded as a 100g "food" whose per-100g equals the macros
  /// for those servings, so MealEntry's grams=100 math reproduces them exactly.
  MealEntry toMealEntry({required String meal, double servingsToLog = 1}) {
    final food = FoodItem(
      id: 'recipe:$id',
      name: name,
      brand: 'Recipe',
      caloriesPer100g: perServingCalories * servingsToLog,
      proteinPer100g: perServingProtein * servingsToLog,
      fatPer100g: perServingFat * servingsToLog,
      carbsPer100g: perServingCarbs * servingsToLog,
    );
    return MealEntry(
      id: 'r${DateTime.now().microsecondsSinceEpoch}',
      food: food,
      grams: 100,
      meal: meal,
      loggedAt: DateTime.now(),
    );
  }

  static Recipe fromJson(Map<String, dynamic> j) => Recipe(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Recipe',
        servings: (j['servings'] as num?)?.toInt() ?? 1,
        ingredients: ((j['ingredientsJson'] ?? j['ingredients'])
                    as List<dynamic>? ??
                const [])
            .whereType<Map>()
            .map((e) => RecipeIngredient.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        totalCalories: FoodItem._d(j['totalCalories']),
        totalProtein: FoodItem._d(j['totalProtein']),
        totalCarbs: FoodItem._d(j['totalCarbs']),
        totalFat: FoodItem._d(j['totalFat']),
      );
}

/// One item in a saved meal template (the backend NutritionMealTemplate item shape).
class MealTemplateItem {
  const MealTemplateItem({
    required this.name,
    this.grams,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.meal,
  });

  final String name;
  final double? grams, calories, proteinG, carbsG, fatG;
  final String? meal;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (grams != null) 'grams': grams,
        if (calories != null) 'calories': calories,
        if (proteinG != null) 'proteinG': proteinG,
        if (carbsG != null) 'carbsG': carbsG,
        if (fatG != null) 'fatG': fatG,
        if (meal != null) 'meal': meal,
      };

  static MealTemplateItem fromJson(Map<String, dynamic> j) => MealTemplateItem(
        name: j['name'] as String? ?? '',
        grams: _nullableDouble(j['grams']),
        calories: _nullableDouble(j['calories']),
        proteinG: _nullableDouble(j['proteinG']),
        carbsG: _nullableDouble(j['carbsG']),
        fatG: _nullableDouble(j['fatG']),
        meal: j['meal'] as String?,
      );

  /// Client-side apply: derive per-100g from grams+totals, like the backend's
  /// templateItemToDiaryEntry, and build a diary entry.
  MealEntry toMealEntry(String fallbackMeal) {
    final g = (grams != null && grams! > 0) ? grams! : 100.0;
    final per = g > 0 ? 100 / g : 1.0;
    final food = FoodItem(
      id: 'tpl:$name',
      name: name,
      brand: 'My Meals',
      caloriesPer100g: (calories ?? 0) * per,
      proteinPer100g: (proteinG ?? 0) * per,
      fatPer100g: (fatG ?? 0) * per,
      carbsPer100g: (carbsG ?? 0) * per,
    );
    return MealEntry(
      id: 't${DateTime.now().microsecondsSinceEpoch}_${name.hashCode}',
      food: food,
      grams: g,
      meal: meal ?? fallbackMeal,
      loggedAt: DateTime.now(),
    );
  }
}

/// A saved meal (multiple foods) for one-tap re-logging.
class MealTemplate {
  const MealTemplate(
      {required this.id, required this.name, required this.items});
  final String id, name;
  final List<MealTemplateItem> items;

  double get totalCalories => items.fold(0, (s, i) => s + (i.calories ?? 0));
  int get itemCount => items.length;

  static MealTemplate fromJson(Map<String, dynamic> j) => MealTemplate(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        items: (j['items'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => MealTemplateItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class NutritionService {
  NutritionService._([AuthService? auth]) : _auth = auth ?? AuthService();
  static final NutritionService instance = NutritionService._();

  final AuthService _auth;

  /// Stubbed during the merge — the backend nutrition-xp service was removed.
  /// Returns a no-op result so the claim card renders "already claimed" UI
  /// without surfacing an error. Will be re-implemented when the endpoint
  /// returns.
  Future<NutritionXpClaimResult> claimDayXp() async {
    return const NutritionXpClaimResult(
      xpAwarded: 0,
      totalXp: 0,
      lines: <NutritionXpClaimLine>[],
      alreadyClaimed: true,
    );
  }

  /// SharedPreferences keys are always `${userId}_…` (or `anonymous_…` if logged out).
  Future<String> _prefsKey(String suffix) async {
    final userId = await _auth.getCurrentUserId();
    final prefix = userId ?? 'anonymous';
    return '${prefix}_$suffix';
  }

  Future<String> _dayKey(DateTime date) async => _prefsKey(
        'nutrition_${date.year}_${date.month}_${date.day}',
      );

  /// Dirty flag per day: set when a local write hasn't been confirmed by the
  /// server (offline / failed PUT). While dirty, the local day is the source
  /// of truth — sync-down must NEVER overwrite it, or offline-logged meals
  /// are silently lost (the exact data-loss bug this guards against).
  Future<String> _dirtyKey(DateTime date) async => _prefsKey(
        'nutrition_dirty_${date.year}_${date.month}_${date.day}',
      );

  Future<bool> _isDayDirty(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(await _dirtyKey(date)) ?? false;
  }

  Future<void> _markDayDirty(DateTime date, bool dirty) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _dirtyKey(date);
    if (dirty) {
      await prefs.setBool(key, true);
    } else {
      await prefs.remove(key);
    }
  }

  Future<String> _goalsKey() async => _prefsKey('nutrition_goals');

  /// YYYY-MM-DD în calendarul local (aceeași convenție ca backend-ul).
  String formatLocalDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Map<String, dynamic> _dayToPrefsJson(DailyNutrition day) => {
        'entries': day.entries.map((e) => e.toJson()).toList(),
        'waterMl': day.waterMl,
        'weightKg': day.weightKg,
      };

  DailyNutrition _dailyFromServerJson(Map<String, dynamic> j) {
    final entries = (j['entries'] as List<dynamic>? ?? [])
        .map((e) => MealEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return DailyNutrition(
      entries: entries,
      waterMl: (j['waterMl'] as num?)?.toInt() ?? 0,
      weightKg:
          j['weightKg'] != null ? (j['weightKg'] as num).toDouble() : null,
    );
  }

  Future<void> _saveDayToPrefs(DateTime date, DailyNutrition day) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        await _dayKey(date), jsonEncode(_dayToPrefsJson(day)));
  }

  /// Tail of the serialized day-push queue — see [_enqueueDayPush].
  Future<void> _pushChain = Future<void>.value();

  /// Serializes day PUTs so background pushes land on the server in the
  /// order they were enqueued. Without this, two quick logs fire concurrent
  /// full-day PUTs and an OLDER snapshot finishing last would regress the
  /// server copy while its 2xx clears the dirty flag on stale data.
  Future<bool> _enqueueDayPush(DateTime date, DailyNutrition day) {
    final push = _pushChain.then((_) => _pushDayToServer(date, day));
    _pushChain = push.then<void>((_) {}).catchError((Object e) {
      // _pushDayToServer catches internally; keep the chain alive regardless.
      debugPrint('[NutritionService] day push chain best-effort skip: $e');
    });
    return push;
  }

  /// Returns true when the server confirmed the write (2xx). On any failure
  /// the day stays marked dirty, so sync-down keeps treating the local copy
  /// as the source of truth until a later push succeeds.
  Future<bool> _pushDayToServer(DateTime date, DailyNutrition day) async {
    await _markDayDirty(date, true);
    final token = await _auth.getAccessToken();
    if (token == null) return false;
    try {
      final res = await http
          .put(
            Uri.parse('$v1Base/nutrition/day'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'date': formatLocalDate(date),
              ..._dayToPrefsJson(day),
            }),
          )
          .withTimeout();
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _markDayDirty(date, false);
        return true;
      }
    } catch (e, st) {
      reportError(e, st, reason: 'nutrition:push-day');
    }
    return false;
  }

  /// Sincronizează ultimele [days] zile de pe server în SharedPreferences (istoric grafice).
  Future<void> syncHistoryFromServer({int days = 14}) async {
    final token = await _auth.getAccessToken();
    if (token == null) return;
    final today = DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    final start = end.subtract(Duration(days: days - 1));
    final from = formatLocalDate(start);
    final to = formatLocalDate(end);
    try {
      final res = await http.get(
        // queryParameters: lets Uri encode the dates safely instead of
        // raw string concat — the values are already YMD so there's no
        // practical injection vector, but this is the canonical pattern.
        Uri.parse('$v1Base/nutrition/days').replace(
          queryParameters: {'from': from, 'to': to},
        ),
        headers: {'Authorization': 'Bearer $token'},
      ).withTimeout();
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = body['data'] as List<dynamic>? ?? [];
      for (final raw in list) {
        if (raw is! Map<String, dynamic>) continue;
        final dateStr = raw['date'] as String?;
        if (dateStr == null || dateStr.length < 10) continue;
        final p = dateStr.split('-');
        if (p.length != 3) continue;
        final y = int.tryParse(p[0]);
        final m = int.tryParse(p[1]);
        final d = int.tryParse(p[2]);
        if (y == null || m == null || d == null) continue;
        final dayDate = DateTime(y, m, d);
        if (await _isDayDirty(dayDate)) {
          // Local day has unsynced changes (e.g. a meal logged offline) —
          // replay it UP instead of letting the stale server copy erase it.
          final local = await _loadDayFromPrefsOnly(dayDate);
          await _enqueueDayPush(dayDate, local);
          continue;
        }
        final daily = _dailyFromServerJson(raw);
        await _saveDayToPrefs(dayDate, daily);
      }
    } catch (e, st) {
      reportError(e, st, reason: 'nutrition:sync-history');
    }
  }

  static FoodItem _foodItemFromUsdaHit(UsdaSearchFoodHit h, {String? barcode}) {
    final hints = NutritionFoodLabels.genericPortionHints(h.description);
    return FoodItem(
      id: 'usda_fdc_${h.fdcId}',
      name: h.description,
      brand:
          h.dataType != null ? 'USDA · ${h.dataType}' : 'USDA FoodData Central',
      caloriesPer100g: h.caloriesPer100g,
      proteinPer100g: h.proteinPer100g,
      fatPer100g: h.fatPer100g,
      carbsPer100g: h.carbsPer100g,
      category: h.dataType,
      barcode: barcode,
      servingGrams: hints.servingGrams,
      servingLabel: hints.servingLabel,
      portionUnitKey: hints.portionUnitKey,
    );
  }

  static List<FoodItem> _foodItemsFromUsdaHits(List<UsdaSearchFoodHit> hits,
      {String? barcode}) {
    return hits.map((h) => _foodItemFromUsdaHit(h, barcode: barcode)).toList();
  }

  Future<FoodNameSearchResult> searchByName(String query) async {
    final q = query.trim();
    if (q.isEmpty) return (items: <FoodItem>[], errorMessage: null);
    // Primary: USDA (via the backend proxy in release). Fallback: Open Food
    // Facts (keyless, direct) so search still works when the server has no
    // USDA key — otherwise it 503s and the list is empty.
    try {
      final hits = await UsdaFdcClient.searchFoods(q);
      final items = _foodItemsFromUsdaHits(hits);
      if (items.isNotEmpty) return (items: items, errorMessage: null);
      final local = await LocalFoodDatabase.searchByName(q);
      if (local.isNotEmpty) return (items: local, errorMessage: null);
      final off = await OpenFoodFactsClient.searchByName(q);
      return (items: off, errorMessage: null);
    } on UsdaFdcException catch (e) {
      final local = await LocalFoodDatabase.searchByName(q);
      if (local.isNotEmpty) return (items: local, errorMessage: null);
      final off = await OpenFoodFactsClient.searchByName(q);
      // Only surface the USDA error if OFF found nothing either.
      return (items: off, errorMessage: off.isEmpty ? e.userMessage : null);
    } on TimeoutException catch (e) {
      debugPrint('[NutritionService] food search timeout: $e');
      final local = await LocalFoodDatabase.searchByName(q);
      if (local.isNotEmpty) return (items: local, errorMessage: null);
      final off = await OpenFoodFactsClient.searchByName(q);
      return (
        items: off,
        errorMessage:
            off.isEmpty ? 'Search timed out — check your connection.' : null,
      );
    } catch (e, st) {
      reportError(e, st, reason: 'nutrition:search-foods');
      final local = await LocalFoodDatabase.searchByName(q);
      if (local.isNotEmpty) return (items: local, errorMessage: null);
      final off = await OpenFoodFactsClient.searchByName(q);
      return (
        items: off,
        errorMessage: off.isEmpty ? 'Food search failed — try again.' : null
      );
    }
  }

  Future<List<FoodItem>> getByCategory(String category) async => [];

  Future<List<String>> getCategories() async => [];

  /// `food == null && errorMessage == null` means a genuine 'not in the
  /// database'. errorMessage carries network/USDA failures so the UI stops
  /// telling users a real product 'doesn't exist' when the lookup just
  /// failed (offline / 429 / 503) — the name-search path already did this.
  Future<({FoodItem? food, String? errorMessage})> searchByBarcode(
      String barcode) async {
    final code = barcode.trim().replaceAll(RegExp(r'[^\d]'), '');
    if (code.length < 8) return (food: null, errorMessage: null);
    // USDA Branded first; OFF (keyless, direct) as a fallback so barcode scan
    // still resolves when the server has no USDA key.
    try {
      final hit = await UsdaFdcClient.lookupBrandedByGtin(code);
      if (hit != null) {
        return (
          food: _foodItemFromUsdaHit(hit, barcode: code),
          errorMessage: null
        );
      }
      return (
        food: await OpenFoodFactsClient.lookupByBarcode(code),
        errorMessage: null
      );
    } on UsdaFdcException catch (e) {
      final off = await OpenFoodFactsClient.lookupByBarcode(code);
      return (food: off, errorMessage: off == null ? e.userMessage : null);
    } on TimeoutException {
      final off = await OpenFoodFactsClient.lookupByBarcode(code);
      return (
        food: off,
        errorMessage: off == null
            ? 'Barcode lookup timed out — check your connection.'
            : null,
      );
    } catch (e, st) {
      reportError(e, st, reason: 'nutrition:lookup-gtin');
      final off = await OpenFoodFactsClient.lookupByBarcode(code);
      return (
        food: off,
        errorMessage: off == null ? 'Barcode lookup failed — try again.' : null
      );
    }
  }

  Future<DailyNutrition> _loadDayFromPrefsOnly(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _dayKey(date));
    if (raw == null) return DailyNutrition.empty;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (j['entries'] as List<dynamic>? ?? [])
          .map((e) => MealEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return DailyNutrition(
        entries: entries,
        waterMl: j['waterMl'] as int? ?? 0,
        weightKg:
            j['weightKg'] != null ? (j['weightKg'] as num).toDouble() : null,
      );
    } catch (e) {
      debugPrint(
          '[NutritionService._loadDayFromPrefsOnly] decode best-effort skip: $e');
      return DailyNutrition.empty;
    }
  }

  Future<DailyNutrition> getDay(DateTime date) async {
    final token = await _auth.getAccessToken();
    if (token != null) {
      try {
        final q = formatLocalDate(date);
        final res = await http.get(
          Uri.parse('$v1Base/nutrition/day?date=$q'),
          headers: {'Authorization': 'Bearer $token'},
        ).withTimeout();
        if (res.statusCode == 200) {
          final j = jsonDecode(res.body) as Map<String, dynamic>;
          var daily = _dailyFromServerJson(j);
          final local = await _loadDayFromPrefsOnly(date);
          final dirty = await _isDayDirty(date);
          final remoteEmpty = daily.entries.isEmpty &&
              daily.waterMl == 0 &&
              daily.weightKg == null;
          final localHas = local.entries.isNotEmpty ||
              local.waterMl > 0 ||
              local.weightKg != null;
          if (dirty || (remoteEmpty && localHas)) {
            // Dirty = the server never confirmed the latest local write
            // (covers offline adds AND offline deletes — an empty-but-dirty
            // local day must win too, or deleted entries resurrect).
            daily = local;
            await _enqueueDayPush(date, local);
          } else {
            await _saveDayToPrefs(date, daily);
          }
          return daily;
        }
      } catch (e, st) {
        reportError(e, st, reason: 'nutrition:get-day');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _dayKey(date));
    if (raw == null) return DailyNutrition.empty;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (j['entries'] as List<dynamic>? ?? [])
          .map((e) => MealEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      return DailyNutrition(
        entries: entries,
        waterMl: j['waterMl'] as int? ?? 0,
        weightKg:
            j['weightKg'] != null ? (j['weightKg'] as num).toDouble() : null,
      );
    } catch (e) {
      debugPrint('[NutritionService.getDay] prefs decode best-effort skip: $e');
      return DailyNutrition.empty;
    }
  }

  Future<void> addEntry(MealEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _dayKey(entry.loggedAt);
    final day = await _loadDayFromPrefsOnly(entry.loggedAt);
    final updated = List<MealEntry>.from(day.entries)..add(entry);
    final next = DailyNutrition(
      entries: updated,
      waterMl: day.waterMl,
      weightKg: day.weightKg,
    );
    await prefs.setString(key, jsonEncode(_dayToPrefsJson(next)));
    // Local-first: mark dirty BEFORE returning (so a concurrent sync-down
    // cannot overwrite the fresh local write), then push in the background —
    // the UI must not block 30-60s on a cold server to confirm a local log.
    await _markDayDirty(entry.loggedAt, true);
    unawaited(_enqueueDayPush(entry.loggedAt, next));
  }

  Future<void> removeEntry(String entryId, DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _dayKey(date);
    final day = await _loadDayFromPrefsOnly(date);
    final updated = day.entries.where((e) => e.id != entryId).toList();
    final next = DailyNutrition(
      entries: updated,
      waterMl: day.waterMl,
      weightKg: day.weightKg,
    );
    await prefs.setString(key, jsonEncode(_dayToPrefsJson(next)));
    // Local-first: see addEntry — dirty flag first, push in the background.
    await _markDayDirty(date, true);
    unawaited(_enqueueDayPush(date, next));
  }

  Future<void> updateWater(int ml, DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _dayKey(date);
    final day = await _loadDayFromPrefsOnly(date);
    final next = DailyNutrition(
      entries: day.entries,
      waterMl: ml,
      weightKg: day.weightKg,
    );
    await prefs.setString(key, jsonEncode(_dayToPrefsJson(next)));
    // Local-first: see addEntry — dirty flag first, push in the background.
    await _markDayDirty(date, true);
    unawaited(_enqueueDayPush(date, next));
  }

  Future<void> updateWeight(double kg, DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _dayKey(date);
    final day = await _loadDayFromPrefsOnly(date);
    final next = DailyNutrition(
      entries: day.entries,
      waterMl: day.waterMl,
      weightKg: kg,
    );
    await prefs.setString(key, jsonEncode(_dayToPrefsJson(next)));
    // Local-first: see addEntry — dirty flag first, push in the background.
    await _markDayDirty(date, true);
    unawaited(_enqueueDayPush(date, next));
  }

  Future<NutritionGoals> getGoals() async {
    final fromServer = await _fetchGoalsFromProfile();
    return _goalsFromServerOrPrefs(fromServer);
  }

  /// Derives [NutritionGoals] from an already-fetched `GET /v1/me` response
  /// WITHOUT issuing a second `/me` request — same side effects as [getGoals]
  /// (writes to prefs on success, falls back to cached prefs otherwise). Lets
  /// callers that already hold the `/me` body (e.g. the nutrition tab loading
  /// goals + bodyweight together) avoid a duplicate GET.
  Future<NutritionGoals> goalsFromMeResponse(Map<String, dynamic>? me) async {
    final profile = me?['profile'] as Map<String, dynamic>?;
    return _goalsFromServerOrPrefs(NutritionGoals.fromServerProfile(profile));
  }

  Future<NutritionGoals> _goalsFromServerOrPrefs(
      NutritionGoals? fromServer) async {
    if (fromServer != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(await _goalsKey(), jsonEncode(fromServer.toJson()));
      return fromServer;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _goalsKey());
    if (raw == null) return const NutritionGoals();
    try {
      return NutritionGoals.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint(
          '[NutritionService.getGoals] prefs decode best-effort skip: $e');
      return const NutritionGoals();
    }
  }

  Future<NutritionGoals?> _fetchGoalsFromProfile() async {
    final token = await _auth.getAccessToken();
    if (token == null) return null;
    try {
      final res = await http.get(
        Uri.parse('$v1Base/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).withTimeout();
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final profile = data['profile'] as Map<String, dynamic>?;
      return NutritionGoals.fromServerProfile(profile);
    } catch (e, st) {
      reportError(e, st, reason: 'nutrition:fetch-goals');
      return null;
    }
  }

  /// Ultimele [days] zile (inclusiv azi), ordine cronologică vechi → nou.
  /// Uses batch sync endpoint instead of N sequential requests.
  Future<List<NutritionDaySnapshot>> loadNutritionHistory(
      {int days = 30}) async {
    final n = days.clamp(1, 365);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    // Batch sync from server first (1 request instead of N)
    await syncHistoryFromServer(days: n);

    // Read from local prefs (no network)
    final out = <NutritionDaySnapshot>[];
    for (var i = n - 1; i >= 0; i--) {
      final d = todayDate.subtract(Duration(days: i));
      final day = await _loadDayFromPrefsOnly(d);
      out.add(
        NutritionDaySnapshot(
          date: d,
          calories: day.totalCalories,
          protein: day.totalProtein,
          carbs: day.totalCarbs,
          fat: day.totalFat,
          waterMl: day.waterMl,
          weightKg: day.weightKg,
        ),
      );
    }
    return out;
  }

  Future<void> saveGoals(NutritionGoals goals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await _goalsKey(), jsonEncode(goals.toJson()));
    final token = await _auth.getAccessToken();
    if (token == null) return;
    try {
      await http
          .patch(
            Uri.parse('$v1Base/me/profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'dailyCalories': goals.calories,
              'dailyProtein': goals.proteinG,
              'dailyCarbs': goals.carbsG,
              'dailyFat': goals.fatG,
              'dailyWaterMl': goals.waterMl,
            }),
          )
          .withTimeout();
    } catch (e, st) {
      reportError(e, st, reason: 'nutrition:save-goals-patch');
    }
  }

  Future<List<NutritionPlanDay>> generateWeeklyPlan({
    bool force = false,
    int? tzOffsetMinutes,
  }) async {
    final token = await _auth.getAccessToken();
    if (token == null) throw Exception('Not signed in');
    final res = await http
        .post(
          Uri.parse('$v1Base/nutrition/plan/generate-weekly'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'force': force,
            'tzOffset':
                tzOffsetMinutes ?? DateTime.now().timeZoneOffset.inMinutes,
          }),
        )
        .withTimeout(kNutritionWeeklyPlanGenerateTimeout);
    if (res.statusCode != 200) {
      final detail = _nutritionApiErrorDetail(res); // logged only
      debugPrint(
        '[NutritionService.generateWeeklyPlan] HTTP ${res.statusCode}: $detail',
      );
      // 5xx = server fault: never surface raw server text to the user. 4xx may
      // carry an actionable validation message worth showing.
      final friendly = res.statusCode >= 500
          ? 'Could not generate your plan right now. Try again in a few moments.'
          : detail;
      throw NutritionPlanException(friendly);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (data['plan'] as List<dynamic>? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => NutritionPlanDay.fromApiMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<NutritionPlanDay>> getWeeklyPlan({String? weekStart}) async {
    final token = await _auth.getAccessToken();
    if (token == null) return [];
    try {
      final res = await http.get(
        Uri.parse('$v1Base/nutrition/plan/week').replace(
          queryParameters: {
            if (weekStart != null && weekStart.isNotEmpty)
              'weekStart': weekStart,
            'tzOffset': '${DateTime.now().timeZoneOffset.inMinutes}',
          },
        ),
        headers: {'Authorization': 'Bearer $token'},
      ).withTimeout();
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (data['plan'] as List<dynamic>? ?? const []);
      return list
          .whereType<Map>()
          .map((e) => NutritionPlanDay.fromApiMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e, st) {
      reportError(e, st, reason: 'nutrition:get-weekly-plan');
      return [];
    }
  }

  Future<void> patchNutritionPlanDay(
      String dateYmd, NutritionDayMealPlan plan) async {
    final token = await _auth.getAccessToken();
    if (token == null) throw Exception('Not signed in');
    final res = await http
        .patch(
          Uri.parse('$v1Base/nutrition/plan/day'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'date': dateYmd,
            'mealPlan': plan.toPatchJson(),
          }),
        )
        .withTimeout();
    if (res.statusCode != 200) {
      throw Exception(_nutritionApiErrorDetail(res));
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // MyFitnessPal-parity: custom foods, favorites, recipes, recent, templates.
  // ───────────────────────────────────────────────────────────────────────────

  Future<Map<String, String>?> _jsonAuthHeaders() async {
    final token = await _auth.getAccessToken();
    if (token == null) return null;
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json'
    };
  }

  Map<String, dynamic> _customFoodBody({
    required String name,
    String? brand,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    double? servingGrams,
    String? servingLabel,
  }) =>
      {
        'name': name,
        if (brand != null && brand.isNotEmpty) 'brand': brand,
        'caloriesPer100g': caloriesPer100g,
        'proteinPer100g': proteinPer100g,
        'carbsPer100g': carbsPer100g,
        'fatPer100g': fatPer100g,
        if (servingGrams != null) 'servingGrams': servingGrams,
        if (servingLabel != null && servingLabel.isNotEmpty)
          'servingLabel': servingLabel,
      };

  /// User's custom food catalog. `FoodItem.id` is `custom:<uuid>`.
  Future<List<FoodItem>> getCustomFoods() async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) return [];
    try {
      final res = await http
          .get(Uri.parse('$v1Base/nutrition/custom-foods'), headers: headers)
          .withTimeout();
      if (res.statusCode != 200) return [];
      final data = (jsonDecode(res.body) as Map<String, dynamic>)['data']
              as List<dynamic>? ??
          [];
      return data
          .whereType<Map>()
          .map((e) => FoodItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e, st) {
      reportError(e, st, reason: 'nutrition:custom-foods-list');
      return [];
    }
  }

  Future<FoodItem> createCustomFood({
    required String name,
    String? brand,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    double? servingGrams,
    String? servingLabel,
  }) async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) {
      throw const NutritionPlanException('You are not signed in');
    }
    final res = await http
        .post(Uri.parse('$v1Base/nutrition/custom-foods'),
            headers: headers,
            body: jsonEncode(_customFoodBody(
              name: name,
              brand: brand,
              caloriesPer100g: caloriesPer100g,
              proteinPer100g: proteinPer100g,
              carbsPer100g: carbsPer100g,
              fatPer100g: fatPer100g,
              servingGrams: servingGrams,
              servingLabel: servingLabel,
            )))
        .withTimeout();
    if (res.statusCode != 201) {
      throw NutritionPlanException(_nutritionApiErrorDetail(res));
    }
    return FoodItem.fromJson((jsonDecode(res.body)
        as Map<String, dynamic>)['food'] as Map<String, dynamic>);
  }

  /// `customId` is the raw uuid (strip the `custom:` prefix from FoodItem.id).
  Future<FoodItem> updateCustomFood(
    String customId, {
    required String name,
    String? brand,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    double? servingGrams,
    String? servingLabel,
  }) async {
    final id =
        customId.startsWith('custom:') ? customId.substring(7) : customId;
    final headers = await _jsonAuthHeaders();
    if (headers == null) {
      throw const NutritionPlanException('You are not signed in');
    }
    final res = await http
        .put(Uri.parse('$v1Base/nutrition/custom-foods/$id'),
            headers: headers,
            body: jsonEncode(_customFoodBody(
              name: name,
              brand: brand,
              caloriesPer100g: caloriesPer100g,
              proteinPer100g: proteinPer100g,
              carbsPer100g: carbsPer100g,
              fatPer100g: fatPer100g,
              servingGrams: servingGrams,
              servingLabel: servingLabel,
            )))
        .withTimeout();
    if (res.statusCode != 200) {
      throw NutritionPlanException(_nutritionApiErrorDetail(res));
    }
    return FoodItem.fromJson((jsonDecode(res.body)
        as Map<String, dynamic>)['food'] as Map<String, dynamic>);
  }

  Future<void> deleteCustomFood(String customId) async {
    final id =
        customId.startsWith('custom:') ? customId.substring(7) : customId;
    final headers = await _jsonAuthHeaders();
    if (headers == null) return;
    final res = await http
        .delete(Uri.parse('$v1Base/nutrition/custom-foods/$id'),
            headers: headers)
        .withTimeout();
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw NutritionPlanException(_nutritionApiErrorDetail(res));
    }
  }

  // ── Favorites ──────────────────────────────────────────────────────────────
  Future<List<FoodItem>> getFavoriteFoods() async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) return [];
    try {
      final res = await http
          .get(Uri.parse('$v1Base/nutrition/favorite-foods'), headers: headers)
          .withTimeout();
      if (res.statusCode != 200) return [];
      final data = (jsonDecode(res.body) as Map<String, dynamic>)['data']
              as List<dynamic>? ??
          [];
      return data
          .whereType<Map>()
          .map((e) => FoodItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e, st) {
      reportError(e, st, reason: 'nutrition:favorites-list');
      return [];
    }
  }

  Future<void> addFavorite(FoodItem f) async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) return;
    final res = await http
        .post(Uri.parse('$v1Base/nutrition/favorite-foods'),
            headers: headers,
            body: jsonEncode({
              'foodId': f.id,
              'name': f.name,
              if (f.brand.isNotEmpty) 'brand': f.brand,
              'caloriesPer100g': f.caloriesPer100g,
              'proteinPer100g': f.proteinPer100g,
              'carbsPer100g': f.carbsPer100g,
              'fatPer100g': f.fatPer100g,
              if (f.servingGrams != null) 'servingGrams': f.servingGrams,
            }))
        .withTimeout();
    if (res.statusCode != 201) {
      throw NutritionPlanException(_nutritionApiErrorDetail(res));
    }
  }

  Future<void> removeFavorite(String foodId) async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) return;
    await http
        .delete(
            Uri.parse(
                '$v1Base/nutrition/favorite-foods/${Uri.encodeComponent(foodId)}'),
            headers: headers)
        .withTimeout();
  }

  // ── Recipes ────────────────────────────────────────────────────────────────
  Future<List<Recipe>> getRecipes() async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) return [];
    try {
      final res = await http
          .get(Uri.parse('$v1Base/nutrition/recipes'), headers: headers)
          .withTimeout();
      if (res.statusCode != 200) return [];
      final data = (jsonDecode(res.body) as Map<String, dynamic>)['data']
              as List<dynamic>? ??
          [];
      return data
          .whereType<Map>()
          .map((e) => Recipe.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e, st) {
      reportError(e, st, reason: 'nutrition:recipes-list');
      return [];
    }
  }

  Future<Recipe> createRecipe({
    required String name,
    required int servings,
    required List<RecipeIngredient> ingredients,
  }) async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) {
      throw const NutritionPlanException('You are not signed in');
    }
    final res = await http
        .post(Uri.parse('$v1Base/nutrition/recipes'),
            headers: headers,
            body: jsonEncode({
              'name': name,
              'servings': servings,
              'ingredients': ingredients.map((i) => i.toJson()).toList(),
            }))
        .withTimeout();
    if (res.statusCode != 201) {
      throw NutritionPlanException(_nutritionApiErrorDetail(res));
    }
    return Recipe.fromJson((jsonDecode(res.body)
        as Map<String, dynamic>)['recipe'] as Map<String, dynamic>);
  }

  Future<Recipe> updateRecipe(
    String id, {
    required String name,
    required int servings,
    required List<RecipeIngredient> ingredients,
  }) async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) {
      throw const NutritionPlanException('You are not signed in');
    }
    final res = await http
        .put(Uri.parse('$v1Base/nutrition/recipes/$id'),
            headers: headers,
            body: jsonEncode({
              'name': name,
              'servings': servings,
              'ingredients': ingredients.map((i) => i.toJson()).toList(),
            }))
        .withTimeout();
    if (res.statusCode != 200) {
      throw NutritionPlanException(_nutritionApiErrorDetail(res));
    }
    return Recipe.fromJson((jsonDecode(res.body)
        as Map<String, dynamic>)['recipe'] as Map<String, dynamic>);
  }

  Future<void> deleteRecipe(String id) async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) return;
    final res = await http
        .delete(Uri.parse('$v1Base/nutrition/recipes/$id'), headers: headers)
        .withTimeout();
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw NutritionPlanException(_nutritionApiErrorDetail(res));
    }
  }

  // ── Recent foods (derived from diary history) ──────────────────────────────
  Future<List<FoodItem>> getRecentFoods({int limit = 20}) async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) return [];
    try {
      final res = await http
          .get(Uri.parse('$v1Base/nutrition/recent-foods?limit=$limit'),
              headers: headers)
          .withTimeout();
      if (res.statusCode != 200) return [];
      final data = (jsonDecode(res.body) as Map<String, dynamic>)['data']
              as List<dynamic>? ??
          [];
      return data
          .whereType<Map>()
          .map((e) => FoodItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e, st) {
      reportError(e, st, reason: 'nutrition:recent-foods');
      return [];
    }
  }

  // ── Meal templates ("My Meals") ───────────────────────────────────────────
  Future<List<MealTemplate>> getMealTemplates() async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) return [];
    try {
      final res = await http
          .get(Uri.parse('$v1Base/nutrition/templates'), headers: headers)
          .withTimeout();
      if (res.statusCode != 200) return [];
      final list = (jsonDecode(res.body) as Map<String, dynamic>)['templates']
              as List<dynamic>? ??
          [];
      return list
          .whereType<Map>()
          .map((e) => MealTemplate.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e, st) {
      reportError(e, st, reason: 'nutrition:templates-list');
      return [];
    }
  }

  Future<MealTemplate> createMealTemplate(
      String name, List<MealTemplateItem> items) async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) {
      throw const NutritionPlanException('You are not signed in');
    }
    final res = await http
        .post(Uri.parse('$v1Base/nutrition/templates'),
            headers: headers,
            body: jsonEncode(
                {'name': name, 'items': items.map((i) => i.toJson()).toList()}))
        .withTimeout();
    if (res.statusCode != 201) {
      throw NutritionPlanException(_nutritionApiErrorDetail(res));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final tpl = body['template'] ?? body;
    return MealTemplate.fromJson(Map<String, dynamic>.from(tpl as Map));
  }

  Future<void> deleteMealTemplate(String id) async {
    final headers = await _jsonAuthHeaders();
    if (headers == null) return;
    final res = await http
        .delete(Uri.parse('$v1Base/nutrition/templates/$id'), headers: headers)
        .withTimeout();
    if (res.statusCode != 204 && res.statusCode != 200) {
      throw NutritionPlanException(_nutritionApiErrorDetail(res));
    }
  }
}
