import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

/// Memento zilnic local (retenție) — fără FCM; utilizatorul poate alege ora.
class RetentionReminderService {
  RetentionReminderService._();
  static final RetentionReminderService instance = RetentionReminderService._();

  static const _prefsEnabled = 'zvelt_retention_daily_enabled';
  static const _prefsHour = 'zvelt_retention_daily_hour';
  static const _prefsMinute = 'zvelt_retention_daily_minute';
  static const _notifId = 90401;
  static const _channelId = 'zvelt_workout_reminders';
  static const _channelName = 'Workout reminders';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      return;
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_prefsEnabled) ?? false;
  }

  Future<(int hour, int minute)> getTime() async {
    final p = await SharedPreferences.getInstance();
    final h = p.getInt(_prefsHour) ?? 17;
    final m = p.getInt(_prefsMinute) ?? 0;
    return (h.clamp(0, 23), m.clamp(0, 59));
  }

  /// Cere permisiune (Android 13+ / iOS) și programează notificarea zilnică.
  Future<bool> setEnabled(bool enabled, {int? hour, int? minute}) async {
    if (kIsWeb) return false;
    await ensureInitialized();
    final p = await SharedPreferences.getInstance();
    if (!enabled) {
      await _plugin.cancel(id: _notifId);
      await p.setBool(_prefsEnabled, false);
      return true;
    }

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      await iosImpl.requestPermissions(alert: true, badge: true, sound: true);
    }

    final allowedAndroid = await androidImpl?.areNotificationsEnabled();
    if (allowedAndroid == false) {
      await p.setBool(_prefsEnabled, false);
      return false;
    }

    final (h, min) = hour != null && minute != null
        ? (hour.clamp(0, 23), minute.clamp(0, 59))
        : await getTime();
    await p.setInt(_prefsHour, h);
    await p.setInt(_prefsMinute, min);
    await p.setBool(_prefsEnabled, true);

    await _scheduleDaily(h, min);
    return true;
  }

  Future<void> updateTime(int hour, int minute) async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_prefsEnabled) != true) return;
    await p.setInt(_prefsHour, hour.clamp(0, 23));
    await p.setInt(_prefsMinute, minute.clamp(0, 59));
    if (kIsWeb) return;
    await ensureInitialized();
    await _scheduleDaily(p.getInt(_prefsHour)!, p.getInt(_prefsMinute)!);
  }

  /// Re-aplică programarea după login (timezone deja setat în main).
  Future<void> rescheduleIfEnabled() async {
    if (kIsWeb) return;
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_prefsEnabled) != true) return;
    await ensureInitialized();
    await _scheduleDaily(p.getInt(_prefsHour) ?? 17, p.getInt(_prefsMinute) ?? 0);
  }

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await ensureInitialized();
    await _plugin.cancel(id: _notifId);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefsEnabled, false);
  }

  static const _streakAtRiskId = 90402;
  static const _prefsStreakAtRiskDate = 'zvelt_streak_at_risk_date';

  /// Fires a one-shot "streak at risk" notification today (if not already sent today).
  Future<void> scheduleStreakAtRiskOnce({required int streak}) async {
    if (kIsWeb) return;
    await ensureInitialized();

    final today = DateTime.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final p = await SharedPreferences.getInstance();
    if (p.getString(_prefsStreakAtRiskDate) == todayKey) return; // already sent today
    await p.setString(_prefsStreakAtRiskDate, todayKey);

    // Schedule for ~8 PM local time today (or in 2 h if already past 8 PM)
    final now = tz.TZDateTime.now(tz.local);
    var target = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20, 0);
    if (!target.isAfter(now)) {
      target = now.add(const Duration(hours: 2));
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Streak at risk alert',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails, macOS: iosDetails);

    await _plugin.zonedSchedule(
      id: _streakAtRiskId,
      scheduledDate: target,
      notificationDetails: details,
      // INEXACT: exactAllowWhileIdle throws on Android 13+ without the
      // SCHEDULE_EXACT_ALARM permission. A streak nudge doesn't need exactness.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: '🔥 Streak at risk!',
      body: streak > 1
          ? 'Your $streak-day streak breaks tonight. Log a workout to keep it alive!'
          : 'Don\'t break your streak! Log a quick session before midnight.',
    );
  }

  Future<void> _scheduleDaily(int hour, int minute) async {
    await _plugin.cancel(id: _notifId);
    final scheduled = _nextInstanceOf(hour, minute);

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Daily nudge to open ZVELT and train',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails, macOS: iosDetails);

    await _plugin.zonedSchedule(
      id: _notifId,
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'ZVELT',
      body: 'Time for a quick session? Open the app and keep your momentum.',
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var s = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!s.isAfter(now)) {
      s = s.add(const Duration(days: 1));
    }
    return s;
  }
}
