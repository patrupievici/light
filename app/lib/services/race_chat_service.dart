// TODO(v1.1): realtime race chat via /v1/challenges/{id}/chat (POST + WS or
// FCM topic per race) — see QA_BACKLOG. v1.0 is STRICTLY local-only: the UI
// promises 'PRIVATE · ONLY YOU', so note bodies must never leave the device.
// When v1.1 ships, sending to the shared room must be an explicit user
// action (fresh opt-in), never a silent upload of existing notes.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '_crash_reporter.dart';
import 'secure_db.dart';

/// One row in the race chat — either sent by the local user or by a peer
/// (peer messages arrive when we eventually wire up realtime; for v1.0 the
/// table holds only locally-sent messages, which is acceptable since the
/// chat is "trash talk" content and even a self-only echo gives the user
/// the satisfying composer flow without blocking on backend).
class RaceChatMessage {
  const RaceChatMessage({
    this.id,
    required this.challengeId,
    required this.userId,
    required this.username,
    required this.body,
    required this.sentAt,
    required this.isMe,
  });

  final int? id;
  final String challengeId;
  final String userId;
  final String username;
  final String body;
  final DateTime sentAt;
  final bool isMe;

  static RaceChatMessage _fromRow(Map<String, dynamic> r) {
    return RaceChatMessage(
      id: r['id'] as int?,
      challengeId: r['challenge_id'] as String? ?? '',
      userId: r['user_id'] as String? ?? '',
      username: r['username'] as String? ?? '',
      body: r['body'] as String? ?? '',
      sentAt: DateTime.tryParse((r['sent_at'] as String?) ?? '') ??
          DateTime.now().toUtc(),
      isMe: ((r['is_me'] as num?)?.toInt() ?? 0) == 1,
    );
  }
}

/// Local-only race notes store (see file header — nothing leaves the device).
class RaceChatService {
  RaceChatService();

  static const String _kDbName = 'zvelt_race_chat.db';
  static const String _kTable = 'race_chat_messages';

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    _db = await SecureDb.instance.openEncryptedOrRecreate(
      dbName: _kDbName,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_kTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            challenge_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            username TEXT NOT NULL,
            body TEXT NOT NULL,
            sent_at TEXT NOT NULL,
            is_me INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_race_chat_challenge ON $_kTable (challenge_id, sent_at)',
        );
      },
    );
    return _db!;
  }

  /// Insert + best-effort POST. The POST is "fire-and-forget" — any non-2xx
  /// (including 404 until the endpoint ships) is swallowed and reported to
  /// Crashlytics with `reason: 'race-chat:send-server'`. Local persist
  /// always succeeds first so the chat works offline.
  Future<RaceChatMessage> sendMessage({
    required String challengeId,
    required String body,
    required String userId,
    required String username,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Race chat message body cannot be empty');
    }
    final db = await _open();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert(_kTable, {
      'challenge_id': challengeId,
      'user_id': userId,
      'username': username,
      'body': trimmed,
      'sent_at': nowIso,
      'is_me': 1,
    });

    // NO server POST in v1.0 — the UI promises 'PRIVATE · ONLY YOU' three
    // times (pill, banner, hint), so the note body must not leave the
    // device. The old best-effort POST meant that the moment the v1.1
    // multi-athlete chat endpoint shipped, notes written under a privacy
    // promise would land in a shared room. When v1.1 chat arrives, sending
    // must be an explicit user action (fresh opt-in), not a silent upload.

    return RaceChatMessage(
      id: id,
      challengeId: challengeId,
      userId: userId,
      username: username,
      body: trimmed,
      sentAt: DateTime.parse(nowIso),
      isMe: true,
    );
  }

  /// Returns the newest [limit] messages for [challengeId], oldest first
  /// (chronological order for chat render).
  Future<List<RaceChatMessage>> getMessages(
    String challengeId, {
    int limit = 100,
  }) async {
    try {
      final db = await _open();
      final rows = await db.query(
        _kTable,
        where: 'challenge_id = ?',
        whereArgs: [challengeId],
        orderBy: 'sent_at DESC',
        limit: limit,
      );
      // Reverse so caller renders oldest at top, newest at bottom.
      final list = rows.map(RaceChatMessage._fromRow).toList().reversed.toList();
      return list;
    } catch (e, st) {
      reportError(e, st, reason: 'race-chat:get-messages');
      return const [];
    }
  }

  /// Wipe history for a single race — called when the user leaves a race.
  Future<void> clearForChallenge(String challengeId) async {
    try {
      final db = await _open();
      await db.delete(
        _kTable,
        where: 'challenge_id = ?',
        whereArgs: [challengeId],
      );
    } catch (e, st) {
      reportError(e, st, reason: 'race-chat:clear-challenge');
    }
  }

  /// Test-only — wipe everything.
  Future<void> clearAll() async {
    try {
      final db = await _open();
      await db.delete(_kTable);
    } catch (e) {
      debugPrint('[race-chat] clearAll failed: $e');
    }
  }
}
