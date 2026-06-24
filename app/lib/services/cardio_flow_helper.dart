import 'package:flutter/material.dart';

import 'activity_calendar_store.dart';
import 'activity_service.dart';
import 'app_data_cache.dart';
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
  }) async {
    if (elapsedSeconds < 30 && meters < 50) return null;
    final store = ActivityCalendarStore();
    final day = AppDataCache.localDayYmd();
    final kind = mode == 'bike' ? ActivityKind.cycle : ActivityKind.run;
    await store.addManualSession(
      day,
      ManualCardioSession(
        kind: kind,
        distanceKm: meters > 0 ? meters / 1000 : null,
        durationMin: (elapsedSeconds / 60).ceil().clamp(1, 999),
      ),
    );
    return ActivityService().completeCardio(
      mode: mode,
      distanceM: meters,
      durationSec: elapsedSeconds,
      source: source,
    );
  }

  static String recapCaption(String mode, double meters, int elapsedSeconds) {
    final km = meters / 1000;
    final min = elapsedSeconds ~/ 60;
    final label = mode == 'bike' ? 'Ride' : 'Run';
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
    VoidCallback? afterDone,
  }) async {
    if (elapsedSeconds < 30 && meters < 50) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session too short to save (need 30s or 50m).')),
        );
      }
      return;
    }

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
            subtitle: xpResult.pctOfWr > 0
                ? '${xpResult.pctOfWr}% vs world-class pace (masters bonus applied)'
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
