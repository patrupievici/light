import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Syncs home-screen widget data for all widgets:
///   Android: streak small/medium, XP small/medium, Day Streak, Chain,
///            Recovery small/medium, Challenge small/large
///   iOS:     ZveltStreakWidget, ZveltXpWidget, ZveltXpMediumWidget,
///            ZveltDayStreakWidget, ZveltChainWidget,
///            ZveltRecoverySmallWidget, ZveltRecoveryMediumWidget,
///            ZveltChallengeSmallWidget, ZveltChallengeLargeWidget
class TodayHomeWidgetService {
  TodayHomeWidgetService._();

  static const String androidSmallProvider =
      'com.lunaoscar.zvelt.widget.TodayWidgetSmallProvider';
  static const String androidMediumProvider =
      'com.lunaoscar.zvelt.widget.TodayWidgetMediumProvider';
  static const String androidStreakProvider =
      'com.lunaoscar.zvelt.widget.StreakWidgetProvider';
  static const String androidXpProvider =
      'com.lunaoscar.zvelt.widget.XpWidgetProvider';
  static const String androidXpMediumProvider =
      'com.lunaoscar.zvelt.widget.XpMediumWidgetProvider';
  static const String androidDayStreakProvider =
      'com.lunaoscar.zvelt.widget.DayStreakWidgetProvider';
  static const String androidChainProvider =
      'com.lunaoscar.zvelt.widget.ChainWidgetProvider';
  static const String androidRecoverySmallProvider =
      'com.lunaoscar.zvelt.widget.RecoveryWidgetSmallProvider';
  static const String androidRecoveryMediumProvider =
      'com.lunaoscar.zvelt.widget.RecoveryWidgetMediumProvider';
  static const String androidChallengeSmallProvider =
      'com.lunaoscar.zvelt.widget.ChallengeWidgetSmallProvider';
  static const String androidChallengeLargeProvider =
      'com.lunaoscar.zvelt.widget.ChallengeWidgetLargeProvider';
  static const String _appGroupId = 'group.com.lunaoscar.zvelt';

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Syncs all widget data and triggers a redraw on all installed widgets.
  static Future<void> sync({
    required int streak,
    required bool streakAtRisk,
    required int totalWorkouts,
    int? daysSinceLastWorkout,
    int xpCurrent = 0,
    int xpGoal = 3000,
    int xpPercent = 0,
    int kcal = 0,
    int steps = 0,
    int activeMin = 0,
    List<int> weekXpPercents = const [],
    int todayWeekDay = 0,
    List<bool> weekCompletion = const [],
    String lastWorkoutName = '',
    String lastWorkoutTimeLabel = '',
    int? lastWorkoutDurationMin,
    int recoveryScore = 0,
    String recoveryStatus = '',
    String recoveryMessage = '',
    String recoveryRecommendationCta = '',
    String recoveryAiRec = '',
    String recoverySleepLabel = '',
    String recoverySleepRating = '',
    int recoverySleepBar = 0,
    String recoveryStressValue = '',
    String recoveryStressRating = '',
    int recoveryStressBar = 0,
    String recoveryHrvLabel = '',
    String recoveryHrvRating = '',
    int recoveryHrvBar = 0,
    String packChallengeName = '',
    String packDaysLeftLabel = '',
    int packMyRank = 0,
    String packGapLabel = '',
    String packGapToLabel = '',
    String packCta = '',
    // Format: "Name:kcal:isMe(0|1)" comma-separated, e.g. "Mihai:1870:0,Alex:1640:0,You:1520:1"
    String packLeaderboard = '',
  }) async {
    if (!_supported) return;
    try {
      if (Platform.isIOS) {
        await HomeWidget.setAppGroupId(_appGroupId);
      }

      // ── Streak / today widgets ──────────────────────────────────────────
      await HomeWidget.saveWidgetData<String>('today_streak', streak.toString());
      await HomeWidget.saveWidgetData<bool>('today_at_risk', streakAtRisk);
      await HomeWidget.saveWidgetData<String>('today_workouts_total', totalWorkouts.toString());
      await HomeWidget.saveWidgetData<String>(
        'today_gap_days',
        daysSinceLastWorkout == null ? '' : '$daysSinceLastWorkout',
      );

      // ── XP small widget ─────────────────────────────────────────────────
      await HomeWidget.saveWidgetData<String>('today_xp_percent', xpPercent.toString());
      await HomeWidget.saveWidgetData<String>('today_kcal', kcal.toString());

      // ── XP medium widget (Daily Progress) ───────────────────────────────
      await HomeWidget.saveWidgetData<String>('today_xp_current', xpCurrent.toString());
      await HomeWidget.saveWidgetData<String>('today_xp_goal', xpGoal.toString());
      await HomeWidget.saveWidgetData<String>('today_steps', steps.toString());
      await HomeWidget.saveWidgetData<String>('today_active_min', activeMin.toString());
      await HomeWidget.saveWidgetData<String>('today_week_day', todayWeekDay.toString());
      final weekStr = weekXpPercents.isEmpty
          ? '0,0,0,0,0,0,0'
          : weekXpPercents.take(7).join(',');
      await HomeWidget.saveWidgetData<String>('week_xp_percents', weekStr);

      // ── Chain / Day Streak widgets ───────────────────────────────────────
      final completionStr = weekCompletion.isEmpty
          ? '0,0,0,0,0,0,0'
          : weekCompletion.take(7).map((b) => b ? '1' : '0').join(',');
      await HomeWidget.saveWidgetData<String>('week_completion', completionStr);
      await HomeWidget.saveWidgetData<String>('last_workout_name', lastWorkoutName);
      await HomeWidget.saveWidgetData<String>('last_workout_time_label', lastWorkoutTimeLabel);
      await HomeWidget.saveWidgetData<String>(
        'last_workout_duration_min',
        lastWorkoutDurationMin == null ? '' : '$lastWorkoutDurationMin',
      );

      // ── Recovery widgets ────────────────────────────────────────────────
      await HomeWidget.saveWidgetData<String>('recovery_score', recoveryScore.toString());
      await HomeWidget.saveWidgetData<String>('recovery_status', recoveryStatus);
      await HomeWidget.saveWidgetData<String>('recovery_message', recoveryMessage);
      await HomeWidget.saveWidgetData<String>('recovery_recommendation_cta', recoveryRecommendationCta);
      await HomeWidget.saveWidgetData<String>('recovery_ai_rec', recoveryAiRec);
      await HomeWidget.saveWidgetData<String>('recovery_sleep_label', recoverySleepLabel);
      await HomeWidget.saveWidgetData<String>('recovery_sleep_rating', recoverySleepRating);
      await HomeWidget.saveWidgetData<String>('recovery_sleep_bar', recoverySleepBar.toString());
      await HomeWidget.saveWidgetData<String>('recovery_stress_value', recoveryStressValue);
      await HomeWidget.saveWidgetData<String>('recovery_stress_rating', recoveryStressRating);
      await HomeWidget.saveWidgetData<String>('recovery_stress_bar', recoveryStressBar.toString());
      await HomeWidget.saveWidgetData<String>('recovery_hrv_label', recoveryHrvLabel);
      await HomeWidget.saveWidgetData<String>('recovery_hrv_rating', recoveryHrvRating);
      await HomeWidget.saveWidgetData<String>('recovery_hrv_bar', recoveryHrvBar.toString());

      // ── Pack Challenge widgets ───────────────────────────────────────────
      await HomeWidget.saveWidgetData<String>('pack_challenge_name', packChallengeName);
      await HomeWidget.saveWidgetData<String>('pack_days_left_label', packDaysLeftLabel);
      await HomeWidget.saveWidgetData<String>('pack_my_rank', packMyRank.toString());
      await HomeWidget.saveWidgetData<String>('pack_gap_label', packGapLabel);
      await HomeWidget.saveWidgetData<String>('pack_gap_to_label', packGapToLabel);
      await HomeWidget.saveWidgetData<String>('pack_cta', packCta);
      await HomeWidget.saveWidgetData<String>('pack_leaderboard', packLeaderboard);

      // ── Trigger redraws ─────────────────────────────────────────────────
      if (Platform.isAndroid) {
        await HomeWidget.updateWidget(qualifiedAndroidName: androidSmallProvider);
        await HomeWidget.updateWidget(qualifiedAndroidName: androidMediumProvider);
        await HomeWidget.updateWidget(qualifiedAndroidName: androidStreakProvider);
        await HomeWidget.updateWidget(qualifiedAndroidName: androidXpProvider);
        await HomeWidget.updateWidget(qualifiedAndroidName: androidXpMediumProvider);
        await HomeWidget.updateWidget(qualifiedAndroidName: androidDayStreakProvider);
        await HomeWidget.updateWidget(qualifiedAndroidName: androidChainProvider);
        await HomeWidget.updateWidget(qualifiedAndroidName: androidRecoverySmallProvider);
        await HomeWidget.updateWidget(qualifiedAndroidName: androidRecoveryMediumProvider);
        await HomeWidget.updateWidget(qualifiedAndroidName: androidChallengeSmallProvider);
        await HomeWidget.updateWidget(qualifiedAndroidName: androidChallengeLargeProvider);
      } else if (Platform.isIOS) {
        await HomeWidget.updateWidget(iOSName: 'ZveltStreakWidget');
        await HomeWidget.updateWidget(iOSName: 'ZveltXpWidget');
        await HomeWidget.updateWidget(iOSName: 'ZveltXpMediumWidget');
        await HomeWidget.updateWidget(iOSName: 'ZveltDayStreakWidget');
        await HomeWidget.updateWidget(iOSName: 'ZveltChainWidget');
        await HomeWidget.updateWidget(iOSName: 'ZveltRecoverySmallWidget');
        await HomeWidget.updateWidget(iOSName: 'ZveltRecoveryMediumWidget');
        await HomeWidget.updateWidget(iOSName: 'ZveltChallengeSmallWidget');
        await HomeWidget.updateWidget(iOSName: 'ZveltChallengeLargeWidget');
      }
    } catch (e, st) {
      debugPrint('TodayHomeWidgetService.sync failed: $e\n$st');
    }
  }
}
