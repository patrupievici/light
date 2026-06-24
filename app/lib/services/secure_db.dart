import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Wave 15 — central helper for opening SQLCipher-encrypted SQLite DBs.
///
/// Background: prior to Wave 15 every local DB (health imports, journal,
/// photo progress, rest intervals, GPS tracks, workout cache) was a plain
/// SQLite file in the app sandbox. On a rooted/jailbroken device — or via
/// `adb backup` on debug builds — those files are world-readable, leaking
/// health data, journal entries, and photo paths.
///
/// V1.0 strategy (pre-launch, no production users):
///   1. Generate a 32-byte cryptographic random passphrase on first run,
///      base64-encode it, persist in [FlutterSecureStorage] (Keychain on
///      iOS / EncryptedSharedPreferences on Android, same posture as auth
///      tokens — see Wave 14 `AuthService`).
///   2. Open every DB with that passphrase via `sqflite_sqlcipher`.
///   3. The first time this code runs on a device that had an OLD
///      unencrypted DB on disk (from a prior debug install), wipe the
///      known-DB files in `getDatabasesPath()` and let SQLCipher create
///      fresh encrypted ones. This is acceptable because all current DBs
///      are local cache / unsynced UX state — no production data at risk.
///
/// Failure modes:
/// - Open throws (DB corrupt / wrong passphrase from a partially-wiped
///   state): caller calls [openEncryptedOrRecreate] which deletes the
///   file and tries again.
/// - SecureStorage drops the passphrase (rare — full keystore reset):
///   on first DB open we detect "could not decrypt" and recreate. Logged
///   to Crashlytics so we see it in the field.
class SecureDb {
  SecureDb._();
  static final SecureDb instance = SecureDb._();

  /// SecureStorage key. Bumped to `_v1` so we can rotate later without
  /// confusion if we ever need a second passphrase.
  static const String _kPassphraseKey = 'db_passphrase_v1';

  /// SharedPreferences flag — `true` once we've run the one-time wipe of
  /// pre-Wave-15 unencrypted DB files. Stored in plain prefs (not a secret).
  static const String _kInitFlagKey = 'secure_db_v1_init';

  /// Canonical list of every DB filename the app has ever opened. If you
  /// add a new DB, list it here so a fresh-from-old-install device wipes
  /// the unencrypted copy before SQLCipher opens an encrypted one.
  static const List<String> kKnownDbNames = <String>[
    'zvelt_health_records.db',
    'zvelt_journal.db',
    'zvelt_photo_progress.db',
    'zvelt_race_chat.db',
    'zvelt_report_outbox.db',
    'zvelt_rest_intervals.db',
    'zvelt_stories.db',
    'zvelt_tracking.db',
  ];

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      // Same posture as auth tokens (Wave 14): not available until after
      // first device unlock following boot, never iCloud-synced.
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Cache opened handles so multiple services calling [openEncrypted]
  /// with the same `dbName` reuse the connection.
  final Map<String, Database> _openDbs = <String, Database>{};

  String? _cachedPassphrase;
  bool _wipeRan = false;

  /// Read or create the master DB passphrase.
  Future<String> _getOrCreatePassphrase() async {
    if (_cachedPassphrase != null) return _cachedPassphrase!;
    try {
      final existing = await _secureStorage.read(key: _kPassphraseKey);
      if (existing != null && existing.isNotEmpty) {
        _cachedPassphrase = existing;
        return existing;
      }
    } catch (e, st) {
      // SecureStorage I/O can transiently fail on Android in low-memory
      // situations — fall through and generate fresh. The recreate path
      // will wipe DBs since the old passphrase is unrecoverable.
      _reportCrash(e, st, 'secure-db-passphrase-read');
    }

    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    final pass = base64Encode(bytes);
    try {
      await _secureStorage.write(key: _kPassphraseKey, value: pass);
    } catch (e, st) {
      // Write failed — we'll still use this in-memory passphrase for the
      // session, but next launch will generate a new one and the DBs
      // will look corrupt → fall through to recreate-on-failure.
      _reportCrash(e, st, 'secure-db-passphrase-write');
    }
    _cachedPassphrase = pass;
    return pass;
  }

  /// One-time wipe of pre-Wave-15 plain-SQLite files. Idempotent — guarded
  /// by a SharedPreferences flag. Safe to call on every open; only runs once.
  Future<void> _wipeLegacyDbsOnce() async {
    if (_wipeRan) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kInitFlagKey) == true) {
        _wipeRan = true;
        return;
      }
      final base = await getDatabasesPath();
      for (final name in kKnownDbNames) {
        final path = p.join(base, name);
        try {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
            debugPrint('[secure-db] wiped legacy unencrypted DB: $name');
          }
          // SQLite -journal/-wal/-shm sidecars from interrupted sessions.
          for (final suffix in const ['-journal', '-wal', '-shm']) {
            final side = File('$path$suffix');
            if (await side.exists()) {
              try {
                await side.delete();
              } catch (e) {
                debugPrint('[secure-db] sidecar delete best-effort skip: $e');
              }
            }
          }
        } catch (e) {
          debugPrint('[secure-db] failed to wipe $name: $e');
        }
      }
      await prefs.setBool(_kInitFlagKey, true);
    } catch (e, st) {
      _reportCrash(e, st, 'secure-db-legacy-wipe');
    } finally {
      _wipeRan = true;
    }
  }

  /// Open `dbName` as an encrypted SQLCipher database. API-compatible with
  /// the plain `sqflite.openDatabase()` call — pass the same `version`,
  /// `onCreate`, and optional `onUpgrade` you had before.
  ///
  /// The returned [Database] is the cipher-aware sqflite database from
  /// `sqflite_sqlcipher`, which has the same surface API (query/insert/
  /// update/delete/transaction/batch/rawQuery) as plain sqflite.
  Future<Database> openEncrypted({
    required String dbName,
    required Future<void> Function(Database db, int version) onCreate,
    int version = 1,
    OnDatabaseVersionChangeFn? onUpgrade,
  }) async {
    final cached = _openDbs[dbName];
    if (cached != null && cached.isOpen) return cached;

    await _wipeLegacyDbsOnce();
    final pass = await _getOrCreatePassphrase();
    final base = await getDatabasesPath();
    final path = p.join(base, dbName);

    final db = await openDatabase(
      path,
      password: pass,
      version: version,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
    _openDbs[dbName] = db;
    return db;
  }

  /// Same as [openEncrypted] but if the open call throws (corrupt DB,
  /// passphrase mismatch after a SecureStorage reset, etc.) the file is
  /// deleted and a fresh encrypted DB is created. Use this from callers
  /// where losing ephemeral cache is acceptable (which is every DB in
  /// v1.0 — see class doc).
  Future<Database> openEncryptedOrRecreate({
    required String dbName,
    required Future<void> Function(Database db, int version) onCreate,
    int version = 1,
    OnDatabaseVersionChangeFn? onUpgrade,
  }) async {
    try {
      return await openEncrypted(
        dbName: dbName,
        onCreate: onCreate,
        version: version,
        onUpgrade: onUpgrade,
      );
    } catch (e, st) {
      _reportCrash(e, st, 'secure-db-open');
      debugPrint('[secure-db] $dbName open failed ($e) — wiping & retrying');
      _openDbs.remove(dbName);
      try {
        final base = await getDatabasesPath();
        final path = p.join(base, dbName);
        final f = File(path);
        if (await f.exists()) await f.delete();
        for (final suffix in const ['-journal', '-wal', '-shm']) {
          final side = File('$path$suffix');
          if (await side.exists()) {
            try {
              await side.delete();
            } catch (e) {
              debugPrint('[secure-db] sidecar delete (retry) best-effort skip: $e');
            }
          }
        }
      } catch (e2, st2) {
        _reportCrash(e2, st2, 'secure-db-wipe-after-fail');
      }
      // Second attempt — if this throws too, let the caller handle it.
      return openEncrypted(
        dbName: dbName,
        onCreate: onCreate,
        version: version,
        onUpgrade: onUpgrade,
      );
    }
  }

  /// Test-only — close cached handles and drop the in-memory passphrase.
  @visibleForTesting
  Future<void> resetForTest() async {
    for (final db in _openDbs.values) {
      try {
        await db.close();
      } catch (e) {
        debugPrint('[secure-db] resetForTest db.close best-effort skip: $e');
      }
    }
    _openDbs.clear();
    _cachedPassphrase = null;
    _wipeRan = false;
  }

  void _reportCrash(Object e, StackTrace st, String reason) {
    try {
      FirebaseCrashlytics.instance
          .recordError(e, st, reason: reason, fatal: false);
    } catch (_) {
      // Crashlytics not initialised (tests, early startup) — swallow.
    }
  }
}
