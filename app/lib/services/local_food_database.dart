import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'nutrition_food_labels.dart';
import 'nutrition_service.dart' show FoodItem;

/// Tiny bundled fallback DB for generic foods.
///
/// Network search stays primary, but this keeps basic foods like eggs, rice,
/// chicken, oats, banana, etc. searchable when USDA is not configured or Open
/// Food Facts throttles anonymous calls.
class LocalFoodDatabase {
  LocalFoodDatabase._();

  static Database? _db;
  static const _assetPath = 'assets/foods.db';
  static const _dbName = 'zvelt_foods_asset_v1.db';

  static Future<List<FoodItem>> searchByName(String query,
      {int limit = 25}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <FoodItem>[];
    try {
      final db = await _open();
      final variants = _queryVariants(q);
      final rows = await db.rawQuery(
        '''
        SELECT id, name, category, calories_per_100g, protein_per_100g,
               fat_per_100g, carbs_per_100g
          FROM foods
         WHERE ${variants.map((_) => '(lower(name) LIKE ? OR lower(category) LIKE ?)').join(' OR ')}
         ORDER BY
           CASE
             WHEN lower(name) = ? THEN 0
             WHEN lower(name) LIKE ? THEN 1
             WHEN lower(category) = ? THEN 2
             ELSE 3
           END,
           name ASC
         LIMIT ?
        ''',
        <Object?>[
          for (final v in variants) ...['%$v%', '%$v%'],
          q,
          '$q%',
          q,
          limit.clamp(1, 50),
        ],
      );
      return rows.map(_fromRow).toList(growable: false);
    } catch (e) {
      debugPrint('[LocalFoodDatabase.searchByName] fallback skipped: $e');
      return const <FoodItem>[];
    }
  }

  static Set<String> _queryVariants(String q) {
    final out = <String>{q};
    if (q.endsWith('s') && q.length > 3) out.add(q.substring(0, q.length - 1));
    return out;
  }

  static Future<Database> _open() async {
    final cached = _db;
    if (cached != null && cached.isOpen) return cached;

    final base = await getDatabasesPath();
    final path = p.join(base, _dbName);
    final file = File(path);
    if (!await file.exists()) {
      await Directory(p.dirname(path)).create(recursive: true);
      final data = await rootBundle.load(_assetPath);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    _db = await openDatabase(path, readOnly: true);
    return _db!;
  }

  static FoodItem _fromRow(Map<String, Object?> row) {
    final name = row['name']?.toString() ?? 'Food';
    final hints = NutritionFoodLabels.genericPortionHints(name);
    return FoodItem(
      id: 'local_food_${row['id']}',
      name: name,
      brand: 'Zvelt foods',
      category: row['category']?.toString(),
      caloriesPer100g: _d(row['calories_per_100g']),
      proteinPer100g: _d(row['protein_per_100g']),
      fatPer100g: _d(row['fat_per_100g']),
      carbsPer100g: _d(row['carbs_per_100g']),
      servingGrams: hints.servingGrams,
      servingLabel: hints.servingLabel,
      portionUnitKey: hints.portionUnitKey,
    );
  }

  static double _d(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }
}
