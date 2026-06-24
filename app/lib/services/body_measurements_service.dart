import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart' show v1Base;
import '_crash_reporter.dart';
import 'auth_service.dart';
import 'http_client.dart';

/// Manual body measurements (design's Body-tab list: Chest / Waist / Arms /
/// Thighs + optional body fat). Local-first SharedPreferences store, one
/// entry per day (re-logging the same day overwrites it).
///
/// Backend sync (P0 #11): measurements now persist server-side under
/// `/v1/me/measurements`. Each day's [BodyMeasurement] is exploded into one
/// row per field on PUSH, and the server list is reconciled back into per-day
/// entries on PULL. Storage stays canonical metric (chest/waist/arms/thighs
/// in cm → unit `cm`; body fat in % → unit `pct`). Sync is offline-tolerant:
/// local writes are NEVER lost — a failed push marks the day dirty and is
/// replayed on the next sync, and a dirty local day always wins over the
/// server copy (same pattern as nutrition).
class BodyMeasurement {
  const BodyMeasurement({
    required this.date,
    this.chestCm,
    this.waistCm,
    this.armsCm,
    this.thighsCm,
    this.bodyFatPct,
  });

  /// Day of the measurement (normalized to date-only).
  final DateTime date;
  final double? chestCm;
  final double? waistCm;
  final double? armsCm;
  final double? thighsCm;
  final double? bodyFatPct;

  bool get isEmpty =>
      chestCm == null &&
      waistCm == null &&
      armsCm == null &&
      thighsCm == null &&
      bodyFatPct == null;

  Map<String, dynamic> toJson() => {
        'date': _ymd(date),
        if (chestCm != null) 'chestCm': chestCm,
        if (waistCm != null) 'waistCm': waistCm,
        if (armsCm != null) 'armsCm': armsCm,
        if (thighsCm != null) 'thighsCm': thighsCm,
        if (bodyFatPct != null) 'bodyFatPct': bodyFatPct,
      };

  static BodyMeasurement fromJson(Map<String, dynamic> j) => BodyMeasurement(
        date: DateTime.parse(j['date'] as String),
        chestCm: (j['chestCm'] as num?)?.toDouble(),
        waistCm: (j['waistCm'] as num?)?.toDouble(),
        armsCm: (j['armsCm'] as num?)?.toDouble(),
        thighsCm: (j['thighsCm'] as num?)?.toDouble(),
        bodyFatPct: (j['bodyFatPct'] as num?)?.toDouble(),
      );

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class BodyMeasurementsService {
  BodyMeasurementsService._([AuthService? auth]) : _auth = auth ?? AuthService();
  static final BodyMeasurementsService instance = BodyMeasurementsService._();

  final AuthService _auth;

  static const _key = 'body_measurements_v1';

  /// Days whose local write the server has NOT confirmed yet (offline / failed
  /// POST). While a day is in this set its local copy is the source of truth —
  /// pull must never overwrite it, or offline-logged measurements vanish.
  static const _dirtyKey = 'body_measurements_dirty_v1';

  // Sanity bounds — same spirit as the nutrition validations (30–250 kg).
  static const double minCm = 10;
  static const double maxCm = 300;
  static const double minBodyFatPct = 2;
  static const double maxBodyFatPct = 60;

  /// Canonical (field → server type, unit) mapping. Body-tab measurements are
  /// stored metric; the server's controlled `type` set uses `arm`/`thigh`
  /// singular and `body_fat` for the % reading.
  static const Map<String, ({String type, String unit})> _fieldServerMap = {
    'chestCm': (type: 'chest', unit: 'cm'),
    'waistCm': (type: 'waist', unit: 'cm'),
    'armsCm': (type: 'arm', unit: 'cm'),
    'thighsCm': (type: 'thigh', unit: 'cm'),
    'bodyFatPct': (type: 'body_fat', unit: 'pct'),
  };

  /// Reverse lookup: server `type` → the local [BodyMeasurement] field key.
  static const Map<String, String> _serverTypeToField = {
    'chest': 'chestCm',
    'waist': 'waistCm',
    'arm': 'armsCm',
    'thigh': 'thighsCm',
    'body_fat': 'bodyFatPct',
  };

  /// All measurements, newest first (local store).
  Future<List<BodyMeasurement>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final items = decoded
          .map((e) => BodyMeasurement.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return items;
    } catch (_) {
      return const [];
    }
  }

  /// Upserts by day. Empty measurements are ignored. Local write is committed
  /// first (offline-first), then pushed to the server; a failed push leaves the
  /// day dirty for the next sync.
  Future<void> log(BodyMeasurement m) async {
    if (m.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final all = (await list()).toList();
    final ymd = BodyMeasurement._ymd(m.date);
    all.removeWhere((e) => BodyMeasurement._ymd(e.date) == ymd);
    all.add(m);
    all.sort((a, b) => b.date.compareTo(a.date));
    await prefs.setString(_key, jsonEncode([for (final e in all) e.toJson()]));
    // Mark dirty up-front so a crash mid-push still replays the day later.
    await _markDayDirty(ymd, true);
    await _pushDayToServer(m);
  }

  /// Latest value + delta vs the PREVIOUS log that has the same field.
  /// Returns null when the field was never logged.
  static ({double value, double? delta})? latestWithDelta(
    List<BodyMeasurement> all,
    double? Function(BodyMeasurement) pick,
  ) {
    double? latest;
    double? previous;
    for (final m in all) {
      final v = pick(m);
      if (v == null) continue;
      if (latest == null) {
        latest = v;
      } else {
        previous = v;
        break;
      }
    }
    if (latest == null) return null;
    return (value: latest, delta: previous == null ? null : latest - previous);
  }

  // ── Backend sync ───────────────────────────────────────────────────────────

  Future<Set<String>> _dirtyDays() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_dirtyKey);
    return raw == null ? <String>{} : raw.toSet();
  }

  Future<void> _markDayDirty(String ymd, bool dirty) async {
    final prefs = await SharedPreferences.getInstance();
    final set = await _dirtyDays();
    if (dirty) {
      set.add(ymd);
    } else {
      set.remove(ymd);
    }
    await prefs.setStringList(_dirtyKey, set.toList());
  }

  /// Explodes a day into the per-field rows the server expects. Each present
  /// field becomes one `{type, valueNum, unit, measuredAt}` payload measured at
  /// local noon of [m.date] — a stable instant so re-pushing the same day
  /// upserts the same server row instead of duplicating.
  List<Map<String, dynamic>> _rowsForDay(BodyMeasurement m) {
    final measuredAt =
        DateTime(m.date.year, m.date.month, m.date.day, 12).toUtc().toIso8601String();
    final fields = <String, double?>{
      'chestCm': m.chestCm,
      'waistCm': m.waistCm,
      'armsCm': m.armsCm,
      'thighsCm': m.thighsCm,
      'bodyFatPct': m.bodyFatPct,
    };
    final rows = <Map<String, dynamic>>[];
    fields.forEach((field, value) {
      if (value == null) return;
      final map = _fieldServerMap[field];
      if (map == null) return;
      rows.add({
        'type': map.type,
        'valueNum': value,
        'unit': map.unit,
        'measuredAt': measuredAt,
        'source': 'app',
      });
    });
    return rows;
  }

  /// Pushes one day's rows. Returns true only when EVERY field was confirmed by
  /// the server (2xx); on any failure the day stays dirty so it's replayed.
  Future<bool> _pushDayToServer(BodyMeasurement m) async {
    final ymd = BodyMeasurement._ymd(m.date);
    final token = await _auth.getAccessToken();
    if (token == null) return false;
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    var allOk = true;
    for (final row in _rowsForDay(m)) {
      try {
        final res = await http
            .post(
              Uri.parse('$v1Base/me/measurements'),
              headers: headers,
              body: jsonEncode(row),
            )
            .withTimeout();
        if (res.statusCode < 200 || res.statusCode >= 300) allOk = false;
      } catch (e, st) {
        reportError(e, st, reason: 'body-measurements:push-day');
        allOk = false;
      }
    }
    await _markDayDirty(ymd, !allOk);
    return allOk;
  }

  /// Pulls the server list and reconciles it into the local per-day store.
  /// Dirty days (unsynced local writes) are replayed UP and never overwritten.
  /// Offline / failures are swallowed — the local store keeps serving reads.
  Future<void> syncFromServer({int limit = 200}) async {
    final token = await _auth.getAccessToken();
    if (token == null) return;

    // 1. Replay any pending local writes first so the server has them before we
    //    fold its copy back in (offline-logged days are never lost).
    final dirty = await _dirtyDays();
    if (dirty.isNotEmpty) {
      final local = await list();
      for (final m in local) {
        if (dirty.contains(BodyMeasurement._ymd(m.date))) {
          await _pushDayToServer(m);
        }
      }
    }

    // 2. Fetch the server rows and group them back into per-day measurements.
    final List<Map<String, dynamic>> serverRows;
    try {
      final res = await http.get(
        Uri.parse('$v1Base/me/measurements').replace(
          queryParameters: {'limit': '$limit'},
        ),
        headers: {'Authorization': 'Bearer $token'},
      ).withTimeout();
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      serverRows = (body['data'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e, st) {
      reportError(e, st, reason: 'body-measurements:sync');
      return;
    }

    final byDay = <String, Map<String, double>>{};
    for (final row in serverRows) {
      final type = row['type']?.toString();
      final field = type == null ? null : _serverTypeToField[type];
      if (field == null) continue;
      final value = _num(row['valueNum']);
      final measuredAt = row['measuredAt']?.toString();
      if (value == null || measuredAt == null) continue;
      final dt = DateTime.tryParse(measuredAt)?.toLocal();
      if (dt == null) continue;
      final ymd = BodyMeasurement._ymd(dt);
      (byDay[ymd] ??= <String, double>{})[field] = value;
    }

    // 3. Merge into local: a dirty day keeps its local copy untouched.
    final stillDirty = await _dirtyDays();
    final local = await list();
    final merged = <String, BodyMeasurement>{
      for (final m in local) BodyMeasurement._ymd(m.date): m,
    };
    byDay.forEach((ymd, fields) {
      if (stillDirty.contains(ymd)) return; // local write wins
      merged[ymd] = BodyMeasurement(
        date: DateTime.parse(ymd),
        chestCm: fields['chestCm'],
        waistCm: fields['waistCm'],
        armsCm: fields['armsCm'],
        thighsCm: fields['thighsCm'],
        bodyFatPct: fields['bodyFatPct'],
      );
    });

    final out = merged.values.where((m) => !m.isEmpty).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final e in out) e.toJson()]));
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
