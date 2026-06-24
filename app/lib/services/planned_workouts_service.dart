import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../config/api_config.dart' show v1Base;
import '../models/activity_kind.dart';
import 'activity_calendar_store.dart';
import 'auth_service.dart';
import 'http_client.dart';

class PlannedWorkoutItem {
  PlannedWorkoutItem({
    required this.id,
    required this.day,
    required this.title,
    required this.kind,
    required this.status,
  });
  final String id;
  final String day;
  final String title;
  final String kind;
  final String status;
}

class PlannedWorkoutsService {
  PlannedWorkoutsService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  Future<Map<String, String>> _headers() => authedJsonHeaders(auth: _auth);

  Future<List<PlannedWorkoutItem>> generateWeekly({
    int tzOffsetMinutes = 0,
    bool force = false,
  }) async {
    final res = await http.post(
      Uri.parse('$v1Base/me/planned-workouts/generate-weekly'),
      headers: await _headers(),
      body: jsonEncode({'tzOffset': tzOffsetMinutes, 'force': force}),
    ).withTimeout();
    if (res.statusCode != 200 && res.statusCode != 201) {
      var msg = 'Could not generate weekly plan';
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>?;
        final m = body?['message']?.toString();
        if (m != null && m.isNotEmpty) msg = m;
      } catch (e) {
        debugPrint('[PlannedWorkoutsService] error-body decode best-effort skip: $e');
      }
      throw Exception(msg);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (data['workouts'] as List<dynamic>? ?? const []);
    final items = list
        .whereType<Map>()
        .map((e) => PlannedWorkoutItem(
              id: e['id']?.toString() ?? '',
              day: e['day']?.toString() ?? '',
              title: e['title']?.toString() ?? '',
              kind: e['kind']?.toString() ?? 'gym',
              status: e['status']?.toString() ?? 'pending',
            ))
        .toList();
    await _persistPlannedLocally(items);
    return items;
  }

  Future<void> _persistPlannedLocally(List<PlannedWorkoutItem> items) async {
    if (items.isEmpty) return;
    final store = ActivityCalendarStore();
    final all = await store.loadPlannedWorkouts();
    for (final item in items) {
      if (item.id.isEmpty || item.day.isEmpty) continue;
      final kind = ActivityKind.tryParse(item.kind) ?? ActivityKind.gym;
      final entry = PlannedWorkoutEntry(
        id: item.id,
        dayYmd: item.day,
        title: item.title.isNotEmpty ? item.title : 'Planned session',
        kind: kind,
        completed: item.status == 'completed',
      );
      final list = List<PlannedWorkoutEntry>.from(all[item.day] ?? []);
      final idx = list.indexWhere((e) => e.id == item.id);
      if (idx >= 0) {
        list[idx] = entry;
      } else {
        list.add(entry);
      }
      all[item.day] = list;
    }
    await store.replacePlannedWorkouts(all);
  }

  Future<void> updateStatus(String id, String status) async {
    final res = await http.patch(
      Uri.parse('$v1Base/me/planned-workouts/$id'),
      headers: await _headers(),
      body: jsonEncode({'status': status}),
    ).withTimeout();
    if (res.statusCode != 200) {
      throw Exception('Could not update planned workout');
    }
  }

  Future<void> remove(String id) async {
    final res = await http.delete(
      Uri.parse('$v1Base/me/planned-workouts/$id'),
      headers: await _headers(),
    ).withTimeout();
    if (res.statusCode != 204) {
      throw Exception('Could not remove planned workout');
    }
  }

  /// Materialize a planned workout into a real draft Workout the tracker can
  /// open. Returns the new workout ID, ready to push into WorkoutTrackerScreen.
  ///
  /// Surfaces `meta.unresolved` (AI exercise names the catalog didn't match)
  /// so the UI can warn "AI suggested X but it's not in our exercise library".
  Future<StartFromPlannedResult> startFromPlanned(String plannedWorkoutId) async {
    final res = await http.post(
      Uri.parse('$v1Base/workouts/from-planned/$plannedWorkoutId'),
      headers: await _headers(),
    ).withTimeout(const Duration(seconds: 30));
    if (res.statusCode != 201) {
      String msg = 'Could not start planned workout';
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>?;
        final m = body?['message']?.toString();
        if (m != null && m.isNotEmpty) msg = m;
      } catch (_) {}
      throw Exception(msg);
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final workout = data['workout'] as Map<String, dynamic>;
    final meta = (data['meta'] as Map<String, dynamic>?) ?? const {};
    final unresolvedRaw = meta['unresolved'];
    return StartFromPlannedResult(
      workoutId: workout['id'] as String,
      resolved: (meta['resolved'] as num?)?.toInt() ?? 0,
      unresolved: unresolvedRaw is List
          ? unresolvedRaw.map((e) => e.toString()).toList()
          : const [],
    );
  }
}

class StartFromPlannedResult {
  const StartFromPlannedResult({
    required this.workoutId,
    required this.resolved,
    required this.unresolved,
  });

  final String workoutId;
  /// Number of AI-suggested exercises that mapped to catalog rows.
  final int resolved;
  /// Names of AI exercises that didn't match anything in the catalog.
  final List<String> unresolved;
}
