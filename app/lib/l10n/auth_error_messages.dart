/// Maps backend auth errors to user-facing English copy.
///
/// The backend returns a stable error CODE (e.g. `EMAIL_TAKEN`,
/// `INVALID_CREDENTIALS`) alongside a localized `message` on every failure
/// (`{ error, message, requestId }`). Matching on the CODE is robust: it
/// survives copy edits and RO↔EN message changes, where the old substring
/// matching ("folosit" / "taken" / "incorect") was brittle.
///
/// Resolution order:
///   1. CODE → curated copy (when the code is known)
///   2. the server-supplied `message` (so unknown codes still say something)
///   3. a generic fallback (when no message is available either)
library;

/// Curated, user-facing copy keyed by the backend's stable error code.
///
/// Keep keys UPPER_SNAKE to match the backend `error` field verbatim. Adding a
/// new backend code only needs a new entry here — no string-sniffing.
const Map<String, String> kAuthErrorCopy = {
  'EMAIL_TAKEN': 'This email is already in use.',
  'USERNAME_TAKEN': 'That username is already taken.',
  'INVALID_CREDENTIALS': 'Invalid email or password.',
  'ACCOUNT_DISABLED': 'This account is disabled.',
  'CURRENT_PASSWORD_INVALID': 'The current password is incorrect.',
  'PASSWORD_NOT_AVAILABLE':
      'This account signs in through an external provider.',
  'INVALID_GOOGLE_TOKEN': 'Google sign-in failed. Try again.',
  'CONFIG_ERROR': 'Google sign-in is not configured.',
  'VALIDATION_ERROR': 'Please check your input.',
  'INVALID_REFRESH_TOKEN': 'Session expired. Please sign in again.',
  'TOKEN_REUSE_DETECTED': 'Session expired. Please sign in again.',
  'RATE_LIMITED': 'Too many attempts. Please wait a moment and try again.',
  'AI_DISABLED': 'This feature is temporarily unavailable.',
  'NOT_FOUND': 'Not found.',
  'INTERNAL_ERROR': 'Something went wrong. Please try again.',
};

/// Resolves backend auth copy from a stable error [code] when known.
///
/// Returns `null` when the code is absent or unrecognized so callers can fall
/// back to the server message. Lookup is case-insensitive and tolerant of
/// surrounding whitespace.
String? authErrorCopyForCode(String? code) {
  if (code == null) return null;
  final key = code.trim().toUpperCase();
  if (key.isEmpty) return null;
  return kAuthErrorCopy[key];
}

/// Maps a backend auth error to user-facing English.
///
/// Prefers the stable backend [code] (e.g. `EMAIL_TAKEN`) when supplied. When
/// no code is given, it attempts to recover one embedded in [message] (some
/// callers only have the raw exception text), then falls back to the legacy
/// substring heuristics, and finally returns [message] verbatim.
///
/// The original single-argument signature is preserved, so existing callers
/// keep working; [code] is an additive, optional parameter.
String authErrorToEnglish(String message, {String? code}) {
  // 1. Stable code path — robust to message copy/locale changes.
  final byCode = authErrorCopyForCode(code) ??
      authErrorCopyForCode(_extractCodeToken(message));
  if (byCode != null) return byCode;

  // 2. Legacy substring heuristics — kept so behavior is preserved for callers
  //    that still only pass a raw (possibly RO) message with no code.
  final m = message.toLowerCase();
  if (m.contains('email') &&
      (m.contains('folosit') || m.contains('taken') || m.contains('already'))) {
    return 'This email is already in use.';
  }
  if (m.contains('incorect') || m.contains('invalid') && m.contains('credential')) {
    return 'Invalid email or password.';
  }
  if (m.contains('parola') || m.contains('password')) {
    return 'Invalid email or password.';
  }
  if (m.contains('dezactivat') || m.contains('disabled')) {
    return 'This account is disabled.';
  }
  if (m.contains('invalid') && m.contains('google')) {
    return 'Google sign-in failed. Try again.';
  }
  if (m.contains('config') && m.contains('google')) {
    return 'Google sign-in is not configured.';
  }
  if (m.contains('invalide') || m.contains('validation')) {
    return 'Please check your input.';
  }
  if (m.contains('refresh') && m.contains('invalid')) {
    return 'Session expired. Please sign in again.';
  }

  // 3. Generic fallback — surface the server message if we have one.
  final trimmed = message.trim();
  return trimmed.isEmpty ? 'Something went wrong. Please try again.' : message;
}

/// Best-effort extraction of an UPPER_SNAKE error code embedded in a free-form
/// message (e.g. `"EMAIL_TAKEN: Acest email este deja folosit"`). Only matches
/// a known code so arbitrary all-caps words in a message aren't mistaken for a
/// code; returns `null` otherwise.
String? _extractCodeToken(String message) {
  for (final match in RegExp(r'[A-Z][A-Z0-9_]{2,}').allMatches(message)) {
    final token = match.group(0)!;
    if (kAuthErrorCopy.containsKey(token)) return token;
  }
  return null;
}
