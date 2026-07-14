import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../config/api_config.dart' show v1Base;
import 'auth_service.dart';

/// Result of a successful Strava connection (or status check).
///
/// `athleteId` is the Strava athlete id stored on the backend.
/// `username` is optional — Strava may return null for users who never set one.
/// `connectedAt` is when the backend recorded the connection (server time).
class StravaConnection {
  const StravaConnection({
    required this.athleteId,
    required this.connectedAt,
    this.username,
  });

  final String athleteId;
  final String? username;
  final DateTime connectedAt;

  factory StravaConnection.fromJson(Map<String, dynamic> j) {
    return StravaConnection(
      athleteId: (j['athleteId'] ?? j['athlete_id'] ?? '').toString(),
      username: j['username'] as String?,
      connectedAt: DateTime.tryParse(
            (j['connectedAt'] ?? j['connected_at'] ?? '') as String? ?? '',
          ) ??
          DateTime.now().toUtc(),
    );
  }
}

/// Thrown by [IntegrationsService] for any non-2xx response or transport error.
class IntegrationsException implements Exception {
  IntegrationsException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'IntegrationsException(${statusCode ?? '-'}): $message';
}

/// Client for the Integrations Service (Strava, etc.).
///
/// Note: the OAuth callback (i.e. handling the `code` returned by Strava) is
/// out of scope for this client. The redirect URI points at a webpage that
/// performs the exchange against the backend; the mobile client only kicks the
/// flow off and later checks status / disconnects.
class IntegrationsService {
  IntegrationsService({AuthService? auth, http.Client? client})
      : _auth = auth ?? AuthService(),
        _client = client ?? http.Client();

  final AuthService _auth;
  final http.Client _client;

  /// Token exchange on Strava's side can be slow; keep a generous timeout.
  static const Duration _exchangeTimeout = Duration(seconds: 20);
  static const Duration _defaultTimeout = Duration(seconds: 12);

  Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _auth.getAccessToken();
    if (token == null) {
      throw IntegrationsException('Not signed in', 401);
    }
    return {
      'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  /// Exchange a Strava authorization `code` for backend-stored tokens.
  ///
  /// Callback handled by web flow → backend; this client doesn't handle the
  /// redirect directly. This method exists so a hosted callback page (or a
  /// deep-link handler added later) can hand the `code` off to the backend.
  Future<StravaConnection> exchangeStravaCode(String code) async {
    if (code.trim().isEmpty) {
      throw IntegrationsException('Authorization code is empty', 400);
    }
    final uri = Uri.parse('$v1Base/integrations/strava/exchange');
    try {
      final res = await _client
          .post(
            uri,
            headers: await _headers(),
            body: jsonEncode({'code': code}),
          )
          .timeout(_exchangeTimeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw IntegrationsException(
          _extractMessage(res.body) ?? 'Strava exchange failed',
          res.statusCode,
        );
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final payload = (data['connection'] as Map<String, dynamic>?) ?? data;
      return StravaConnection.fromJson(payload);
    } on IntegrationsException {
      rethrow;
    } on TimeoutException {
      throw IntegrationsException('Strava exchange timed out', null);
    } catch (e) {
      throw IntegrationsException('Network error: $e', null);
    }
  }

  /// Revoke the server-side Strava connection. Returns `true` on success.
  Future<bool> disconnectStrava() async {
    final uri = Uri.parse('$v1Base/integrations/strava');
    try {
      final res = await _client
          .delete(uri, headers: await _headers(json: false))
          .timeout(_defaultTimeout);
      if (res.statusCode == 200 ||
          res.statusCode == 202 ||
          res.statusCode == 204) {
        return true;
      }
      throw IntegrationsException(
        _extractMessage(res.body) ?? 'Disconnect failed',
        res.statusCode,
      );
    } on IntegrationsException {
      rethrow;
    } on TimeoutException {
      throw IntegrationsException('Disconnect timed out', null);
    } catch (e) {
      throw IntegrationsException('Network error: $e', null);
    }
  }

  /// Current Strava connection status, or `null` if not connected.
  ///
  /// A 404 from the backend is interpreted as "not connected" (returns null).
  Future<StravaConnection?> getStravaStatus() async {
    final uri = Uri.parse('$v1Base/integrations/strava/status');
    try {
      final res = await _client
          .get(uri, headers: await _headers(json: false))
          .timeout(_defaultTimeout);
      if (res.statusCode == 404) return null;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final connected = data['connected'];
        if (connected == false) return null;
        final payload =
            (data['connection'] as Map<String, dynamic>?) ?? data;
        if (payload.isEmpty ||
            (payload['athleteId'] == null &&
                payload['athlete_id'] == null)) {
          return null;
        }
        return StravaConnection.fromJson(payload);
      }
      throw IntegrationsException(
        _extractMessage(res.body) ?? 'Status check failed',
        res.statusCode,
      );
    } on IntegrationsException {
      rethrow;
    } on TimeoutException {
      throw IntegrationsException('Status check timed out', null);
    } catch (e) {
      throw IntegrationsException('Network error: $e', null);
    }
  }

  /// GET /v1/integrations — the connected provider ids plus whether the
  /// wearable cloud aggregator (Terra) is configured server-side.
  ///
  /// Same payload the Integrations screen consumes; used by the profile
  /// "Connect a device" sheet to render real Connect/Connected pill states.
  Future<({Set<String> connected, bool aggregatorConfigured})>
      listIntegrations() async {
    final uri = Uri.parse('$v1Base/integrations');
    try {
      final res = await _client
          .get(uri, headers: await _headers(json: false))
          .timeout(_defaultTimeout);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw IntegrationsException(
          _extractMessage(res.body) ?? 'Failed to load integrations',
          res.statusCode,
        );
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['integrations'] as List<dynamic>? ?? const [];
      // Parse defensively — a single malformed row must not abort the map.
      final connected = <String>{};
      for (final e in list) {
        if (e is! Map) continue;
        final provider = e['provider'] as String?;
        if (provider != null) connected.add(provider);
      }
      final agg = data['aggregator'];
      return (
        connected: connected,
        aggregatorConfigured: agg is Map && agg['configured'] == true,
      );
    } on IntegrationsException {
      rethrow;
    } on TimeoutException {
      throw IntegrationsException('Integrations load timed out', null);
    } catch (e) {
      throw IntegrationsException('Network error: $e', null);
    }
  }

  String? _extractMessage(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) {
        return (v['message'] ?? v['error']) as String?;
      }
    } catch (e) {
      debugPrint('[IntegrationsService._extractMessage] body decode best-effort skip: $e');
    }
    return null;
  }
}
