import 'package:flutter/material.dart';

import '_crash_reporter.dart';
import 'activity_calendar_store.dart';
import 'activity_service.dart';
import 'app_data_cache.dart';
import 'offline_sync_coordinator.dart';
import 'pending_activity_queue.dart';
import '../models/activity_kind.dart';
import '../screens/workouts/cardio_recap_screen.dart';
import '../screens/workouts/xp_complete_screen.dart';

/// Shared Finish → Recap → XP loop for all cardio entry points.
class CardioFlowHelper {
  CardioFlowHelper._();

  static Future<CardioCompleteResult?> persistAndAward({
    required String mode,
    required double meters,
    required int elapsedSeconds,
    String source = 'app',
    // Canonical recorded route ({lat,lng,t}) + session window. When present,
    // the session is persisted to POST /v1/activities BEFORE the XP award —
    // and durably queued for replay if the save fails (route is never lost).
    List<Map<String, dynamic>>? routePoints,
    DateTime? startedAt,
    DateTime? endedAt,
    // Stable client id (e.g. the session's start epoch ms) — makes the local
    // calendar mirror idempotent, so a save Retry replaces instead of
    // double-counting the session in the weekly cardio card.
    String? sessionId,
  }) async {
    if (elapsedSeconds < 30 && meters < 50) return null;
    final store = ActivityCalendarStore();
    final day = AppDataCache.localDayYmd();
    final kind = mode == 'bike'
        ? ActivityKind.cycle
        : mode == 'walk'
            ? ActivityKind.walk
            : ActivityKind.run;
    await store.addManualSession(
      day,
      ManualCardioSession(
        id: sessionId,
        kind: kind,
        distanceKm: meters > 0 ? meters / 1000 : null,
        durationMin: (elapsedSeconds / 60).ceil().clamp(1, 999),
      ),
    );

    // ── Persist the GPS route (canonical /v1/activities) ────────────────────
    var xpDistance = meters;
    var xpDuration = elapsedSeconds;
    var queuedOffline = false;
    if (routePoints != null && routePoints.length >= 2 && startedAt != null) {
      final end = endedAt ?? startedAt.add(Duration(seconds: elapsedSeconds));
      try {
        final saved = await ActivityService().saveActivity(
          routePoints: routePoints,
          distanceM: meters,
          durationS: elapsedSeconds,
          startedAt: startedAt,
          endedAt: end,
        );
        // Server recomputes from the polyline (anti-cheat) — award XP on the
        // server-trusted metrics, not the local estimate.
        if ((saved.distanceM ?? 0) > 0) xpDistance = saved.distanceM!;
        if ((saved.durationS ?? 0) > 0) xpDuration = saved.durationS!;
      } on ActivitySaveException catch (e, st) {
        // 4xx: replaying the identical payload can never succeed — keep the
        // XP flow on local metrics and leave a breadcrumb.
        reportError(e, st, reason: 'cardio-flow:activity-4xx');
      } catch (_) {
        // Offline / 5xx — durable-store the full session for later replay.
        await OfflineSyncCoordinator.instance.enqueueActivity(
          PendingActivityEntry(
            clientActivityId:
                'act_${DateTime.now().microsecondsSinceEpoch}',
            mode: mode,
            routePoints: routePoints,
            distanceM: meters,
            durationS: elapsedSeconds,
            startedAtIso: startedAt.toUtc().toIso8601String(),
            endedAtIso: end.toUtc().toIso8601String(),
          ),
        );
        queuedOffline = true;
      }
    }

    try {
      return await ActivityService().completeCardio(
        // The XP endpoint may only recognize run/bike; score a walk as a run so
        // XP isn't lost (the local calendar above still records it as a walk).
        mode: mode == 'walk' ? 'run' : mode,
        distanceM: xpDistance,
        durationSec: xpDuration.clamp(1, 86400),
        source: source,
      );
    } catch (_) {
      if (queuedOffline) {
        // Offline end-to-end: the route is stored and the queue awards XP on
        // replay — finish the flow quietly instead of surfacing an error.
        return null;
      }
      rethrow;
    }
  }

  static String recapCaption(String mode, double meters, int elapsedSeconds) {
    final km = meters / 1000;
    final min = elapsedSeconds ~/ 60;
    final label = mode == 'bike' ? 'Ride' : mode == 'walk' ? 'Walk' : 'Run';
    if (km >= 0.05) {
      return '$label · ${km.toStringAsFixed(2)} km · $min min';
    }
    return '$label · $min min';
  }

  static Future<void> showRecapAndXp({
    required BuildContext context,
    required String mode,
    required double meters,
    required int elapsedSeconds,
    required String source,
    List<Map<String, dynamic>>? routePoints,
    DateTime? startedAt,
    DateTime? endedAt,
    VoidCallback? afterDone,
  }) async {
    if (elapsedSeconds < 30 && meters < 50) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session too short to save (need 30s or 50m).')),
        );
      }
      // The caller already stopped GPS before invoking this flow — finish it
      // (pop the live screen) instead of stranding a dead tracker whose
      // timer keeps ticking.
      afterDone?.call();
      return;
    }

    // Stable per-session id: every Save retry from this recap reuses it, so
    // the calendar mirror replaces instead of duplicating.
    final sessionId =
        (startedAt ?? DateTime.now()).millisecondsSinceEpoch.toString();

    CardioCompleteResult? xpResult;
    try {
      xpResult = await Navigator.of(context).push<CardioCompleteResult?>(
        MaterialPageRoute<CardioCompleteResult?>(
          builder: (ctx) => CardioRecapScreen(
            mode: mode,
            elapsedSeconds: elapsedSeconds,
            meters: meters,
            onSave: () => persistAndAward(
              mode: mode,
              meters: meters,
              elapsedSeconds: elapsedSeconds,
              source: source,
              routePoints: routePoints,
              startedAt: startedAt,
              endedAt: endedAt,
              sessionId: sessionId,
            ),
            onDiscard: () => Navigator.of(ctx).pop(),
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
      return;
    }

    if (!context.mounted) return;
    if (xpResult != null) {
      final caption = recapCaption(mode, meters, elapsedSeconds);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (ctx) => XpCompleteScreen(
            xpGain: xpResult!.xpGain,
            gameXp: xpResult.gameXp,
            xpBreakdown: xpResult.breakdown,
            title: 'Cardio complete!',
            // No "(masters bonus applied)" claim — the backend folds the age
            // bonus into pct silently and doesn't return the multiplier, so
            // the client can't know whether one applied (most users get none).
            subtitle: xpResult.pctOfWr > 0
                ? '${xpResult.pctOfWr}% vs world-class pace'
                : null,
            shareCaption: caption,
            showRanks: false,
            onDone: () => Navigator.of(ctx).pop(),
          ),
        ),
      );
    }
    afterDone?.call();
  }
}
