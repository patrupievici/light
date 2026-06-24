import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Tracks one in-progress gym workout for "Continue where you left off".
class WorkoutDraftSnapshot {
  const WorkoutDraftSnapshot({
    required this.workoutId,
    required this.title,
    required this.savedAt,
    this.exerciseCount = 0,
    this.setsLogged = 0,
  });

  final String workoutId;
  final String title;
  final DateTime savedAt;
  final int exerciseCount;
  final int setsLogged;

  Map<String, dynamic> toJson() => {
        'workoutId': workoutId,
        'title': title,
        'savedAt': savedAt.toIso8601String(),
        'exerciseCount': exerciseCount,
        'setsLogged': setsLogged,
      };

  static WorkoutDraftSnapshot? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = m['workoutId'] as String?;
    final title = m['title'] as String?;
    final saved = m['savedAt'] as String?;
    if (id == null || title == null || saved == null) return null;
    return WorkoutDraftSnapshot(
      workoutId: id,
      title: title,
      savedAt: DateTime.parse(saved),
      exerciseCount: (m['exerciseCount'] as num?)?.toInt() ?? 0,
      setsLogged: (m['setsLogged'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isStale => DateTime.now().difference(savedAt).inHours > 48;
}

class WorkoutDraftStore {
  WorkoutDraftStore({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  static const _keyPrefix = 'zvelt_workout_draft_v1';

  Future<String> _key() async {
    final id = await _auth.getCurrentUserId();
    return '${_keyPrefix}_${id ?? 'anon'}';
  }

  Future<void> save(WorkoutDraftSnapshot draft) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(await _key(), jsonEncode(draft.toJson()));
  }

  Future<WorkoutDraftSnapshot?> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(await _key());
    if (raw == null || raw.isEmpty) return null;
    try {
      final draft = WorkoutDraftSnapshot.fromJson(jsonDecode(raw));
      if (draft == null || draft.isStale) {
        await clear();
        return null;
      }
      return draft;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(await _key());
  }
}
