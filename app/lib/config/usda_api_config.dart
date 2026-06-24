import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// USDA FoodData Central — cheie **data.gov** / FDC (opțională în client).
///
/// **Dacă nu pui cheia în app:** căutarea merge prin backend (`/v1/nutrition/usda/…`) cu
/// `USDA_API_KEY` în `.env` pe server — recomandat pentru producție.
///
/// **Prioritate în client:** `flutter run --dart-define=USDA_API_KEY=…` → apoi
/// fișierul [assets/dotenv] (`USDA_API_KEY=…`), încărcat la pornire în `main.dart`.
///
/// Nu publica cheia în repo-uri deschise; USDA poate dezactiva chei expuse.
class UsdaApiConfig {
  UsdaApiConfig._();

  static String _dotEnvKey = '';

  /// Apelat după `await dotenv.load(fileName: 'assets/dotenv')` în `main`.
  static void syncFromDotenv() {
    try {
      _dotEnvKey = dotenv.env['USDA_API_KEY']?.trim() ?? '';
    } catch (e) {
      debugPrint('[UsdaApiConfig.syncFromDotenv] dotenv read best-effort skip: $e');
      _dotEnvKey = '';
    }
  }

  static String get apiKey {
    const fromDefine = String.fromEnvironment('USDA_API_KEY');
    if (fromDefine.trim().isNotEmpty) return fromDefine.trim();
    return _dotEnvKey;
  }

  static bool get isConfigured => apiKey.isNotEmpty;
}
