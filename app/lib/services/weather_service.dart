import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart' show v1Base;
import 'auth_service.dart';
import 'http_client.dart';

class WeatherSnapshot {
  WeatherSnapshot({
    this.tempC,
    this.description,
    this.icon,
    this.error,
  });
  final double? tempC;
  final String? description;
  final String? icon;
  final String? error;
}

class WeatherService {
  WeatherService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  Future<WeatherSnapshot> current({required double lat, required double lon}) async {
    final Map<String, String> headers;
    try {
      headers = await authedReadHeaders(auth: _auth);
    } catch (_) {
      return WeatherSnapshot(error: 'Not signed in');
    }
    final res = await http.get(
      Uri.parse('$v1Base/weather/current').replace(queryParameters: {
        'lat': '$lat',
        'lon': '$lon',
      }),
      headers: headers,
    ).withTimeout();
    if (res.statusCode != 200) {
      return WeatherSnapshot(error: 'Weather n/a');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return WeatherSnapshot(
      tempC: (j['tempC'] as num?)?.toDouble(),
      description: j['description'] as String?,
      icon: j['icon'] as String?,
    );
  }
}
