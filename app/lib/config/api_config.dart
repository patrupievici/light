// Backend base URL.
//
// Productie: https://zveltutzu.onrender.com (default pentru build release).
// Dev local emulator: flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
// Dev local telefon fizic: flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3000
const String _kProductionUrl = 'https://zveltutzu.onrender.com';

const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: _kProductionUrl,
);

String get v1Base => '$apiBaseUrl/v1';

/// Imagini servite de backend la `/uploads/...` sau URL deja absolut.
String mediaAbsoluteUrl(String? pathOrUrl) {
  if (pathOrUrl == null || pathOrUrl.isEmpty) return '';
  final p = pathOrUrl.trim();
  if (p.startsWith('http://') || p.startsWith('https://')) return p;
  if (p.startsWith('/')) return '$apiBaseUrl$p';
  return '$apiBaseUrl/$p';
}
