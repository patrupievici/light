import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/activity_kind.dart';
import '_crash_reporter.dart';
import 'auth_service.dart';
import 'feed_refresh_notifier.dart';

/// Sesiune cardio manuală (todo Excel #19) — distanță/timp opționale.
class ManualCardioSession {
  ManualCardioSession({
    required this.kind,
    this.distanceKm,
    this.durationMin,
    this.id,
  });
  final ActivityKind kind;
  final double? distanceKm;
  final int? durationMin;

  /// Optional client id (e.g. the session's start epoch). When present,
  /// [ActivityCalendarStore.addManualSession] is idempotent for it — retrying
  /// a failed upload can't double-count the session in the weekly card.
  final String? id;

  Map<String, dynamic> toJson() => {
        'kind': kind.id,
        if (distanceKm != null) 'distanceKm': distanceKm,
        if (durationMin != null) 'durationMin': durationMin,
        if (id != null) 'id': id,
      };

  static ManualCardioSession? fromJson(dynamic o) {
    if (o is! Map) return null;
    final m = Map<String, dynamic>.from(o);
    final k = ActivityKind.tryParse(m['kind'] as String?);
    if (k == null || k == ActivityKind.gym) return null;
    return ManualCardioSession(
      kind: k,
      distanceKm: (m['distanceKm'] as num?)?.toDouble(),
      durationMin: (m['durationMin'] as num?)?.toInt(),
      id: (m['id'] as String?)?.trim().isEmpty ?? true
          ? null
          : (m['id'] as String).trim(),
    );
  }

  String get subtitle {
    final parts = <String>[];
    if (distanceKm != null) parts.add('${distanceKm!.toStringAsFixed(1)} km');
    if (durationMin != null) parts.add('${durationMin!} min');
    return parts.isEmpty ? 'Manual log' : parts.join(' · ');
  }
}

/// Minute cardio manual agregate pe zi (pentru grafice).
class ManualCardioDayPoint {
  ManualCardioDayPoint({required this.date, required this.totalMinutes, required this.sessionCount});
  final DateTime date;
  final int totalMinutes;
  final int sessionCount;
}

/// Activități non-gym (alergare, înot, …) pe zi — stocate local **per utilizator**.
/// Cheie zi: `yyyy-MM-dd` în timezone local.
class ActivityCalendarStore {
  ActivityCalendarStore({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  /// Prefix chei locale curente (`…_$userId`).
  static const String _prefsActivity = 'zvelt_activity_calendar_v1';
  static const String _prefsManual = 'zvelt_manual_cardio_v1';
  static const String _prefsPlanned = 'zvelt_planned_workouts_v1';
  /// Zile cu gym sincronizate de la server (`yyyy-MM-dd`). QA P1.2 — astfel
  /// reinstall pe alt device păstrează istoricul după primul sync.
  static const String _prefsServerGymDays = 'zvelt_server_gym_days_v1';
  /// Timestamp ms (epoch UTC) al ultimului sync reușit cu serverul.
  static const String _prefsCalendarLastSync = 'zvelt_calendar_last_sync_v1';

  /// Migrate din branding vechi Forge (`forge_*` scoped sau global).
  static const String _forgeActivityScopedPrefix = 'forge_activity_calendar_v1';
  static const String _forgeManualScopedPrefix = 'forge_manual_cardio_v1';
  static const String _forgePlannedScopedPrefix = 'forge_planned_workouts_v1';

  static const String _forgeActivityGlobal = 'forge_activity_calendar_v1';
  static const String _forgeManualGlobal = 'forge_manual_cardio_v1';
  static const String _forgePlannedGlobal = 'forge_planned_workouts_v1';

  Future<String> _calendarPrefsKey() async {
    final id = await _auth.getCurrentUserId();
    return '${_prefsActivity}_${id ?? 'anonymous'}';
  }

  Future<String> _manualPrefsKey() async {
    final id = await _auth.getCurrentUserId();
    return '${_prefsManual}_${id ?? 'anonymous'}';
  }

  Future<String> _plannedPrefsKey() async {
    final id = await _auth.getCurrentUserId();
    return '${_prefsPlanned}_${id ?? 'anonymous'}';
  }

  Future<String> _serverGymDaysKey() async {
    final id = await _auth.getCurrentUserId();
    return '${_prefsServerGymDays}_${id ?? 'anonymous'}';
  }

  Future<String> _calendarLastSyncKey() async {
    final id = await _auth.getCurrentUserId();
    return '${_prefsCalendarLastSync}_${id ?? 'anonymous'}';
  }

  /// Zilele cu workout-uri gym sincronizate de la server (`yyyy-MM-dd`).
  /// Folosit ca cache offline pentru calendar (QA P1.2).
  Future<Set<String>> loadServerGymDays() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(await _serverGymDaysKey());
    if (raw == null || raw.isEmpty) return <String>{};
    return raw.toSet();
  }

  /// Adaugă [dates] în cache-ul local (idempotent).
  Future<void> mergeServerGymDays(Iterable<String> dates) async {
    if (dates.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final key = await _serverGymDaysKey();
    final current = (p.getStringList(key) ?? const <String>[]).toSet();
    final before = current.length;
    current.addAll(dates);
    if (current.length == before) return;
    await p.setStringList(key, current.toList());
  }

  /// `null` dacă nu s-a sincronizat niciodată.
  Future<DateTime?> getLastCalendarSync() async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(await _calendarLastSyncKey());
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<void> setLastCalendarSync(DateTime t) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(await _calendarLastSyncKey(), t.toUtc().millisecondsSinceEpoch);
  }

  /// Încarcă JSON brut: cheie Zvelt scoped → migrate din Forge scoped/user sau Forge global.
  Future<String?> _loadPrefsRaw({
    required SharedPreferences p,
    required Future<String> Function() zveltScopedKey,
    required String forgeScopedPrefix,
    required String forgeGlobalKey,
  }) async {
    final scoped = await zveltScopedKey();
    var raw = p.getString(scoped);
    if (raw != null && raw.isNotEmpty) return raw;

    final id = await _auth.getCurrentUserId();
    final forgeScoped = '${forgeScopedPrefix}_${id ?? 'anonymous'}';
    raw = p.getString(forgeScoped);
    if (raw != null && raw.isNotEmpty) {
      await p.setString(scoped, raw);
      await p.remove(forgeScoped);
      return raw;
    }

    raw = p.getString(forgeGlobalKey);
    if (raw != null && raw.isNotEmpty) {
      await p.setString(scoped, raw);
      await p.remove(forgeGlobalKey);
      return raw;
    }
    return null;
  }

  Future<Map<String, List<ActivityKind>>> loadAll() async {
    final p = await SharedPreferences.getInstance();
    final raw = await _loadPrefsRaw(
      p: p,
      zveltScopedKey: _calendarPrefsKey,
      forgeScopedPrefix: _forgeActivityScopedPrefix,
      forgeGlobalKey: _forgeActivityGlobal,
    );
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, List<ActivityKind>>{};
      map.forEach((day, v) {
        if (v is! List) return;
        final kinds = v
            .map((e) => ActivityKind.tryParse(e?.toString()))
            .whereType<ActivityKind>()
            .where((k) => k != ActivityKind.gym)
            .toList();
        if (kinds.isNotEmpty) out[day] = kinds;
      });
      return out;
    } catch (e, st) {
      reportError(e, st, reason: 'calendar:load-all-decode');
      return {};
    }
  }

  Future<void> add(String dayYmd, ActivityKind kind) async {
    if (kind == ActivityKind.gym) return;
    final all = await loadAll();
    final list = List<ActivityKind>.from(all[dayYmd] ?? []);
    list.add(kind);
    all[dayYmd] = list;
    await _save(all);
  }

  Future<void> removeAt(String dayYmd, int index) async {
    final all = await loadAll();
    final list = List<ActivityKind>.from(all[dayYmd] ?? []);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    if (list.isEmpty) {
      all.remove(dayYmd);
    } else {
      all[dayYmd] = list;
    }
    await _save(all);
  }

  Future<void> _save(Map<String, List<ActivityKind>> all) async {
    final p = await SharedPreferences.getInstance();
    final jsonMap = <String, dynamic>{};
    all.forEach((k, v) {
      jsonMap[k] = v.map((e) => e.id).toList();
    });
    await p.setString(await _calendarPrefsKey(), jsonEncode(jsonMap));
  }

  Future<Map<String, List<ManualCardioSession>>> loadManualSessions() async {
    final p = await SharedPreferences.getInstance();
    final raw = await _loadPrefsRaw(
      p: p,
      zveltScopedKey: _manualPrefsKey,
      forgeScopedPrefix: _forgeManualScopedPrefix,
      forgeGlobalKey: _forgeManualGlobal,
    );
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, List<ManualCardioSession>>{};
      map.forEach((day, v) {
        if (v is! List) return;
        final list = v.map(ManualCardioSession.fromJson).whereType<ManualCardioSession>().toList();
        if (list.isNotEmpty) out[day] = list;
      });
      return out;
    } catch (e, st) {
      reportError(e, st, reason: 'calendar:load-manual-decode');
      return {};
    }
  }

  Future<void> addManualSession(String dayYmd, ManualCardioSession session) async {
    final all = await loadManualSessions();
    final list = List<ManualCardioSession>.from(all[dayYmd] ?? []);
    // Idempotent for id-carrying sessions: a save Retry (4xx / cold backend)
    // replaces the earlier mirror instead of double-counting it.
    if (session.id != null) {
      list.removeWhere((s) => s.id == session.id);
    }
    list.add(session);
    all[dayYmd] = list;
    await _saveManual(all);
    // Home's weekly cardio card reads this store — wake it on every save.
    FeedRefreshNotifier.instance.bump(RefreshScope.home);
  }

  Future<void> removeManualSessionAt(String dayYmd, int index) async {
    final all = await loadManualSessions();
    final list = List<ManualCardioSession>.from(all[dayYmd] ?? []);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    if (list.isEmpty) {
      all.remove(dayYmd);
    } else {
      all[dayYmd] = list;
    }
    await _saveManual(all);
    FeedRefreshNotifier.instance.bump(RefreshScope.home);
  }

  Future<void> _saveManual(Map<String, List<ManualCardioSession>> all) async {
    final p = await SharedPreferences.getInstance();
    final jsonMap = <String, dynamic>{};
    all.forEach((k, v) {
      jsonMap[k] = v.map((e) => e.toJson()).toList();
    });
    await p.setString(await _manualPrefsKey(), jsonEncode(jsonMap));
  }

  Future<Map<String, List<PlannedWorkoutEntry>>> loadPlannedWorkouts() async {
    final p = await SharedPreferences.getInstance();
    final raw = await _loadPrefsRaw(
      p: p,
      zveltScopedKey: _plannedPrefsKey,
      forgeScopedPrefix: _forgePlannedScopedPrefix,
      forgeGlobalKey: _forgePlannedGlobal,
    );
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, List<PlannedWorkoutEntry>>{};
      map.forEach((day, v) {
        if (v is! List) return;
        final list = v
            .map(PlannedWorkoutEntry.fromJson)
            .whereType<PlannedWorkoutEntry>()
            .toList();
        if (list.isNotEmpty) out[day] = list;
      });
      return out;
    } catch (e, st) {
      reportError(e, st, reason: 'calendar:load-planned-decode');
      return {};
    }
  }

  Future<void> replacePlannedWorkouts(Map<String, List<PlannedWorkoutEntry>> incoming) async {
    if (incoming.isEmpty) return;
    final all = await loadPlannedWorkouts();
    incoming.forEach((day, entries) {
      all[day] = List<PlannedWorkoutEntry>.from(entries);
    });
    await _savePlanned(all);
  }

  Future<void> addPlannedWorkout(PlannedWorkoutEntry entry) async {
    final all = await loadPlannedWorkouts();
    final list = List<PlannedWorkoutEntry>.from(all[entry.dayYmd] ?? []);
    list.add(entry);
    all[entry.dayYmd] = list;
    await _savePlanned(all);
  }

  Future<void> updatePlannedWorkoutStatus({
    required String dayYmd,
    required String id,
    required bool completed,
  }) async {
    final all = await loadPlannedWorkouts();
    final list = List<PlannedWorkoutEntry>.from(all[dayYmd] ?? []);
    final idx = list.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    list[idx] = list[idx].copyWith(completed: completed);
    all[dayYmd] = list;
    await _savePlanned(all);
  }

  Future<void> removePlannedWorkoutAt(String dayYmd, int index) async {
    final all = await loadPlannedWorkouts();
    final list = List<PlannedWorkoutEntry>.from(all[dayYmd] ?? []);
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    if (list.isEmpty) {
      all.remove(dayYmd);
    } else {
      all[dayYmd] = list;
    }
    await _savePlanned(all);
  }

  Future<void> markGymPlannedCompletedForDays(Set<String> completedGymDays) async {
    if (completedGymDays.isEmpty) return;
    final all = await loadPlannedWorkouts();
    var changed = false;
    all.forEach((day, entries) {
      if (!completedGymDays.contains(day)) return;
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        if (!e.completed && e.kind == ActivityKind.gym) {
          entries[i] = e.copyWith(completed: true);
          changed = true;
        }
      }
    });
    if (changed) await _savePlanned(all);
  }

  Future<void> _savePlanned(Map<String, List<PlannedWorkoutEntry>> all) async {
    final p = await SharedPreferences.getInstance();
    final jsonMap = <String, dynamic>{};
    all.forEach((k, v) {
      jsonMap[k] = v.map((e) => e.toJson()).toList();
    });
    await p.setString(await _plannedPrefsKey(), jsonEncode(jsonMap));
  }

  static String _dayYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Ultimele [days] zile, ordine cronologică vechi → nou.
  Future<List<ManualCardioDayPoint>> loadManualCardioHistory({int days = 30}) async {
    final manual = await loadManualSessions();
    final n = days.clamp(1, 365);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final out = <ManualCardioDayPoint>[];
    for (var i = n - 1; i >= 0; i--) {
      final d = todayDate.subtract(Duration(days: i));
      final key = _dayYmd(d);
      final sessions = manual[key] ?? [];
      var mins = 0;
      for (final s in sessions) {
        mins += s.durationMin ?? 0;
      }
      out.add(ManualCardioDayPoint(date: d, totalMinutes: mins, sessionCount: sessions.length));
    }
    return out;
  }
}

class PlannedWorkoutEntry {
  PlannedWorkoutEntry({
    required this.id,
    required this.dayYmd,
    required this.title,
    required this.kind,
    this.completed = false,
    this.time,
  });

  final String id;
  final String dayYmd;
  final String title;
  final ActivityKind kind;
  final bool completed;

  /// Optional display time "HH:mm" (Plan agenda rows). Backwards-compatible:
  /// older persisted entries simply have no time.
  final String? time;

  Map<String, dynamic> toJson() => {
        'id': id,
        'dayYmd': dayYmd,
        'title': title,
        'kind': kind.id,
        'completed': completed,
        if (time != null) 'time': time,
      };

  static PlannedWorkoutEntry? fromJson(dynamic o) {
    if (o is! Map) return null;
    final m = Map<String, dynamic>.from(o);
    final id = (m['id'] as String?)?.trim();
    final dayYmd = (m['dayYmd'] as String?)?.trim();
    final title = (m['title'] as String?)?.trim();
    final kind = ActivityKind.tryParse(m['kind'] as String?);
    if (id == null || dayYmd == null || title == null || kind == null) return null;
    return PlannedWorkoutEntry(
      id: id,
      dayYmd: dayYmd,
      title: title,
      kind: kind,
      completed: m['completed'] == true,
      time: (m['time'] as String?)?.trim(),
    );
  }

  PlannedWorkoutEntry copyWith({
    String? id,
    String? dayYmd,
    String? title,
    ActivityKind? kind,
    bool? completed,
    String? time,
  }) {
    return PlannedWorkoutEntry(
      id: id ?? this.id,
      dayYmd: dayYmd ?? this.dayYmd,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      completed: completed ?? this.completed,
      time: time ?? this.time,
    );
  }
}

class NutritionDayEntry {
  NutritionDayEntry({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.goal,
  });

  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final String goal;

  Map<String, dynamic> toJson() => {
        'calories': calories,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
        'goal': goal,
      };

  static NutritionDayEntry? fromJson(dynamic o) {
    if (o is! Map) return null;
    final m = Map<String, dynamic>.from(o);
    final calories = m['calories'] as int?;
    final proteinG = m['proteinG'] as int?;
    final carbsG = m['carbsG'] as int?;
    final fatG = m['fatG'] as int?;
    final goal = m['goal'] as String?;
    if (calories == null || proteinG == null || carbsG == null || fatG == null || goal == null) return null;
    return NutritionDayEntry(
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      goal: goal,
    );
  }
}
