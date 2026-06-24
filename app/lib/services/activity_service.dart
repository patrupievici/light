import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart' show v1Base;
import '../models/game_xp_models.dart';
import 'auth_service.dart';
import 'http_client.dart';

class XpBreakdownLine {
  const XpBreakdownLine({
    required this.label,
    required this.pct,
    required this.mult,
    required this.xp,
    this.detail,
  });

  final String label;
  final int pct;
  final int mult;
  final int xp;
  final String? detail;

  factory XpBreakdownLine.fromJson(Map<String, dynamic> j) => XpBreakdownLine(
        label: j['label'] as String? ?? '',
        pct: (j['pct'] as num?)?.toInt() ?? 0,
        mult: (j['mult'] as num?)?.toInt() ?? 1,
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        detail: j['detail'] as String?,
      );
}

class CardioCompleteResult {
  const CardioCompleteResult({
    required this.xpGain,
    this.gameXp,
    this.pctOfWr = 0,
    this.breakdown = const [],
  });

  final int xpGain;
  final GameXpSnapshot? gameXp;
  final int pctOfWr;
  final List<XpBreakdownLine> breakdown;

  factory CardioCompleteResult.fromJson(Map<String, dynamic> j) {
    final raw = j['xpBreakdown'];
    final lines = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => XpBreakdownLine.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <XpBreakdownLine>[];
    return CardioCompleteResult(
      xpGain: (j['xpGain'] as num?)?.toInt() ?? 0,
      gameXp: j['gameXp'] is Map<String, dynamic>
          ? GameXpSnapshot.fromJson(j['gameXp'] as Map<String, dynamic>)
          : null,
      pctOfWr: (j['pctOfWr'] as num?)?.toInt() ?? (lines.isNotEmpty ? lines.first.pct : 0),
      breakdown: lines,
    );
  }
}

/// Cardio XP + calendar-related activity API.
class ActivityService {
  ActivityService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  Future<Map<String, String>> _headers() => authedJsonHeaders(auth: _auth);

  /// POST /v1/activities/cardio/complete
  Future<CardioCompleteResult> completeCardio({
    required String mode,
    required double distanceM,
    required int durationSec,
    String source = 'app',
  }) async {
    final res = await http
        .post(
          Uri.parse('$v1Base/activities/cardio/complete'),
          headers: await _headers(),
          body: jsonEncode({
            'mode': mode,
            'distanceM': distanceM,
            'durationSec': durationSec,
            'source': source,
          }),
        )
        .withTimeout();
    if (res.statusCode != 200) {
      final d = jsonDecode(res.body);
      if (d is Map && d['message'] != null) throw Exception(d['message']);
      throw Exception('Could not award cardio XP (${res.statusCode})');
    }
    return CardioCompleteResult.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
