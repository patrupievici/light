import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'secure_db.dart';

/// Single on-device progress photo. The file lives in the app's documents
/// directory under `/photos/` and never leaves the device for v1.0
/// (CLAUDE.md Privacy by default).
@immutable
class ProgressPhoto {
  const ProgressPhoto({
    required this.id,
    required this.filePath,
    required this.takenAt,
    this.label,
  });

  final int id;
  final String filePath;
  final DateTime takenAt;
  final String? label;

  File get file => File(filePath);

  static ProgressPhoto _fromRow(Map<String, dynamic> r) => ProgressPhoto(
        id: r['id'] as int,
        filePath: r['file_path'] as String,
        takenAt: DateTime.parse(r['taken_at'] as String),
        label: r['label'] as String?,
      );
}

/// Client-only persistent store of progress photos.
///
/// Photos stay in the app sandbox (not world-readable on iOS/Android). For
/// v1.1 we plan AES-256 at-rest encryption via `flutter_secure_storage`
/// (for the key) + the `encrypt` package — deferred so we don't add deps now.
// TODO(v1.1): AES-256 at-rest encryption with flutter_secure_storage + encrypt.
class PhotoProgressService {
  PhotoProgressService._();
  static final PhotoProgressService instance = PhotoProgressService._();

  static const String _kDbName = 'zvelt_photo_progress.db';
  static const String _kTable = 'progress_photos';
  static const String _kPhotoDir = 'photos';

  Database? _db;
  Directory? _photoDir;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    // Wave 15 — encrypted via SQLCipher; photo paths are sensitive
    // (reveal the file layout of a private gallery).
    _db = await SecureDb.instance.openEncryptedOrRecreate(
      dbName: _kDbName,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_kTable (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL,
            taken_at TEXT NOT NULL,
            label TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_photos_taken_at ON $_kTable (taken_at)',
        );
      },
    );
    return _db!;
  }

  Future<Directory> _ensurePhotoDir() async {
    if (_photoDir != null) return _photoDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _kPhotoDir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _photoDir = dir;
    return dir;
  }

  /// Copy [source] into the app's photo directory under a deterministic name
  /// (`progress_YYYYMMDD_HHmmss.jpg`), insert a row, and return the model.
  ///
  /// Throws on disk-full / IO errors so callers can show a SnackBar.
  Future<ProgressPhoto> savePhoto(File source, {String? label}) async {
    final dir = await _ensurePhotoDir();
    final now = DateTime.now();
    final fname = _formatFilename(now);
    final dest = File(p.join(dir.path, fname));
    await source.copy(dest.path);

    final db = await _open();
    final id = await db.insert(_kTable, {
      'file_path': dest.path,
      'taken_at': now.toUtc().toIso8601String(),
      'label': label,
    });
    return ProgressPhoto(
      id: id,
      filePath: dest.path,
      takenAt: now,
      label: label,
    );
  }

  /// All photos, newest first. Rows whose underlying file no longer exists
  /// (e.g. user cleared app data) are pruned from the DB and skipped.
  Future<List<ProgressPhoto>> listPhotos({int limit = 50}) async {
    try {
      final db = await _open();
      final rows = await db.query(
        _kTable,
        orderBy: 'taken_at DESC',
        limit: limit,
      );
      final out = <ProgressPhoto>[];
      final missingIds = <int>[];
      for (final r in rows) {
        final photo = ProgressPhoto._fromRow(r);
        if (await photo.file.exists()) {
          out.add(photo);
        } else {
          missingIds.add(photo.id);
        }
      }
      if (missingIds.isNotEmpty) {
        await db.delete(
          _kTable,
          where: 'id IN (${List.filled(missingIds.length, '?').join(',')})',
          whereArgs: missingIds,
        );
      }
      return out;
    } catch (e) {
      debugPrint('[photo-progress] list failed: $e');
      return const [];
    }
  }

  /// Hard delete: removes the row AND the underlying file.
  Future<void> deletePhoto(int id) async {
    try {
      final db = await _open();
      final rows = await db.query(
        _kTable,
        columns: ['file_path'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final fp = rows.first['file_path'] as String?;
        if (fp != null) {
          try {
            final f = File(fp);
            if (await f.exists()) await f.delete();
          } catch (e) {
            // File may already be gone — DB row removal below is what matters.
            debugPrint('[PhotoProgress] file delete best-effort skip: $e');
          }
        }
      }
      await db.delete(_kTable, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('[photo-progress] delete failed: $e');
    }
  }

  /// Earliest photo on file — "Day 0" anchor for the comparison view.
  Future<ProgressPhoto?> firstPhoto() async {
    try {
      final db = await _open();
      final rows = await db.query(
        _kTable,
        orderBy: 'taken_at ASC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final photo = ProgressPhoto._fromRow(rows.first);
      if (!await photo.file.exists()) {
        await db.delete(_kTable, where: 'id = ?', whereArgs: [photo.id]);
        return firstPhoto(); // try next earliest
      }
      return photo;
    } catch (e) {
      debugPrint('[photo-progress] firstPhoto failed: $e');
      return null;
    }
  }

  /// Most recent photo.
  Future<ProgressPhoto?> latestPhoto() async {
    try {
      final db = await _open();
      final rows = await db.query(
        _kTable,
        orderBy: 'taken_at DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final photo = ProgressPhoto._fromRow(rows.first);
      if (!await photo.file.exists()) {
        await db.delete(_kTable, where: 'id = ?', whereArgs: [photo.id]);
        return latestPhoto();
      }
      return photo;
    } catch (e) {
      debugPrint('[photo-progress] latestPhoto failed: $e');
      return null;
    }
  }

  // ── helpers ────────────────────────────────────────────────────────

  static String _formatFilename(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    final ymd = '${dt.year}${two(dt.month)}${two(dt.day)}';
    final hms = '${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
    return 'progress_${ymd}_$hms.jpg';
  }
}
