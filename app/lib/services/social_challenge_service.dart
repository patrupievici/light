import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart' show v1Base;
import '../models/social_challenge.dart';
import '_crash_reporter.dart';
import 'auth_service.dart';

/// Provocări sociale: `GET/POST/DELETE /v1/challenges`; fallback local dacă nu e token sau rețea.
class SocialChallengeService {
  SocialChallengeService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  static const _prefsPrefix = 'zvelt_social_challenges_v1';

  Future<String> _prefsKey() async {
    final id = await _auth.getCurrentUserId();
    return '${_prefsPrefix}_${id ?? 'anonymous'}';
  }

  Future<Map<String, String>> _headersAuth() async {
    final token = await _auth.getAccessToken();
    if (token == null) return {};
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  bool _looksLikeUuid(String id) {
    final t = id.trim().toLowerCase();
    return RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(t);
  }

  bool _looksLikeNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('timeoutexception') ||
        s.contains('failed host lookup') ||
        s.contains('connection refused') ||
        s.contains('connection reset') ||
        s.contains('network is unreachable');
  }

  Future<List<SocialChallenge>> loadActive() async {
    final headers = await _headersAuth();
    if (headers.isNotEmpty) {
      try {
        final res = await http
            .get(Uri.parse('$v1Base/challenges/feed'), headers: headers)
            .timeout(const Duration(seconds: 22));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final list = data['data'] as List<dynamic>? ?? [];
          return list.map(SocialChallenge.fromJson).whereType<SocialChallenge>().toList();
        }
      } catch (e, st) {
        reportError(e, st, reason: 'challenges:load-active-feed');
      }
    }
    final all = await _loadAllLocal();
    return all.where((c) => !c.isExpired).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<SocialChallenge>> _loadAllLocal() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(await _prefsKey());
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map(SocialChallenge.fromJson).whereType<SocialChallenge>().toList();
    } catch (e) {
      debugPrint('[SocialChallenge._loadAllLocal] decode best-effort skip: $e');
      return [];
    }
  }

  Future<void> _saveLocal(List<SocialChallenge> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      await _prefsKey(),
      jsonEncode(list.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _addLocal(SocialChallenge challenge) async {
    final list = await _loadAllLocal();
    list.insert(0, challenge);
    await _saveLocal(list);
  }

  Future<void> _removeLocal(String id) async {
    final list = await _loadAllLocal();
    list.removeWhere((e) => e.id == id);
    await _saveLocal(list);
  }

  Future<void> _upsertLocal(SocialChallenge challenge) async {
    final list = await _loadAllLocal();
    final idx = list.indexWhere((e) => e.id == challenge.id);
    if (idx >= 0) {
      list[idx] = challenge;
    } else {
      list.insert(0, challenge);
    }
    await _saveLocal(list);
  }

  /// Trimite la server; dacă nu există token sau pică rețeaua, salvează local.
  Future<void> publish(SocialChallenge draft) async {
    final headers = await _headersAuth();
    if (headers.isEmpty) {
      await _addLocal(draft);
      return;
    }

    try {
      final body = <String, dynamic>{
        'kind': draft.kind.name,
        'customTitle': draft.customTitle,
        'visibility': draft.visibility,
        'durationDays': draft.durationDays,
      };
      final hint = draft.targetHint?.trim();
      if (hint != null && hint.isNotEmpty) body['targetHint'] = hint;

      final res = await http
          .post(
            Uri.parse('$v1Base/challenges'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode == 201) {
        try {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          final row = map['data'];
          final saved = SocialChallenge.fromJson(row);
          if (saved != null) {
            await _removeLocal(draft.id);
            await _upsertLocal(saved);
          }
        } catch (e, st) {
          reportError(e, st, reason: 'challenges:publish-decode');
        }
        return;
      }

      var msg = 'Could not publish (${res.statusCode})';
      try {
        final j = jsonDecode(res.body);
        if (j is Map && j['message'] is String) msg = j['message'] as String;
      } catch (e) {
        debugPrint('[SocialChallenge.publish] error-body decode best-effort skip: $e');
      }
      throw Exception(msg);
    } catch (e) {
      if (_looksLikeNetworkError(e)) {
        await _addLocal(draft);
        return;
      }
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    final headers = await _headersAuth();
    if (headers.isNotEmpty && _looksLikeUuid(id)) {
      try {
        await http
            .delete(Uri.parse('$v1Base/challenges/$id'), headers: headers)
            .timeout(const Duration(seconds: 18));
      } catch (e, st) {
        reportError(e, st, reason: 'challenges:delete');
      }
    }
    await _removeLocal(id);
  }

  /// POST /v1/challenges/:id/join — trata 200 (already joined) și 201 (joined) ca succes.
  Future<void> joinChallenge(String challengeId) async {
    final headers = await _headersAuth();
    if (headers.isEmpty) throw Exception('Not signed in');
    final res = await http
        .post(
          Uri.parse('$v1Base/challenges/$challengeId/join'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 22));
    if (res.statusCode == 200 || res.statusCode == 201) return;
    String msg = 'Could not join challenge (${res.statusCode})';
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['message'] is String) msg = j['message'] as String;
    } catch (e) {
      debugPrint('[SocialChallenge.join] error-body decode best-effort skip: $e');
    }
    throw Exception(msg);
  }

  /// DELETE /v1/challenges/:id/leave
  Future<void> leaveChallenge(String challengeId) async {
    final headers = await _headersAuth();
    if (headers.isEmpty) throw Exception('Not signed in');
    final res = await http
        .delete(
          Uri.parse('$v1Base/challenges/$challengeId/leave'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 22));
    if (res.statusCode == 204 || res.statusCode == 200) return;
    String msg = 'Could not leave challenge (${res.statusCode})';
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['message'] is String) msg = j['message'] as String;
    } catch (e) {
      debugPrint('[SocialChallenge.leave] error-body decode best-effort skip: $e');
    }
    throw Exception(msg);
  }

  /// GET /v1/challenges/:id/participants — returnează { data: [...], total: int }.
  Future<Map<String, dynamic>> getChallengeParticipants(String challengeId) async {
    final headers = await _headersAuth();
    if (headers.isEmpty) return {'data': <dynamic>[], 'total': 0};
    final res = await http
        .get(
          Uri.parse('$v1Base/challenges/$challengeId/participants'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 22));
    if (res.statusCode != 200) return {'data': <dynamic>[], 'total': 0};
    try {
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return {
        'data': j['data'] ?? <dynamic>[],
        'total': (j['total'] as num?)?.toInt() ?? 0,
      };
    } catch (e, st) {
      reportError(e, st, reason: 'challenges:get-participants');
      return {'data': <dynamic>[], 'total': 0};
    }
  }

  /// POST /v1/challenges/:id/progress — logs an amount (server auto-joins).
  /// Returns { total, rank, participants }.
  Future<({double total, int rank})> logProgress(
      String challengeId, double amount) async {
    final headers = await _headersAuth();
    if (headers.isEmpty) throw Exception('Not signed in');
    final res = await http
        .post(
          Uri.parse('$v1Base/challenges/$challengeId/progress'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'amount': amount}),
        )
        .timeout(const Duration(seconds: 22));
    if (res.statusCode != 201 && res.statusCode != 200) {
      String msg = 'Could not log progress (${res.statusCode})';
      try {
        final j = jsonDecode(res.body);
        if (j is Map && j['message'] is String) msg = j['message'] as String;
      } catch (_) {}
      throw Exception(msg);
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final data = j['data'] as Map<String, dynamic>? ?? const {};
    return (
      total: (data['total'] as num?)?.toDouble() ?? amount,
      rank: (data['rank'] as num?)?.toInt() ?? 0,
    );
  }

  /// GET /v1/challenges/:id/standings — full roster with totals + my rank.
  /// Returns { data: [rows], me: {rank,total}? }.
  Future<Map<String, dynamic>> getStandings(String challengeId) async {
    final headers = await _headersAuth();
    if (headers.isEmpty) return {'data': <dynamic>[], 'me': null};
    final res = await http
        .get(
          Uri.parse('$v1Base/challenges/$challengeId/standings'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 22));
    if (res.statusCode != 200) {
      throw Exception('Standings failed (${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// GET /v1/challenges/:id/messages — shared race chat, oldest-first.
  Future<List<Map<String, dynamic>>> getRaceMessages(String challengeId,
      {int limit = 50}) async {
    final headers = await _headersAuth();
    if (headers.isEmpty) return const [];
    final res = await http
        .get(
          Uri.parse('$v1Base/challenges/$challengeId/messages?limit=$limit'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 22));
    if (res.statusCode != 200) {
      throw Exception('Chat load failed (${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['data'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>();
  }

  /// POST /v1/challenges/:id/messages — send to the shared race chat.
  Future<Map<String, dynamic>> sendRaceMessage(
      String challengeId, String body) async {
    final headers = await _headersAuth();
    if (headers.isEmpty) throw Exception('Not signed in');
    final res = await http
        .post(
          Uri.parse('$v1Base/challenges/$challengeId/messages'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'body': body}),
        )
        .timeout(const Duration(seconds: 22));
    if (res.statusCode != 201) {
      String msg = 'Could not send (${res.statusCode})';
      try {
        final j = jsonDecode(res.body);
        if (j is Map && j['message'] is String) msg = j['message'] as String;
      } catch (_) {}
      throw Exception(msg);
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return (j['data'] as Map<String, dynamic>?) ?? const {};
  }
}
