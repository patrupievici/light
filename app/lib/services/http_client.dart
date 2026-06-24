import 'dart:async';

import 'package:http/http.dart' as http;

import '../l10n/auth_error_messages.dart';
import 'auth_service.dart';

/// Shared HTTP timeout constant used by all services.
/// Bumped 15s → 45s to survive Render free-tier cold starts (15-min idle
/// → ~30-60s wake-up). Normal warm requests still return in <300ms p95;
/// the extra ceiling only matters when the dyno was sleeping.
const Duration kHttpTimeout = Duration(seconds: 45);

/// Longer timeout for AI endpoints (can take 30-60 seconds for complex generation)
const Duration kAiHttpTimeout = Duration(seconds: 90);

/// Weekly nutrition plan triggers DeepSeek + DB; 15–60s is often insufficient on mobile networks.
const Duration kNutritionWeeklyPlanGenerateTimeout = Duration(seconds: 150);

/// Convenience extension: `.withTimeout()` on `Future<http.Response>`.
///
/// Usage:
/// ```dart
/// final res = await http.get(uri, headers: headers).withTimeout();
/// ```
extension TimeoutResponse on Future<http.Response> {
  Future<http.Response> withTimeout([Duration timeout = kHttpTimeout]) {
    return this.timeout(timeout, onTimeout: () {
      throw TimeoutException('HTTP request timed out after ${timeout.inSeconds}s');
    });
  }
  
  /// Extended timeout for AI/ML operations
  Future<http.Response> withAiTimeout([Duration timeout = kAiHttpTimeout]) {
    return this.timeout(timeout, onTimeout: () {
      throw TimeoutException('AI request timed out after ${timeout.inSeconds}s');
    });
  }
}

/// Maps a thrown load error to a short, user-facing message that still names
/// the real cause — so a failure screen says *why* (HTTP 500, session expired,
/// timed out) instead of a generic "check your connection". Services throw
/// `Exception('Stats <code>')` / `TimeoutException('... timed out ...')`, so we
/// recover the signal from the message without needing typed catches.
///
/// When the caller has already decoded the backend's stable error [errorCode]
/// (the `error` field of `{ error, message, requestId }`), it is preferred over
/// any heuristics: a known code maps straight to curated copy. This is the same
/// code→copy table used for auth, so backend failures read consistently.
/// [errorCode] is optional and additive, so existing callers are unaffected.
String friendlyLoadError(Object e, {String? errorCode}) {
  // Prefer an explicitly-decoded backend error code when it maps to copy.
  final byCode = authErrorCopyForCode(errorCode);
  if (byCode != null) return byCode;

  final msg = e.toString().replaceFirst('Exception: ', '');
  if (msg.contains('timed out')) {
    return 'Timed out — the server may be waking up. Tap retry.';
  }
  if (msg.contains('Not signed in') || msg.contains('401')) {
    return 'Your session expired. Sign out and back in.';
  }
  final code = RegExp(r'\b(4\d\d|5\d\d)\b').firstMatch(msg)?.group(1);
  if (code != null) return 'Could not load (HTTP $code). Tap retry.';
  return 'Could not load — check your connection.';
}

/// Standard authenticated JSON headers for backend API calls.
///
/// Throws when no access token is available — caller (a service) decides how
/// to surface that. Use this everywhere instead of hand-rolling the same
/// `{'Authorization': 'Bearer $token'}` map per service so:
///   • Content-Type and Accept stay consistent
///   • Adding a new header (e.g. X-Client-Version) needs one edit, not 20
///   • The "Not signed in" failure mode is uniform
///
/// Usage:
/// ```dart
/// final res = await http.post(uri, headers: await authedJsonHeaders(), body: jsonEncode(body)).withTimeout();
/// ```
Future<Map<String, String>> authedJsonHeaders({AuthService? auth}) async {
  final token = await (auth ?? AuthService()).getAccessToken();
  if (token == null) throw Exception('Not signed in');
  return {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
  };
}

/// Same as [authedJsonHeaders] but skips the body content-type when you're
/// only doing a GET — some APIs reject Content-Type on GET. Kept separate so
/// the GET-only callers don't need to think about it.
Future<Map<String, String>> authedReadHeaders({AuthService? auth}) async {
  final token = await (auth ?? AuthService()).getAccessToken();
  if (token == null) throw Exception('Not signed in');
  return {
    'Accept': 'application/json',
    'Authorization': 'Bearer $token',
  };
}
