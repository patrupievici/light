import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Fasting state (handoff Nutrition §13d + sheetFast): a protocol
/// (16:8 / 18:6 / 20:4) and a start timestamp, persisted per user. The ring
/// and "Ends in" label are computed live from wall-clock time.
class FastingState {
  const FastingState({
    required this.active,
    required this.protocolHours,
    this.startMs,
  });

  final bool active;

  /// Fasting window length in hours (16, 18 or 20).
  final int protocolHours;

  /// Epoch ms when the current fast started (null when inactive).
  final int? startMs;

  DateTime? get startAt =>
      startMs == null ? null : DateTime.fromMillisecondsSinceEpoch(startMs!);

  DateTime? get endsAt =>
      startAt?.add(Duration(hours: protocolHours));

  Duration get elapsed => !active || startAt == null
      ? Duration.zero
      : DateTime.now().difference(startAt!);

  Duration get remaining {
    final end = endsAt;
    if (!active || end == null) return Duration.zero;
    final r = end.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  /// 0..1 progress through the fasting window.
  double get progress {
    if (!active || startAt == null) return 0;
    final total = Duration(hours: protocolHours).inSeconds;
    if (total <= 0) return 0;
    return (elapsed.inSeconds / total).clamp(0.0, 1.0);
  }

  String get protocolLabel => switch (protocolHours) {
        18 => '18:6',
        20 => '20:4',
        _ => '16:8',
      };
}

/// Per-user persisted fasting store.
class FastingService {
  FastingService({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;

  static const _kPrefix = 'zvelt_fasting_v1';

  Future<String> _key() async {
    final id = await _auth.getCurrentUserId();
    return '${_kPrefix}_${id ?? 'anonymous'}';
  }

  Future<FastingState> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(await _key());
      if (raw == null || raw.isEmpty) {
        return const FastingState(active: false, protocolHours: 16);
      }
      final parts = raw.split('|'); // active|hours|startMs
      return FastingState(
        active: parts.isNotEmpty && parts[0] == '1',
        protocolHours: parts.length > 1 ? int.tryParse(parts[1]) ?? 16 : 16,
        startMs: parts.length > 2 ? int.tryParse(parts[2]) : null,
      );
    } catch (e) {
      debugPrint('[FastingService.load] best-effort skip: $e');
      return const FastingState(active: false, protocolHours: 16);
    }
  }

  Future<void> save(FastingState s) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          await _key(), '${s.active ? 1 : 0}|${s.protocolHours}|${s.startMs ?? ''}');
    } catch (e) {
      debugPrint('[FastingService.save] best-effort skip: $e');
    }
  }

  Future<FastingState> start({required int protocolHours, DateTime? startAt}) async {
    final s = FastingState(
      active: true,
      protocolHours: protocolHours,
      startMs: (startAt ?? DateTime.now()).millisecondsSinceEpoch,
    );
    await save(s);
    return s;
  }

  /// Patch the window and/or start time of the CURRENT state without
  /// toggling it — used by the fasting sheet so protocol/start edits apply
  /// immediately even mid-fast (prototype setFastWindow/onFastStart: the
  /// ring retargets live instead of requiring a fresh start).
  Future<FastingState> update({int? protocolHours, DateTime? startAt}) async {
    final cur = await load();
    final s = FastingState(
      active: cur.active,
      protocolHours: protocolHours ?? cur.protocolHours,
      startMs: startAt?.millisecondsSinceEpoch ?? cur.startMs,
    );
    await save(s);
    return s;
  }

  Future<FastingState> end() async {
    final cur = await load();
    final s = FastingState(active: false, protocolHours: cur.protocolHours);
    await save(s);
    return s;
  }
}
