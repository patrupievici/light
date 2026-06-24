import 'package:sqflite_sqlcipher/sqflite.dart';

import '_crash_reporter.dart';
import 'moderation_service.dart';
import 'secure_db.dart';

/// Wave 22 P0.2 — Apple §1.2 / Play UGC moderation requires *honest*
/// "we received your report" UX. Until the backend ships
/// `POST /v1/users/:id/report`, this outbox queues reports locally in
/// an encrypted SQLCipher table and retries on every app foreground.
///
/// Failure modes:
/// - Network drop → row stays in outbox, retried later.
/// - 404 (endpoint not deployed) → row stays in outbox indefinitely,
///   retried on every foreground.
/// - Other 4xx/5xx → `attempts` increments; after `_kMaxAttempts` the
///   row is logged to Crashlytics and removed (so the user isn't lied
///   to about a doomed report sitting around forever).
class ReportOutboxService {
  ReportOutboxService({ModerationService? service})
      : _service = service ?? ModerationService();

  static ReportOutboxService? _instance;
  factory ReportOutboxService.shared() =>
      _instance ??= ReportOutboxService();

  final ModerationService _service;

  static const _kDbName = 'zvelt_report_outbox.db';
  static const _kTable = 'report_outbox';
  static const int _kMaxAttempts = 5;

  Database? _db;
  bool _draining = false;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    _db = await SecureDb.instance.openEncryptedOrRecreate(
      dbName: _kDbName,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_kTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            target_user_id TEXT NOT NULL,
            category TEXT NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_report_outbox_created ON $_kTable (created_at)',
        );
      },
    );
    return _db!;
  }

  /// Insert a pending report. Called when the live POST returns 404
  /// (backend not deployed) so the user's report isn't silently dropped.
  Future<void> enqueue({
    required String targetUserId,
    required String category,
    String? note,
  }) async {
    try {
      final db = await _open();
      final trimmedNote = note?.trim();
      await db.insert(_kTable, {
        'target_user_id': targetUserId,
        'category': category,
        'note': (trimmedNote == null || trimmedNote.isEmpty)
            ? null
            : trimmedNote,
        'created_at': DateTime.now().toIso8601String(),
        'attempts': 0,
      });
    } catch (e, st) {
      reportError(e, st, reason: 'report-outbox:enqueue');
    }
  }

  /// Count of reports still waiting to sync — for "{N} pending reports
  /// waiting to sync" footer in BlockedUsersScreen.
  Future<int> pendingCount() async {
    try {
      final db = await _open();
      final res = await db.rawQuery('SELECT COUNT(*) AS c FROM $_kTable');
      final c = res.isNotEmpty ? res.first['c'] : 0;
      return (c is int) ? c : (c as num?)?.toInt() ?? 0;
    } catch (e, st) {
      reportError(e, st, reason: 'report-outbox:count');
      return 0;
    }
  }

  /// Best-effort drain — POSTs every queued row. On success deletes
  /// the row, on 404 keeps it for the next attempt, on other errors
  /// increments `attempts` and drops the row once over the cap.
  ///
  /// Caller should invoke from app foreground (lifecycle resumed) and
  /// from anywhere a user opens the BlockedUsersScreen.
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      final db = await _open();
      final rows = await db.query(_kTable, orderBy: 'created_at ASC');
      for (final row in rows) {
        final id = row['id'] as int?;
        final targetUserId = row['target_user_id'] as String?;
        final category = row['category'] as String?;
        final note = row['note'] as String?;
        final attempts = (row['attempts'] as int?) ?? 0;
        if (id == null || targetUserId == null || category == null) continue;
        try {
          await _service.reportUser(
            targetUserId,
            category: category,
            note: note,
          );
          // Success → drop the row.
          await db.delete(_kTable, where: 'id = ?', whereArgs: [id]);
        } on ModerationException catch (e, st) {
          if (e.isNotDeployed) {
            // Keep the row — backend not online yet. Don't bump attempts
            // because the failure isn't the report's fault.
            continue;
          }
          if (e.isNetworkError) {
            // Transient network issue — leave the row alone, try again
            // on the next foreground. Don't bump attempts.
            continue;
          }
          final next = attempts + 1;
          if (next >= _kMaxAttempts) {
            reportError(
              e,
              st,
              reason: 'report-outbox:abandon (cat=$category, attempts=$next)',
            );
            await db.delete(_kTable, where: 'id = ?', whereArgs: [id]);
          } else {
            await db.update(
              _kTable,
              {'attempts': next},
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        } catch (e, st) {
          // Unexpected error — bump attempts and continue.
          final next = attempts + 1;
          if (next >= _kMaxAttempts) {
            reportError(
              e,
              st,
              reason: 'report-outbox:abandon-unexpected (attempts=$next)',
            );
            await db.delete(_kTable, where: 'id = ?', whereArgs: [id]);
          } else {
            await db.update(
              _kTable,
              {'attempts': next},
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        }
      }
    } catch (e, st) {
      reportError(e, st, reason: 'report-outbox:drain');
    } finally {
      _draining = false;
    }
  }
}
