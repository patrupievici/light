import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '_crash_reporter.dart';
import 'secure_db.dart';

/// One day's wellness journal entry.
///
/// Keyed by [entryDate] (date-only, no time component). The store enforces
/// at most one entry per calendar day via a UNIQUE constraint and the
/// upsert semantics in [JournalStore.upsertEntry].
///
/// Stored as a CSV in the DB for [soreness] to keep the schema flat —
/// the chip set is small (~11 items) and we never query by individual chip.
@immutable
class JournalEntry {
  const JournalEntry({
    this.id,
    required this.entryDate,
    required this.mood,
    required this.energy,
    required this.soreness,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  /// `null` for entries that haven't been persisted yet.
  final int? id;

  /// Date-only — time component is ignored. The store normalizes to
  /// `yyyy-MM-dd` before reading/writing.
  final DateTime entryDate;

  /// 1..5 — maps to the 5-emoji scale in the UI.
  final int mood;

  /// 1..5 — maps to lightning-bolt count in the UI.
  final int energy;

  /// Body-part identifiers; see [JournalStore.kBodyParts] for the canonical
  /// list. Stored as comma-separated string in SQLite.
  final List<String> soreness;

  /// Free text, max 1000 chars (clamped by the composer).
  final String notes;

  final DateTime createdAt;
  final DateTime updatedAt;

  JournalEntry copyWith({
    int? id,
    DateTime? entryDate,
    int? mood,
    int? energy,
    List<String>? soreness,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JournalEntry(
      id: id ?? this.id,
      entryDate: entryDate ?? this.entryDate,
      mood: mood ?? this.mood,
      energy: energy ?? this.energy,
      soreness: soreness ?? this.soreness,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static JournalEntry _fromRow(Map<String, dynamic> r) {
    final csv = (r['soreness_csv'] as String?) ?? '';
    final parts = csv.isEmpty
        ? const <String>[]
        : csv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return JournalEntry(
      id: r['id'] as int?,
      entryDate: DateTime.parse(r['entry_date'] as String),
      mood: (r['mood'] as num).toInt(),
      energy: (r['energy'] as num).toInt(),
      soreness: parts,
      notes: (r['notes'] as String?) ?? '',
      createdAt: DateTime.parse(r['created_at'] as String),
      updatedAt: DateTime.parse(r['updated_at'] as String),
    );
  }
}

/// Local-first journal store backed by sqflite.
///
/// v1.0 ships offline-only — see CLAUDE.md "Offline-first" principle.
///
/// TODO(v1.1): sync to backend GET /v1/journal, POST /v1/journal/entries.
/// When the API ships, follow the [ActivityCalendarStore] pattern: keep
/// the local table authoritative for unsynced rows, mirror remote rows
/// on read, and add a `synced_at` column.
class JournalStore {
  JournalStore._();
  static final JournalStore instance = JournalStore._();

  static const String _kDbName = 'zvelt_journal.db';
  static const String _kTable = 'journal_entries';

  /// Canonical body-part identifiers used by [JournalEntry.soreness] and the
  /// composer's chip grid. Order is display order.
  static const List<String> kBodyParts = <String>[
    'shoulders',
    'chest',
    'back',
    'biceps',
    'triceps',
    'lower_back',
    'abs',
    'glutes',
    'quads',
    'hamstrings',
    'calves',
  ];

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    // Wave 15 — encrypted via SQLCipher; passphrase from SecureStorage.
    _db = await SecureDb.instance.openEncryptedOrRecreate(
      dbName: _kDbName,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_kTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_date TEXT NOT NULL UNIQUE,
            mood INTEGER NOT NULL,
            energy INTEGER NOT NULL,
            soreness_csv TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_journal_date ON $_kTable (entry_date)',
        );
      },
    );
    return _db!;
  }

  /// Normalize to a date-only key (`yyyy-MM-dd`) ignoring time + tz.
  static String _dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  /// Fetch the entry for [date] (date-only). Returns `null` if absent.
  Future<JournalEntry?> getEntry(DateTime date) async {
    try {
      final db = await _open();
      final rows = await db.query(
        _kTable,
        where: 'entry_date = ?',
        whereArgs: [_dateKey(date)],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return JournalEntry._fromRow(rows.first);
    } catch (e) {
      debugPrint('[journal-store] getEntry failed: $e');
      return null;
    }
  }

  /// Most-recent [limit] entries, newest first.
  Future<List<JournalEntry>> getEntries({int limit = 30}) async {
    try {
      final db = await _open();
      final rows = await db.query(
        _kTable,
        orderBy: 'entry_date DESC',
        limit: limit,
      );
      return rows.map(JournalEntry._fromRow).toList();
    } catch (e) {
      debugPrint('[journal-store] getEntries failed: $e');
      return const [];
    }
  }

  /// Insert if no row exists for `entryDate`, otherwise update in place.
  /// Returns the persisted entry with `id` populated and timestamps refreshed.
  Future<JournalEntry> upsertEntry(JournalEntry e) async {
    final db = await _open();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final key = _dateKey(e.entryDate);
    final csv = e.soreness.join(',');

    final existing = await db.query(
      _kTable,
      where: 'entry_date = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (existing.isEmpty) {
      final createdIso = e.createdAt.toUtc().toIso8601String();
      final id = await db.insert(_kTable, {
        'entry_date': key,
        'mood': e.mood,
        'energy': e.energy,
        'soreness_csv': csv,
        'notes': e.notes,
        'created_at': createdIso,
        'updated_at': nowIso,
      });
      return e.copyWith(
        id: id,
        updatedAt: DateTime.parse(nowIso),
        createdAt: e.createdAt,
      );
    } else {
      final row = existing.first;
      final existingId = row['id'] as int;
      final createdIso = (row['created_at'] as String?) ??
          e.createdAt.toUtc().toIso8601String();
      await db.update(
        _kTable,
        {
          'mood': e.mood,
          'energy': e.energy,
          'soreness_csv': csv,
          'notes': e.notes,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: [existingId],
      );
      return e.copyWith(
        id: existingId,
        createdAt: DateTime.parse(createdIso),
        updatedAt: DateTime.parse(nowIso),
      );
    }
  }

  /// Hard-delete a single entry by id.
  Future<void> deleteEntry(int id) async {
    try {
      final db = await _open();
      await db.delete(_kTable, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('[journal-store] deleteEntry failed: $e');
    }
  }

  /// Map of entries keyed by date-only DateTime, for the chart view.
  /// [from] and [to] are inclusive. Missing days are simply absent from the
  /// map (caller treats those as gaps).
  Future<Map<DateTime, JournalEntry>> rangeMap(
    DateTime from,
    DateTime to,
  ) async {
    try {
      final db = await _open();
      final rows = await db.query(
        _kTable,
        where: 'entry_date >= ? AND entry_date <= ?',
        whereArgs: [_dateKey(from), _dateKey(to)],
        orderBy: 'entry_date ASC',
      );
      final out = <DateTime, JournalEntry>{};
      for (final r in rows) {
        final e = JournalEntry._fromRow(r);
        out[DateTime(e.entryDate.year, e.entryDate.month, e.entryDate.day)] = e;
      }
      return out;
    } catch (e) {
      debugPrint('[journal-store] rangeMap failed: $e');
      return const {};
    }
  }

  /// Test-only — wipe the table.
  @visibleForTesting
  Future<void> clearAll() async {
    try {
      final db = await _open();
      await db.delete(_kTable);
    } catch (e, st) {
      reportError(e, st, reason: 'journal:clear-all');
    }
  }
}
