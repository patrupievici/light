import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart' show v1Base;
import 'auth_service.dart';
import 'http_client.dart';
import 'workout_service.dart';

/// Multi-week training programs (the "Programe" library). Mirrors the backend
/// `/v1/programs` API. The program structure lives server-side (code templates);
/// a started program materializes one day at a time into the normal tracker flow.

double? _toDouble(Object? v) => v is num ? v.toDouble() : null;
int _toInt(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
List<String> _toStrList(Object? v) =>
    v is List ? v.map((e) => e.toString()).toList() : const <String>[];
List<int> _toIntList(Object? v) =>
    v is List ? v.map((e) => _toInt(e)).toList() : const <int>[];

/// Library card metadata for one program template.
class ProgramSummary {
  ProgramSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.level,
    required this.scheme,
    required this.split,
    required this.goalTags,
    required this.weeksOptions,
    required this.defaultWeeks,
    required this.daysPerWeek,
    required this.sessionsInRotation,
    required this.requiresTrainingMax,
    required this.exercisesPerDay,
    required this.sessionTime,
    required this.equipment,
    required this.thumbnails,
  });

  final String id, title, description, level, scheme, split;
  final List<String> goalTags;
  final List<int> weeksOptions;
  final int defaultWeeks, daysPerWeek, sessionsInRotation;
  final bool requiresTrainingMax;

  /// Card metadata (Liftosaur-style library).
  final String exercisesPerDay; // "3" or "3-5"
  final String sessionTime; // "45-60 mins"
  final List<String> equipment; // ["Barbell", "Dumbbell"]
  final List<String> thumbnails; // per-exercise GIF urls

  static ProgramSummary fromJson(Map<String, dynamic> j) => ProgramSummary(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Program',
        description: j['description'] as String? ?? '',
        level: j['level'] as String? ?? 'intermediate',
        scheme: j['scheme'] as String? ?? 'auto',
        split: j['split'] as String? ?? '',
        goalTags: _toStrList(j['goalTags']),
        weeksOptions: _toIntList(j['weeksOptions']),
        defaultWeeks: _toInt(j['defaultWeeks'], 8),
        daysPerWeek: _toInt(j['daysPerWeek'], 3),
        sessionsInRotation: _toInt(j['sessionsInRotation'], 3),
        requiresTrainingMax: j['requiresTrainingMax'] == true,
        exercisesPerDay: j['exercisesPerDay'] as String? ?? '—',
        sessionTime: j['sessionTime'] as String? ?? '',
        equipment: _toStrList(j['equipment']),
        thumbnails: _toStrList(j['thumbnails']),
      );
}

/// One exercise slot in a template preview (human-readable set label derived here).
class ProgramSlotView {
  ProgramSlotView({
    required this.exercise,
    required this.role,
    required this.setsLabel,
    required this.restSeconds,
    required this.warmup,
  });

  final String exercise, role, setsLabel;
  final int restSeconds;
  final bool warmup;

  static String _label(Map<String, dynamic>? sets) {
    if (sets == null) return '';
    final kind = sets['kind'] as String?;
    if (kind == 'straight') {
      return '${_toInt(sets['sets'])}×${_toInt(sets['reps'])}';
    }
    if (kind == 'range') {
      return '${_toInt(sets['sets'])}×${_toInt(sets['minReps'])}–${_toInt(sets['maxReps'])}';
    }
    if (kind == 'wave') {
      switch (sets['wave'] as String?) {
        case '531_main':
          return '5/3/1';
        case '531_bbb':
          return '5×10 BBB';
        case 'nsuns_t1':
          return 'nSuns T1';
        case 'nsuns_t2':
          return 'nSuns T2';
      }
      return 'wave';
    }
    return '';
  }

  static ProgramSlotView fromJson(Map<String, dynamic> j) => ProgramSlotView(
        exercise: j['exercise'] as String? ?? 'Exercise',
        role: j['role'] as String? ?? 'accessory',
        setsLabel: _label(j['sets'] as Map<String, dynamic>?),
        restSeconds: _toInt(j['restSeconds'], 90),
        warmup: j['warmup'] == true,
      );
}

class ProgramDayView {
  ProgramDayView(
      {required this.dayKey, required this.title, required this.slots});
  final String dayKey, title;
  final List<ProgramSlotView> slots;

  static ProgramDayView fromJson(Map<String, dynamic> j) => ProgramDayView(
        dayKey: j['dayKey'] as String? ?? '',
        title: j['title'] as String? ?? '',
        slots: (j['slots'] as List<dynamic>? ?? [])
            .map((s) => ProgramSlotView.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class ProgramTemplateDetail {
  ProgramTemplateDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.scheme,
    required this.weeksOptions,
    required this.defaultWeeks,
    required this.daysPerWeek,
    required this.trainingMaxLifts,
    required this.days,
  });

  final String id, title, description, scheme;
  final List<int> weeksOptions;
  final int defaultWeeks, daysPerWeek;
  final List<String> trainingMaxLifts;
  final List<ProgramDayView> days;

  bool get requiresTrainingMax => trainingMaxLifts.isNotEmpty;

  static ProgramTemplateDetail fromJson(Map<String, dynamic> j) =>
      ProgramTemplateDetail(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Program',
        description: j['description'] as String? ?? '',
        scheme: j['scheme'] as String? ?? 'auto',
        weeksOptions: _toIntList(j['weeksOptions']),
        defaultWeeks: _toInt(j['defaultWeeks'], 8),
        daysPerWeek: _toInt(j['daysPerWeek'], 3),
        trainingMaxLifts: _toStrList(j['trainingMaxLifts']),
        days: (j['days'] as List<dynamic>? ?? [])
            .map((d) => ProgramDayView.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
}

/// A started program instance.
class ActiveProgram {
  ActiveProgram({
    required this.id,
    required this.templateId,
    required this.title,
    required this.progressionScheme,
    required this.status,
    required this.totalWeeks,
    required this.daysPerWeek,
    required this.deloadCadence,
    required this.currentWeek,
    required this.sessionIndex,
    required this.trainingMaxes,
  });

  final String id, templateId, title, progressionScheme, status;
  final int totalWeeks, daysPerWeek, deloadCadence, currentWeek, sessionIndex;
  final Map<String, double> trainingMaxes;

  static ActiveProgram fromJson(Map<String, dynamic> j) {
    final tmRaw = j['trainingMaxes'];
    final tm = <String, double>{};
    if (tmRaw is Map) {
      tmRaw.forEach((k, v) {
        final d = _toDouble(v);
        if (d != null) tm[k.toString()] = d;
      });
    }
    return ActiveProgram(
      id: j['id'] as String,
      templateId: j['templateId'] as String? ?? '',
      title: j['title'] as String? ?? 'Program',
      progressionScheme: j['progressionScheme'] as String? ?? 'auto',
      status: j['status'] as String? ?? 'active',
      totalWeeks: _toInt(j['totalWeeks'], 8),
      daysPerWeek: _toInt(j['daysPerWeek'], 3),
      deloadCadence: _toInt(j['deloadCadence'], 0),
      currentWeek: _toInt(j['currentWeek'], 1),
      sessionIndex: _toInt(j['sessionIndex'], 0),
      trainingMaxes: tm,
    );
  }
}

class MaterializedSetView {
  MaterializedSetView(
      {required this.weightKg, required this.reps, required this.amrap});
  final double? weightKg;
  final int reps;
  final bool amrap;

  static MaterializedSetView fromJson(Map<String, dynamic> j) =>
      MaterializedSetView(
        weightKg: _toDouble(j['weightKg']),
        reps: _toInt(j['reps'], 1),
        amrap: j['amrap'] == true,
      );
}

class MaterializedExercise {
  MaterializedExercise({
    required this.name,
    required this.sets,
    required this.reps,
    required this.suggestedWeightKg,
    required this.setsDetail,
    required this.warmups,
    required this.notes,
  });

  final String name;
  final int sets, reps;
  final double? suggestedWeightKg;
  final List<MaterializedSetView> setsDetail;
  final List<MaterializedSetView> warmups;
  final String? notes;

  static MaterializedExercise fromJson(Map<String, dynamic> j) =>
      MaterializedExercise(
        name: j['name'] as String? ?? 'Exercise',
        sets: _toInt(j['sets'], 3),
        reps: _toInt(j['reps'], 8),
        suggestedWeightKg: _toDouble(j['suggestedWeightKg']),
        setsDetail: (j['setsDetail'] as List<dynamic>? ?? [])
            .map((s) => MaterializedSetView.fromJson(s as Map<String, dynamic>))
            .toList(),
        warmups: (j['warmups'] as List<dynamic>? ?? [])
            .map((s) => MaterializedSetView.fromJson(s as Map<String, dynamic>))
            .toList(),
        notes: j['notes'] as String?,
      );
}

class MaterializedDay {
  MaterializedDay({
    required this.dayKey,
    required this.title,
    required this.week,
    required this.weekInCycle,
    required this.isDeload,
    required this.exercises,
  });

  final String dayKey, title;
  final int week, weekInCycle;
  final bool isDeload;
  final List<MaterializedExercise> exercises;

  static MaterializedDay fromJson(Map<String, dynamic> j) => MaterializedDay(
        dayKey: j['dayKey'] as String? ?? '',
        title: j['title'] as String? ?? '',
        week: _toInt(j['week'], 1),
        weekInCycle: _toInt(j['weekInCycle'], 1),
        isDeload: j['isDeload'] == true,
        exercises: (j['exercises'] as List<dynamic>? ?? [])
            .map(
                (e) => MaterializedExercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ActiveProgramView {
  ActiveProgramView(
      {required this.program, required this.today, required this.completed});
  final ActiveProgram? program;
  final MaterializedDay? today;

  /// True when there is no ACTIVE program but [program] is the most recent
  /// COMPLETED one (show a finished-program card instead of an empty state).
  final bool completed;
}

class ProgramService {
  final _auth = AuthService();
  Future<Map<String, String>> _jsonHeaders() => authedJsonHeaders(auth: _auth);
  Future<Map<String, String>> _readHeaders() => authedReadHeaders(auth: _auth);

  String _errorMessage(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['message'] is String) {
        final message = (body['message'] as String).trim();
        if (message.isNotEmpty) return message;
      }
    } catch (_) {}
    return '$fallback (${res.statusCode})';
  }

  /// GET /v1/programs/templates — the program library.
  Future<List<ProgramSummary>> getTemplates() async {
    final res = await http
        .get(Uri.parse('$v1Base/programs/templates'),
            headers: await _readHeaders())
        .withTimeout();
    if (res.statusCode != 200) {
      throw Exception('Could not load programs (${res.statusCode})');
    }
    final data = (jsonDecode(res.body) as Map<String, dynamic>)['data']
            as List<dynamic>? ??
        [];
    return data
        .map((p) => ProgramSummary.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// GET /v1/programs/templates/:id — full preview (days × slots).
  Future<ProgramTemplateDetail> getTemplate(String id) async {
    final res = await http
        .get(Uri.parse('$v1Base/programs/templates/$id'),
            headers: await _readHeaders())
        .withTimeout();
    if (res.statusCode != 200) {
      throw Exception('Could not load program (${res.statusCode})');
    }
    return ProgramTemplateDetail.fromJson((jsonDecode(res.body)
        as Map<String, dynamic>)['template'] as Map<String, dynamic>);
  }

  /// GET /v1/programs/active — current active program + today's materialized day.
  Future<ActiveProgramView> getActive() async {
    final res = await http
        .get(Uri.parse('$v1Base/programs/active'),
            headers: await _readHeaders())
        .withTimeout();
    if (res.statusCode != 200) {
      throw Exception('Could not load active program (${res.statusCode})');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final prog = body['program'];
    final today = body['today'];
    return ActiveProgramView(
      program:
          prog is Map<String, dynamic> ? ActiveProgram.fromJson(prog) : null,
      today: today is Map<String, dynamic>
          ? MaterializedDay.fromJson(today)
          : null,
      completed: body['completed'] == true,
    );
  }

  /// PATCH /v1/programs/:id — set/refresh training maxes from 1RMs.
  Future<ActiveProgram> setTrainingMaxes(
      String programId, Map<String, double> oneRepMaxes) async {
    final res = await http
        .patch(
          Uri.parse('$v1Base/programs/$programId'),
          headers: await _jsonHeaders(),
          body: jsonEncode({'oneRepMaxes': oneRepMaxes}),
        )
        .withTimeout();
    if (res.statusCode != 200) {
      throw Exception('Could not save training maxes (${res.statusCode})');
    }
    return ActiveProgram.fromJson((jsonDecode(res.body)
        as Map<String, dynamic>)['program'] as Map<String, dynamic>);
  }

  /// POST /v1/programs/start — start a template (archives any active program).
  Future<ActiveProgram> startProgram({
    required String templateId,
    int? weeks,
    Map<String, double>? oneRepMaxes,
    List<String>? equipmentTags,
  }) async {
    final res = await http
        .post(
          Uri.parse('$v1Base/programs/start'),
          headers: await _jsonHeaders(),
          body: jsonEncode({
            'templateId': templateId,
            if (weeks != null) 'weeks': weeks,
            if (oneRepMaxes != null && oneRepMaxes.isNotEmpty)
              'oneRepMaxes': oneRepMaxes,
            if (equipmentTags != null && equipmentTags.isNotEmpty)
              'equipmentTags': equipmentTags,
          }),
        )
        .withTimeout();
    if (res.statusCode != 201) {
      throw Exception('Could not start program (${res.statusCode})');
    }
    return ActiveProgram.fromJson((jsonDecode(res.body)
        as Map<String, dynamic>)['program'] as Map<String, dynamic>);
  }

  /// POST /v1/programs/:id/start-day — materialize today → returns a draft workoutId.
  Future<String> startProgramDay(String programId) async {
    final res = await http
        .post(
          Uri.parse('$v1Base/programs/$programId/start-day'),
          headers: await _jsonHeaders(),
          body: jsonEncode({}),
        )
        .withTimeout();
    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Could not start session'));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final id = body['workoutId'];
    if (id is! String || id.isEmpty) {
      throw Exception('Session has no exercises to start');
    }
    try {
      final workout = await WorkoutService().getWorkout(id);
      await WorkoutService.saveActiveWorkoutPointer(workout,
          label: 'Program session');
    } catch (_) {
      // Best-effort only: the tracker still opens from the returned id.
    }
    return id;
  }

  /// POST /v1/programs/:id/advance — mark the session done, advance week/TM.
  Future<ActiveProgram> advance(String programId) async {
    final res = await http
        .post(
          Uri.parse('$v1Base/programs/$programId/advance'),
          headers: await _jsonHeaders(),
          body: jsonEncode({}),
        )
        .withTimeout();
    if (res.statusCode != 200) {
      throw Exception('Could not advance program (${res.statusCode})');
    }
    return ActiveProgram.fromJson((jsonDecode(res.body)
        as Map<String, dynamic>)['program'] as Map<String, dynamic>);
  }

  /// PATCH /v1/programs/:id — archive the active program.
  Future<void> archive(String programId) async {
    final res = await http
        .patch(
          Uri.parse('$v1Base/programs/$programId'),
          headers: await _jsonHeaders(),
          body: jsonEncode({'status': 'archived'}),
        )
        .withTimeout();
    if (res.statusCode != 200) {
      throw Exception('Could not archive program (${res.statusCode})');
    }
  }
}
