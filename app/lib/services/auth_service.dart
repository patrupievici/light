import 'dart:async';
import 'dart:convert';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/api_config.dart';
import '_crash_reporter.dart';
import 'local_account_data_wiper.dart';

// User-facing copy — this string lands verbatim in LoginScreen's error box.
// It used to be a Romanian developer hint (with a literal `flutter run`
// command) shown to any production user with bad Wi-Fi. Keep dev details in
// the debug log only.
String _authNetworkHint() {
  debugPrint('[AuthService] cannot reach server at $apiBaseUrl '
      '(dev hint: start the backend, or run with '
      '--dart-define=API_BASE_URL=http://<pc-ip>:3000 on a real device)');
  return "Can't reach the server. Check your internet connection and try again.";
}

bool _looksLikeNetworkFailure(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('connection refused') ||
      s.contains('connection timed out') ||
      s.contains('timeoutexception') ||
      s.contains('network is unreachable') ||
      s.contains('clientexception') ||
      s.contains('connection reset') ||
      s.contains('networkerror');
}

Map<String, dynamic>? _tryDecodeJsonObject(String body) {
  try {
    final v = jsonDecode(body);
    if (v is Map<String, dynamic>) return v;
    return null;
  } catch (e) {
    debugPrint('[AuthService] _tryDecodeJsonObject best-effort skip: $e');
    return null;
  }
}

class AuthService {
  static const _keyAccessToken = 'zvelt_access_token';
  static const _keyRefreshToken = 'zvelt_refresh_token';

  /// Seconds before JWT exp to treat as expired (proactive refresh).
  static const _expirySkewSeconds = 90;

  /// Fără timeout, `http.post` poate bloca minute dacă backend-ul nu răspunde.
  /// Render free tier are cold start de până la ~60s după 15 min idle;
  /// 75s dă marjă pentru worst case + DNS + handshake pe rețele lente.
  static const Duration httpTimeout = Duration(seconds: 75);

  /// Wave 14 — Keychain (iOS) / EncryptedSharedPreferences (Android).
  /// `first_unlock_this_device`: tokens unavailable until first unlock
  /// after boot AND never sync via iCloud — correct posture for auth.
  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Logs to Crashlytics + debugPrint without ever throwing.
  void _reportTokenIoError(Object e, StackTrace st) {
    debugPrint('[AuthService] SecureStorage failure: $e');
    try {
      FirebaseCrashlytics.instance
          .recordError(e, st, reason: 'auth-token-io', fatal: false);
    } catch (_) {
      // Crashlytics may not be initialised in tests — swallow.
    }
  }

  /// Reads from SecureStorage first; on miss, falls back to SharedPreferences
  /// (legacy storage). Found legacy values are promoted to SecureStorage and
  /// removed from SharedPreferences — one-time migration on first access.
  /// On SecureStorage I/O failure: falls back to SharedPreferences for this
  /// session so the user isn't locked out, but next call will retry secure.
  Future<String?> _readSecureWithMigration(String key) async {
    final prefs = await SharedPreferences.getInstance();
    // Always run the forge_* → zvelt_* migration first so even very old
    // tokens get a chance to land in SharedPreferences before we promote
    // them into SecureStorage below.
    await _migrateForgeAuthKeys(prefs);

    try {
      final secure = await _secureStorage.read(key: key);
      if (secure != null && secure.isNotEmpty) return secure;

      final legacy = prefs.getString(key);
      if (legacy != null && legacy.isNotEmpty) {
        // Promote legacy plain-text token into SecureStorage and wipe the
        // plain copy. Best-effort: if the write fails we keep the legacy
        // value around so the user stays signed in.
        try {
          await _secureStorage.write(key: key, value: legacy);
          await prefs.remove(key);
        } catch (e, st) {
          _reportTokenIoError(e, st);
        }
        return legacy;
      }
      return null;
    } catch (e, st) {
      _reportTokenIoError(e, st);
      // Fallback so the current session keeps working.
      return prefs.getString(key);
    }
  }

  Future<String?> _getAccessToken() async {
    return _readSecureWithMigration(_keyAccessToken);
  }

  Future<String?> _getRefreshToken() async {
    return _readSecureWithMigration(_keyRefreshToken);
  }

  /// Renaming app prefs `forge_*` → `zvelt_*`; keeps login on dev devices.
  /// Runs against SharedPreferences only — secure migration happens after.
  Future<void> _migrateForgeAuthKeys(SharedPreferences prefs) async {
    const legacyAccess = 'forge_access_token';
    const legacyRefresh = 'forge_refresh_token';
    final curA = prefs.getString(_keyAccessToken);
    final curR = prefs.getString(_keyRefreshToken);
    final legA = prefs.getString(legacyAccess);
    final legR = prefs.getString(legacyRefresh);

    if ((curA == null || curA.isEmpty) && legA != null && legA.isNotEmpty) {
      await prefs.setString(_keyAccessToken, legA);
    }
    if ((curR == null || curR.isEmpty) && legR != null && legR.isNotEmpty) {
      await prefs.setString(_keyRefreshToken, legR);
    }
    await prefs.remove(legacyAccess);
    await prefs.remove(legacyRefresh);
  }

  Future<void> _saveTokens(
    String accessToken,
    String refreshToken, {
    bool preserveMediaCache = false,
  }) async {
    try {
      await _secureStorage.write(key: _keyAccessToken, value: accessToken);
      await _secureStorage.write(key: _keyRefreshToken, value: refreshToken);
      // Defense in depth: clear any leftover plain copies from older builds.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyAccessToken);
      await prefs.remove(_keyRefreshToken);
    } catch (e, st) {
      _reportTokenIoError(e, st);
      // SecureStorage unavailable — degrade to SharedPreferences so login
      // still completes. Next read will retry the secure promotion.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAccessToken, accessToken);
      await prefs.setString(_keyRefreshToken, refreshToken);
    }

    // A new login can replace an account without first calling logout (for
    // example after a stale login screen is resumed). Protected images must
    // not remain visible from the previous session in Flutter's memory cache
    // or the disk cache. Token refreshes keep the same identity and skip this.
    if (!preserveMediaCache) {
      try {
        await LocalAccountDataWiper.clearMediaCaches();
      } catch (e, st) {
        reportError(e, st, reason: 'auth:clear-media-cache-on-login');
      }
    }
  }

  Future<void> _clearTokens() async {
    // Defense in depth: wipe BOTH storages regardless of which one currently
    // holds the token.
    try {
      await _secureStorage.delete(key: _keyAccessToken);
      await _secureStorage.delete(key: _keyRefreshToken);
    } catch (e, st) {
      _reportTokenIoError(e, st);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove('forge_access_token');
    await prefs.remove('forge_refresh_token');
  }

  /// True if JWT is missing `exp` or already past (with skew).
  bool _isAccessTokenExpiredOrSoon(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return true;
    try {
      final payloadBytes = base64Url.decode(base64Url.normalize(parts[1]));
      final payload =
          jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
      final exp = payload['exp'];
      // A JWT with no `exp` claim is malformed for our purposes — we treat
      // it as expired so the caller refreshes. The old behavior (returning
      // false) silently accepted such tokens, masking server bugs and
      // creating tokens that lived forever.
      if (exp == null) return true;
      final expSec = exp is num ? exp.toInt() : int.tryParse(exp.toString());
      if (expSec == null) return true;
      final expiry =
          DateTime.fromMillisecondsSinceEpoch(expSec * 1000, isUtc: true);
      final now = DateTime.now().toUtc();
      return !now.isBefore(
          expiry.subtract(const Duration(seconds: _expirySkewSeconds)));
    } catch (e) {
      debugPrint('[AuthService] _isAccessTokenExpiredOrSoon parse failed: $e');
      return true;
    }
  }

  /// `userId` din JWT salvat — fără rețea (merge și dacă access-ul e expirat).
  Future<String?> getStoredUserId() async {
    final access = await _getAccessToken();
    if (access == null || access.isEmpty) return null;
    return _decodeUserIdFromJwt(access);
  }

  String? _decodeUserIdFromJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payloadBytes = base64Url.decode(base64Url.normalize(parts[1]));
      final payload =
          jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
      return payload['userId'] as String?;
    } catch (e) {
      debugPrint('[AuthService] _decodeUserIdFromJwt parse failed: $e');
      return null;
    }
  }

  /// POST /v1/auth/refresh — returns new access token or null.
  Future<String?> _refreshAccessToken() async {
    final refresh = await _getRefreshToken();
    if (refresh == null || refresh.isEmpty) return null;

    try {
      final res = await http
          .post(
            Uri.parse('$v1Base/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refresh}),
          )
          .timeout(httpTimeout);
      if (res.statusCode != 200) {
        // Wipe the session ONLY when the server explicitly rejected the
        // refresh token (401/403). A 5xx/429 (e.g. Render free-tier cold
        // start, documented elsewhere in this file) means the token is
        // still valid — clearing it here permanently logged users out on
        // transient backend hiccups.
        if (res.statusCode == 401 || res.statusCode == 403) {
          await _clearTokens();
        }
        return null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final accessToken = data['accessToken'] as String?;
      final newRefresh = data['refreshToken'] as String?;
      if (accessToken != null && newRefresh != null) {
        await _saveTokens(
          accessToken,
          newRefresh,
          preserveMediaCache: true,
        );
        return accessToken;
      }
      // Malformed 200 — a server bug, not a revoked session. Keep tokens.
      return null;
    } catch (e, st) {
      reportError(e, st, reason: 'auth:refresh-token');
      return null;
    }
  }

  /// Shared in-flight refresh. STATIC so the many `AuthService()` instances
  /// created across services (ProfileService, SocialFeedService, …) all share
  /// ONE refresh round-trip. Refresh tokens are single-use server-side; if two
  /// callers POST /auth/refresh concurrently with the SAME token, the backend
  /// flags TOKEN_REUSE_DETECTED and wipes every session — that was the
  /// cold-start logout + Feed-401 bug. De-duping collapses the storm to a
  /// single request that all callers await.
  static Future<String?>? _inflightRefresh;

  Future<String?> _refreshAccessTokenDeduped() {
    final existing = _inflightRefresh;
    if (existing != null) return existing;
    final fut = _refreshAccessToken().whenComplete(() {
      _inflightRefresh = null;
    });
    _inflightRefresh = fut;
    return fut;
  }

  /// Logged in: valid access token, or refresh token that can be verified.
  /// If only a refresh token exists (access expired), attempts a refresh to verify
  /// the refresh token is still valid server-side (catches revoked sessions).
  ///
  /// Offline-first: a refresh that fails for NETWORK reasons (airplane mode,
  /// basement gym, backend 5xx) keeps the user signed in. The session is
  /// only treated as dead when the server explicitly rejects the refresh
  /// token — `_refreshAccessToken` clears the tokens in exactly that case,
  /// so "refresh token still present after a failed refresh" == transient.
  Future<bool> hasValidToken() async {
    final access = await _getAccessToken();
    if (access != null &&
        access.isNotEmpty &&
        !_isAccessTokenExpiredOrSoon(access)) {
      return true;
    }
    // Access expired or missing — try refresh to verify session is still active
    final refresh = await _getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    final refreshed = await _refreshAccessTokenDeduped();
    if (refreshed != null) return true;
    // Refresh failed: if the refresh token survived, the failure was
    // transient (network/5xx) — optimistic offline session, don't lock the
    // user out of workout tracking.
    final stillThere = await _getRefreshToken();
    return stillThere != null && stillThere.isNotEmpty;
  }

  /// Returns a usable Bearer token; refreshes automatically before expiry.
  ///
  /// On refresh failure we return `null` instead of falling back to the
  /// known-expired token. Returning the expired token caused a 401 storm:
  /// every service call would attach it, hit 401, and the caller couldn't
  /// distinguish "no session" from "session expired and refresh broke" —
  /// the user saw confusing error toasts everywhere. Null gives callers
  /// the unambiguous "not signed in" branch they already check for.
  Future<String?> getAccessToken() async {
    final access = await _getAccessToken();
    if (access != null &&
        access.isNotEmpty &&
        !_isAccessTokenExpiredOrSoon(access)) {
      return access;
    }
    return _refreshAccessTokenDeduped();
  }

  /// Offline-safe: decode the uid straight from the stored JWT — the claim
  /// doesn't change when the access token expires, and cache keys / "is this
  /// mine" checks must not flip to `anonymous` in airplane mode (that made
  /// logged nutrition/cardio days look empty after an offline restart and
  /// stranded new offline logs under `anonymous_*` keys). Only falls back to
  /// the refreshing path when no token is stored at all. Tokens are cleared
  /// on logout / rejected refresh, so a stored token always identifies the
  /// current user. Never use this for auth decisions — only for namespacing.
  Future<String?> getCurrentUserId() async {
    final stored = await getStoredUserId();
    if (stored != null && stored.isNotEmpty) return stored;
    final token = await getAccessToken();
    if (token == null || token.isEmpty) return null;
    return _decodeUserIdFromJwt(token);
  }

  /// Shared skeleton for the auth POST endpoints (login/signup/google):
  /// POST + JSON header + timeout, network-hint mapping, status check,
  /// token save, returns the decoded response body.
  ///
  /// Callers differ only in [path], [body], the expected [okStatus]
  /// (200 vs 201), and the [failLabel] used in the non-OK error message.
  Future<Map<String, dynamic>?> _authPost(
    String path,
    Map<String, dynamic> body, {
    int okStatus = 200,
    required String failLabel,
  }) async {
    final uri = Uri.parse('$v1Base$path');
    try {
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(httpTimeout);
      if (res.statusCode != okStatus) {
        final decoded = _tryDecodeJsonObject(res.body);
        throw Exception(
            decoded?['message'] ?? '$failLabel (${res.statusCode})');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final accessToken = data['accessToken'] as String?;
      final refreshToken = data['refreshToken'] as String?;
      if (accessToken != null && refreshToken != null) {
        await _saveTokens(accessToken, refreshToken);
      }
      return data;
    } on FormatException {
      throw Exception(_authNetworkHint());
    } catch (e) {
      if (_looksLikeNetworkFailure(e)) {
        throw Exception(_authNetworkHint());
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> login(String email, String password) async {
    return _authPost(
      '/auth/login',
      {'email': email, 'password': password},
      failLabel: 'Login failed',
    );
  }

  Future<Map<String, dynamic>?> signup({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
      if (displayName != null && displayName.isNotEmpty)
        'displayName': displayName,
    };
    return _authPost(
      '/auth/signup',
      body,
      okStatus: 201,
      failLabel: 'Signup failed',
    );
  }

  Future<Map<String, dynamic>?> loginWithGoogle(String idToken) async {
    return _authPost(
      '/auth/google',
      {'idToken': idToken},
      failLabel: 'Google login failed',
    );
  }

  /// POST /v1/auth/password/forgot — asks the server to email a 6-digit reset
  /// code. The server ALWAYS answers a generic 200 (never reveals whether the
  /// email exists), so this only throws on network/rate-limit/server errors.
  Future<void> requestPasswordReset(String email) async {
    await _authPost(
      '/auth/password/forgot',
      {'email': email},
      failLabel: 'Could not request a reset code',
    );
  }

  /// POST /v1/auth/password/reset — sets a new password using the emailed code.
  ///
  /// Throws [PasswordResetException] with `invalidCode == true` when the
  /// server rejects the code (wrong or expired) so the UI can show an inline
  /// field error, and with `invalidCode == false` for every other failure
  /// (network → retry, rate limit, server error).
  Future<void> resetPassword(
      String email, String code, String newPassword) async {
    final uri = Uri.parse('$v1Base/auth/password/reset');
    http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'code': code,
              'new_password': newPassword,
            }),
          )
          .timeout(httpTimeout);
    } catch (e) {
      if (_looksLikeNetworkFailure(e)) {
        throw PasswordResetException(_authNetworkHint());
      }
      throw PasswordResetException('Network error: $e');
    }
    if (res.statusCode == 200) return;
    final decoded = _tryDecodeJsonObject(res.body);
    if (decoded?['error'] == 'INVALID_CODE') {
      throw PasswordResetException(
        'That code is incorrect or has expired. Check the email or request a new code.',
        invalidCode: true,
      );
    }
    throw PasswordResetException(
      decoded?['message']?.toString() ??
          'Could not reset the password (${res.statusCode}). Please try again.',
    );
  }

  /// SharedPreferences flag marking the current session as an anonymous "guest"
  /// (no real email/Google identity), so the UI can later offer to save it.
  static const String _keyIsGuest = 'zvelt_is_guest';

  /// Creates a throwaway "guest" account so the user can enter the app WITHOUT a
  /// login screen. Generates random credentials and signs up; the regular
  /// [signup] path persists the returned tokens, so afterwards [getAccessToken]
  /// works normally. Returns true on success, false on failure (e.g. offline) —
  /// the caller may still let the user continue offline.
  Future<bool> continueAsGuest({String displayName = 'Athlete'}) async {
    final id = const Uuid().v4().replaceAll('-', '');
    final email = 'guest_$id@guest.zvelt.app';
    // Backend only enforces length 8–128; this is ~34 chars with letters+digits.
    final password = 'Gx${id}9';
    final res = await signup(
        email: email, password: password, displayName: displayName);
    if (res == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyIsGuest, true);
    } catch (_) {/* flag is best-effort */}
    return true;
  }

  /// Whether the active session is an anonymous guest account.
  Future<bool> isGuest() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyIsGuest) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    // Nu apela getAccessToken() — poate declanșa refresh blocant fără server.
    final token = await _getAccessToken();
    // Local-first: the user is signed out the moment the tokens are wiped.
    // Previously this awaited the server POST first, so on a slow network
    // the first "Log out" tap looked like it did nothing (up to httpTimeout).
    await _clearTokens();
    try {
      await LocalAccountDataWiper.clearMediaCaches();
    } catch (e, st) {
      reportError(e, st, reason: 'auth:logout-media-cache');
    }
    // Best-effort server-side revoke — fire-and-forget, off the critical path.
    final uri = Uri.parse('$v1Base/auth/logout');
    http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
        )
        .timeout(httpTimeout)
        .then<void>((_) {})
        .catchError((Object e, StackTrace st) {
          reportError(e, st, reason: 'auth:logout-server');
        })
        .ignore();
  }

  /// GDPR / Play Store policy: user-initiated permanent account deletion.
  ///
  /// Calls `DELETE /v1/me/account` with a confirmation token. Server is
  /// expected to hard-delete the account and return 204 No Content on success
  /// (or a structured 4xx/5xx error on failure).
  ///
  /// On success, ALL local credentials, SharedPreferences and cached DBs
  /// are cleared client-side regardless of network outcome — the user wants out.
  ///
  /// Throws [AccountDeletionException] on backend failure so the UI can
  /// surface a real error (instead of silently signing the user out).
  Future<void> deleteAccount({required String confirmation}) async {
    if (confirmation.trim().toUpperCase() != 'DELETE') {
      throw AccountDeletionException('Confirmation text does not match.');
    }
    final token = await getAccessToken();
    if (token == null || token.isEmpty) {
      throw AccountDeletionException('You are not signed in.');
    }
    final uri = Uri.parse('$v1Base/me/account');
    http.Response resp;
    try {
      resp = await http
          .delete(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            // Carry the typed confirmation so the server can enforce it (was
            // validated client-side only; the server ignored it entirely).
            body: jsonEncode({'confirm': confirmation.trim()}),
          )
          .timeout(httpTimeout);
    } catch (e) {
      if (_looksLikeNetworkFailure(e)) {
        throw AccountDeletionException(_authNetworkHint());
      }
      throw AccountDeletionException('Network error: $e');
    }

    // Accept 200, 202 (accepted, deletion queued), 204 (no content).
    final ok = resp.statusCode == 200 ||
        resp.statusCode == 202 ||
        resp.statusCode == 204;
    if (!ok) {
      final body = _tryDecodeJsonObject(resp.body);
      final msg = body?['message']?.toString() ??
          body?['error']?.toString() ??
          'Server returned HTTP ${resp.statusCode}.';
      throw AccountDeletionException(msg);
    }

    // Wipe ALL local state. The user is gone. Defense in depth: clear
    // SecureStorage tokens BEFORE the SharedPreferences nuke (the latter
    // doesn't touch Keychain/EncryptedSharedPreferences on its own).
    await _clearTokens();
    try {
      await _secureStorage.deleteAll();
    } catch (e, st) {
      _reportTokenIoError(e, st);
    }
    final wipeResult = await LocalAccountDataWiper.instance.wipe();
    if (!wipeResult.completed) {
      debugPrint(
        '[AuthService] account erasure local cleanup incomplete: '
        '${wipeResult.failedSteps.join(', ')}',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}

class AccountDeletionException implements Exception {
  AccountDeletionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Typed failure for [AuthService.resetPassword]. `invalidCode` distinguishes
/// "the 6-digit code was rejected" (inline field error) from transport/server
/// failures (banner + retry).
class PasswordResetException implements Exception {
  PasswordResetException(this.message, {this.invalidCode = false});
  final String message;
  final bool invalidCode;
  @override
  String toString() => message;
}
