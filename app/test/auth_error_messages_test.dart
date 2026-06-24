// Contract tests for the backend-error → user-copy mapping.
//
// The mapping moved from brittle substring-matching on (RO/EN) message text to
// keying on the backend's STABLE error code (`{ error, message, requestId }`).
// These pin: (1) known codes map to curated copy regardless of the message,
// (2) an unknown code falls back to the server message, (3) no code at all
// still works via the legacy heuristics, and (4) the empty-everything case
// yields a sensible generic line.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/l10n/auth_error_messages.dart';
import 'package:zvelt_app/services/http_client.dart';

void main() {
  group('authErrorCopyForCode', () {
    test('known codes map to curated copy', () {
      expect(authErrorCopyForCode('EMAIL_TAKEN'), 'This email is already in use.');
      expect(authErrorCopyForCode('INVALID_CREDENTIALS'), 'Invalid email or password.');
      expect(authErrorCopyForCode('USERNAME_TAKEN'), 'That username is already taken.');
    });

    test('is case-insensitive and trims whitespace', () {
      expect(authErrorCopyForCode('  email_taken '), 'This email is already in use.');
    });

    test('null / empty / unknown → null (caller falls back)', () {
      expect(authErrorCopyForCode(null), isNull);
      expect(authErrorCopyForCode(''), isNull);
      expect(authErrorCopyForCode('SOME_FUTURE_CODE'), isNull);
    });
  });

  group('authErrorToEnglish — code path', () {
    test('code wins over (and ignores) the raw message text', () {
      // A RO message that the old substring matcher would have mis-handled —
      // the code drives the copy instead.
      expect(
        authErrorToEnglish('Acest email este deja folosit', code: 'EMAIL_TAKEN'),
        'This email is already in use.',
      );
      expect(
        authErrorToEnglish('totally unrelated text', code: 'INVALID_CREDENTIALS'),
        'Invalid email or password.',
      );
    });

    test('rate-limit + ai-disabled codes (no message heuristic existed)', () {
      expect(
        authErrorToEnglish('', code: 'RATE_LIMITED'),
        'Too many attempts. Please wait a moment and try again.',
      );
      expect(
        authErrorToEnglish('', code: 'AI_DISABLED'),
        'This feature is temporarily unavailable.',
      );
    });

    test('embedded known code in message is recovered when no code arg', () {
      expect(
        authErrorToEnglish('EMAIL_TAKEN: Acest email este deja folosit'),
        'This email is already in use.',
      );
    });
  });

  group('authErrorToEnglish — fallbacks (behavior preserved)', () {
    test('unknown code falls back to legacy heuristics / server message', () {
      // Unknown code, but RO message still resolves via legacy substring path.
      expect(
        authErrorToEnglish('Email sau parola incorecta', code: 'WEIRD_NEW_CODE'),
        'Invalid email or password.',
      );
    });

    test('legacy substring matching still works with no code', () {
      expect(
        authErrorToEnglish('Acest email este deja folosit'),
        'This email is already in use.',
      );
      expect(authErrorToEnglish('Contul este dezactivat'), 'This account is disabled.');
    });

    test('unknown code + opaque message → message verbatim', () {
      expect(
        authErrorToEnglish('A truly opaque server note', code: 'NOPE'),
        'A truly opaque server note',
      );
    });

    test('empty message + no/unknown code → generic line', () {
      expect(
        authErrorToEnglish('', code: 'NOPE'),
        'Something went wrong. Please try again.',
      );
    });
  });

  group('friendlyLoadError — prefers decoded error code', () {
    test('known errorCode maps straight to curated copy', () {
      expect(
        friendlyLoadError(Exception('HTTP 500'), errorCode: 'RATE_LIMITED'),
        'Too many attempts. Please wait a moment and try again.',
      );
    });

    test('unknown/absent code falls back to existing heuristics', () {
      expect(
        friendlyLoadError(Exception('Stats 503')),
        'Could not load (HTTP 503). Tap retry.',
      );
      expect(
        friendlyLoadError(TimeoutException('request timed out after 45s')),
        'Timed out — the server may be waking up. Tap retry.',
      );
      expect(
        friendlyLoadError(Exception('boom'), errorCode: 'UNKNOWN_X'),
        'Could not load — check your connection.',
      );
    });
  });
}
