import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Wave 16 — central wrapper around `FirebaseCrashlytics.recordError` so the
/// previously-silent `catch (_)` sites across the app can now report into the
/// Crashlytics dashboard while remaining 100% safe from raising user-visible
/// errors.
///
/// **Safety contract:**
///  - This function MUST NEVER throw. If Crashlytics is not yet initialised
///    (e.g. unit tests, very early startup) the recordError call is wrapped
///    in its own try/catch and swallowed.
///  - Always non-fatal — errors recorded via this helper continue execution
///    at the catch site.
///  - `reason` follows the convention `<service-name>:<action>` so the
///    Crashlytics console can group related issues, e.g. `auth:refresh-token`,
///    `feed:load-page`, `health:incremental-sync`.
///
/// Use [reportError] for Tier A/B (instrumented). For Tier C (best-effort
/// polish) prefer a simple `debugPrint` at the catch site without calling
/// this helper.
void reportError(
  Object error,
  StackTrace stackTrace, {
  required String reason,
}) {
  debugPrint('[crash-reporter] $reason: $error');
  try {
    // ignore: discarded_futures
    FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      reason: reason,
      fatal: false,
    );
  } catch (_) {
    // Crashlytics may not be initialised (tests, plugin not on platform,
    // bootstrap failed earlier). Never surface that to the caller.
  }
}

/// Same as [reportError] but accepts a callable that produces the stack lazily
/// — useful when the catch site only has `catch (e)` (no `st` captured).
/// Falls back to `StackTrace.current` which is good-enough for grouping.
void reportErrorNoStack(Object error, {required String reason}) {
  reportError(error, StackTrace.current, reason: reason);
}
