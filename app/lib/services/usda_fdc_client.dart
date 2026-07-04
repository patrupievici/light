import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart' show v1Base;
import '../config/usda_api_config.dart';
import 'auth_service.dart';
import 'http_client.dart';

/// USDA sau proxy-ul Zvelt a răspuns cu eroare utilizabilă în UI.
class UsdaFdcException implements Exception {
  UsdaFdcException({required this.statusCode, required this.body});
  final int statusCode;
  final String body;

  String get userMessage {
    if (body.contains('APP_AUTH_REQUIRED')) {
      return 'Sign in to search foods.';
    }
    switch (statusCode) {
      case 401:
      case 403:
        return body.contains('APP_AUTH_REQUIRED')
            ? 'Sign in to search foods.'
            : 'Food search was refused. Sign in again or check USDA_API_KEY on the server.';
      case 429:
        return 'USDA rate limit (~1000 requests/hour). Try again later.';
      case 503:
        final t = body.trim();
        if (t.isEmpty) return 'Food search is not configured on the server (USDA_API_KEY).';
        return t.length > 220 ? '${t.substring(0, 220)}…' : t;
      default:
        return 'Food search unavailable (HTTP $statusCode).';
    }
  }
}

/// Un rând din căutare sau din `/food/{fdcId}` — macronutrienți per 100 g acolo unde FDC îi dă astfel.
class UsdaSearchFoodHit {
  const UsdaSearchFoodHit({
    required this.fdcId,
    required this.description,
    required this.dataType,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.fatPer100g,
    required this.carbsPer100g,
  });

  final int fdcId;
  final String description;
  final String? dataType;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double carbsPer100g;
}

/// Client pentru [FoodData Central](https://fdc.nal.usda.gov/api-guide.html).
///
/// **Prioritate:** dacă există `USDA_API_KEY` în client (`dart-define` sau dotenv), apel direct la USDA.
/// Altfel folosește proxy-ul autentificat `/v1/nutrition/usda/…` — cheia rămâne în `.env` pe backend.
class UsdaFdcClient {
  UsdaFdcClient._();

  static const String _base = 'https://api.nal.usda.gov/fdc/v1';

  // Release builds always proxy — key never embedded in shipped APK.
  static bool get _useDirectUsda => !kReleaseMode && UsdaApiConfig.apiKey.trim().isNotEmpty;

  static Future<Map<String, String>> _jsonAuthHeaders() async {
    final auth = AuthService();
    final token = await auth.getAccessToken();
    final h = <String, String>{'Content-Type': 'application/json; charset=utf-8'};
    if (token != null && token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  static Future<Map<String, String>> _bearerOnlyHeaders() async {
    final auth = AuthService();
    final token = await auth.getAccessToken();
    if (token == null || token.isEmpty) return {};
    return {'Authorization': 'Bearer $token'};
  }

  static UsdaFdcException _badResponse(http.Response res) {
    var detail = res.body;
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['message'] != null) {
        detail = j['message'].toString();
      }
    } catch (e) {
      debugPrint('[UsdaFdcClient._badResponse] decode best-effort skip: $e');
    }
    return UsdaFdcException(statusCode: res.statusCode, body: detail);
  }

  static List<UsdaSearchFoodHit> _hitsFromSearchResponseBody(String responseBody) {
    final map = jsonDecode(responseBody) as Map<String, dynamic>;
    final foods = map['foods'] as List<dynamic>? ?? [];

    final out = <UsdaSearchFoodHit>[];
    final seen = <int>{};
    for (final raw in foods) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final hit = _hitFromSearchMap(m);
      if (hit == null) continue;
      if (!seen.add(hit.fdcId)) continue;
      out.add(hit);
    }
    return out;
  }

  static Future<List<UsdaSearchFoodHit>> searchFoods(String query, {int pageSize = 30}) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final payload = jsonEncode({
      'query': q,
      'pageSize': pageSize.clamp(1, 50),
      'pageNumber': 1,
      'dataType': ['Foundation', 'SR Legacy', 'Survey (FNDDS)'],
    });

    late final http.Response res;
    if (_useDirectUsda) {
      final key = UsdaApiConfig.apiKey.trim();
      final uri = Uri.parse('$_base/foods/search').replace(queryParameters: {'api_key': key});
      res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: payload,
          )
          .withTimeout();
    } else {
      final headers = await _jsonAuthHeaders();
      if (!headers.containsKey('Authorization')) {
        throw UsdaFdcException(statusCode: 401, body: 'APP_AUTH_REQUIRED');
      }
      final uri = Uri.parse('$v1Base/nutrition/usda/foods/search');
      res = await http.post(uri, headers: headers, body: payload).withTimeout();
    }

    if (res.statusCode != 200) {
      throw _badResponse(res);
    }
    return _hitsFromSearchResponseBody(res.body);
  }

  /// Produse ambalate (GTIN/UPC/EAN) — căutare în tipul Branded, apoi nutrienți din `/food/{id}` dacă e nevoie.
  static Future<UsdaSearchFoodHit?> lookupBrandedByGtin(String barcodeDigits) async {
    final raw = barcodeDigits.replaceAll(RegExp(r'\D'), '');
    if (raw.length < 8) return null;

    final payload = jsonEncode({
      'query': raw,
      'pageSize': 25,
      'pageNumber': 1,
      'dataType': ['Branded'],
    });

    late final http.Response res;
    if (_useDirectUsda) {
      final key = UsdaApiConfig.apiKey.trim();
      final uri = Uri.parse('$_base/foods/search').replace(queryParameters: {'api_key': key});
      res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: payload,
          )
          .withTimeout();
    } else {
      final headers = await _jsonAuthHeaders();
      if (!headers.containsKey('Authorization')) return null;
      final uri = Uri.parse('$v1Base/nutrition/usda/foods/search');
      res = await http.post(uri, headers: headers, body: payload).withTimeout();
    }

    if (res.statusCode != 200) return null;

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final foods = map['foods'] as List<dynamic>? ?? [];

    Map<String, dynamic>? match;
    for (final el in foods) {
      if (el is! Map) continue;
      final m = Map<String, dynamic>.from(el);
      final gtin = m['gtinUpc']?.toString() ?? '';
      if (_gtinEquivalent(gtin, raw)) {
        match = m;
        break;
      }
    }
    if (match == null) {
      // No food's gtinUpc actually matches the scanned code. Do NOT accept a
      // lone fuzzy text-search hit as "the scanned product" — that logs the
      // wrong macros. Honest not-found.
      return null;
    }

    var hit = _hitFromSearchMap(match);
    final id = hit?.fdcId ?? _fdcIdFrom(match);
    if (id == null) return hit;

    if (hit == null ||
        (hit.caloriesPer100g <= 0 &&
            hit.proteinPer100g <= 0 &&
            hit.fatPer100g <= 0 &&
            hit.carbsPer100g <= 0)) {
      hit = await fetchFoodByFdcId(id);
    }
    return hit;
  }

  static int? _fdcIdFrom(Map<String, dynamic> m) {
    final idRaw = m['fdcId'];
    return switch (idRaw) {
      final int i => i,
      final num n => n.toInt(),
      _ => int.tryParse(idRaw?.toString() ?? ''),
    };
  }

  static Future<UsdaSearchFoodHit?> fetchFoodByFdcId(int fdcId) async {
    late final http.Response res;
    if (_useDirectUsda) {
      final key = UsdaApiConfig.apiKey.trim();
      final uri = Uri.parse('$_base/food/$fdcId').replace(queryParameters: {'api_key': key});
      res = await http.get(uri).withTimeout();
    } else {
      final headers = await _bearerOnlyHeaders();
      if (!headers.containsKey('Authorization')) return null;
      final uri = Uri.parse('$v1Base/nutrition/usda/food/$fdcId');
      res = await http.get(uri, headers: headers).withTimeout();
    }

    if (res.statusCode != 200) return null;

    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return _hitFromDetailMap(m);
  }

  static bool _gtinEquivalent(String a, String b) {
    final da = a.replaceAll(RegExp(r'\D'), '');
    final db = b.replaceAll(RegExp(r'\D'), '');
    if (da.isEmpty || db.isEmpty) return false;
    if (da == db) return true;
    final ta = da.replaceFirst(RegExp(r'^0+'), '');
    final tb = db.replaceFirst(RegExp(r'^0+'), '');
    if (ta.isNotEmpty && tb.isNotEmpty && ta == tb) return true;
    return da.endsWith(db) || db.endsWith(da);
  }

  static UsdaSearchFoodHit? _hitFromDetailMap(Map<String, dynamic> m) {
    final fdcId = _fdcIdFrom(m);
    if (fdcId == null) return null;

    final name = m['description']?.toString().trim();
    if (name == null || name.isEmpty) return null;

    final dataType = m['dataType']?.toString().trim();
    final nutrients = m['foodNutrients'];
    final macros = nutrients is List ? _macrosPer100gFromNutrients(nutrients) : (0.0, 0.0, 0.0, 0.0);

    return UsdaSearchFoodHit(
      fdcId: fdcId,
      description: name,
      dataType: dataType?.isEmpty ?? true ? null : dataType,
      caloriesPer100g: macros.$1,
      proteinPer100g: macros.$2,
      fatPer100g: macros.$3,
      carbsPer100g: macros.$4,
    );
  }

  static UsdaSearchFoodHit? _hitFromSearchMap(Map<String, dynamic> m) => _hitFromDetailMap(m);

  static (double, double, double, double) _macrosPer100gFromNutrients(List<dynamic> nutrients) {
    double kcal = 0, protein = 0, fat = 0, carbs = 0;

    for (final n in nutrients) {
      if (n is! Map) continue;
      final map = Map<String, dynamic>.from(n);

      String nutrientName = (map['nutrientName'] ?? map['name'] ?? '').toString().toLowerCase();
      String unit = (map['unitName'] ?? '').toString().toLowerCase();

      if (map['nutrient'] is Map) {
        final nut = Map<String, dynamic>.from(map['nutrient'] as Map);
        if (nutrientName.isEmpty) {
          nutrientName = (nut['name'] ?? '').toString().toLowerCase();
        }
        if (unit.isEmpty) {
          unit = (nut['unitName'] ?? '').toString().toLowerCase();
        }
      }

      final v = _parseDouble(map['value'] ?? map['amount']);

      if (nutrientName.contains('energy') || nutrientName.contains('calorie')) {
        if (unit == 'kj' || nutrientName.contains('kj')) {
          if (v > 0) kcal = v / 4.184;
        } else if (unit == 'kcal' || unit.contains('kcal') || unit.isEmpty) {
          if (v > 0) kcal = v;
        }
        continue;
      }
      if (nutrientName.contains('protein')) {
        protein = v;
        continue;
      }
      if (nutrientName.contains('lipid') ||
          nutrientName.contains('total fat') ||
          (nutrientName == 'fat' && !nutrientName.contains('trans'))) {
        fat = v;
        continue;
      }
      if (nutrientName.contains('carbohydrate') ||
          nutrientName.contains('carbohydrate, by difference')) {
        carbs = v;
      }
    }

    return (
      kcal < 0 ? 0.0 : kcal,
      protein < 0 ? 0.0 : protein,
      fat < 0 ? 0.0 : fat,
      carbs < 0 ? 0.0 : carbs,
    );
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }
}
