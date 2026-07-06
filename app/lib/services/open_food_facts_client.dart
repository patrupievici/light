import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'http_client.dart';
import 'nutrition_service.dart' show FoodItem;

/// Keyless food data from Open Food Facts (https://openfoodfacts.org).
///
/// Used as a fallback for name/barcode search when the USDA path is
/// unavailable (in release the app proxies USDA through the backend, which
/// returns 503 when the server has no USDA_API_KEY). OFF needs no key, so
/// searching it directly from the client keeps food search working without a
/// server config or an app secret. Results carry macros per 100 g embedded in
/// the [FoodItem], so logging works even though the id is an `off:<code>` key.
class OpenFoodFactsClient {
  OpenFoodFactsClient._();

  // OFF asks every client to identify itself in the User-Agent.
  static const Map<String, String> _headers = {
    'User-Agent': 'Zvelt/1.0 (Flutter; nutrition food search)',
  };

  /// Search products by name. Returns foods that have a usable name + macros.
  static Future<List<FoodItem>> searchByName(String query, {int pageSize = 25}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final uri = Uri.parse('https://world.openfoodfacts.org/cgi/search.pl').replace(
      queryParameters: {
        'search_terms': q,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '$pageSize',
        'fields': 'code,product_name,brands,nutriments,image_small_url,serving_quantity',
      },
    );
    try {
      final res = await http.get(uri, headers: _headers).withTimeout();
      if (res.statusCode != 200) return [];
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final products = map['products'] as List<dynamic>? ?? const [];
      final out = <FoodItem>[];
      final seen = <String>{};
      for (final raw in products) {
        if (raw is! Map) continue;
        final item = _foodFromProduct(Map<String, dynamic>.from(raw));
        if (item == null) continue;
        if (!seen.add(item.id)) continue;
        out.add(item);
      }
      return out;
    } catch (e) {
      debugPrint('[OpenFoodFactsClient.searchByName] best-effort skip: $e');
      return [];
    }
  }

  /// Look up a single product by barcode (GTIN/EAN/UPC).
  static Future<FoodItem?> lookupByBarcode(String barcode) async {
    final code = barcode.replaceAll(RegExp(r'\D'), '');
    if (code.length < 8) return null;
    final uri = Uri.parse('https://world.openfoodfacts.org/api/v2/product/$code.json').replace(
      queryParameters: {
        'fields': 'code,product_name,brands,nutriments,image_small_url,serving_quantity',
      },
    );
    try {
      final res = await http.get(uri, headers: _headers).withTimeout();
      if (res.statusCode != 200) return null;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if ((map['status'] as num?)?.toInt() != 1) return null;
      final product = map['product'];
      if (product is! Map) return null;
      return _foodFromProduct(Map<String, dynamic>.from(product));
    } catch (e) {
      debugPrint('[OpenFoodFactsClient.lookupByBarcode] best-effort skip: $e');
      return null;
    }
  }

  static FoodItem? _foodFromProduct(Map<String, dynamic> p) {
    final name = (p['product_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null;
    final code = p['code']?.toString().trim() ?? '';
    if (code.isEmpty) return null;

    final n = p['nutriments'];
    final nutriments = n is Map ? Map<String, dynamic>.from(n) : const <String, dynamic>{};
    final kcal = _kcalPer100g(nutriments);
    final protein = _num(nutriments['proteins_100g']);
    final fat = _num(nutriments['fat_100g']);
    final carbs = _num(nutriments['carbohydrates_100g']);
    // Skip products with no usable macros — they'd log as 0 kcal.
    if (kcal <= 0 && protein <= 0 && fat <= 0 && carbs <= 0) return null;

    final brands = (p['brands'] as String?)?.trim();
    final serving = _num(p['serving_quantity']);

    return FoodItem(
      id: 'off:$code',
      name: name,
      brand: (brands != null && brands.isNotEmpty) ? brands : 'Open Food Facts',
      caloriesPer100g: kcal,
      proteinPer100g: protein,
      fatPer100g: fat,
      carbsPer100g: carbs,
      imageUrl: (p['image_small_url'] as String?)?.trim(),
      barcode: code,
      servingGrams: serving > 0 ? serving : null,
    );
  }

  /// OFF gives `energy-kcal_100g` on most products; fall back to converting the
  /// kJ `energy_100g` when only that is present.
  static double _kcalPer100g(Map<String, dynamic> n) {
    final kcal = _num(n['energy-kcal_100g']);
    if (kcal > 0) return kcal;
    final kj = _num(n['energy_100g']);
    return kj > 0 ? kj / 4.184 : 0;
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final d = double.tryParse(v.toString().replaceAll(',', '.'));
    return (d != null && d > 0) ? d : 0;
  }
}
