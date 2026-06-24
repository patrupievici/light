import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'activity_calendar_store.dart';

/// Local reminders for planned workouts (calendar pending items).
class PlannedWorkoutReminderService {
  PlannedWorkoutReminderService._();
  static final PlannedWorkoutReminderService instance = PlannedWorkoutReminderService._();

  static const _channelId = 'zvelt_planned_workouts';
  static const _channelName = 'Planned workouts';
  static const _baseId = 931000;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized || kIsWeb) return;
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

  int _notificationIdFor(String planId) {
    final hash = planId.hashCode & 0x7FFFFFFF;
    return _baseId + (hash % 900000);
  }

  tz.TZDateTime _scheduleTime(String dayYmd) {
    final parts = dayYmd.split('-');
    if (parts.length != 3) return tz.TZDateTime.now(tz.local).add(const Duration(minutes: 2));
    final y = int.tryParse(parts[0]) ?? 2099;
    final m = int.tryParse(parts[1]) ?? 1;
    final d = int.tryParse(parts[2]) ?? 1;
    var at = tz.TZDateTime(tz.local, y, m, d, 9, 0);
    final now = tz.TZDateTime.now(tz.local);
    if (!at.isAfter(now)) at = now.add(const Duration(minutes: 2));
    return at;
  }

  Future<void> scheduleForPlannedEntries(List<PlannedWorkoutEntry> entries) async {
    if (kIsWeb) return;
    await ensureInitialized();
    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Upcoming planned workouts',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails, macOS: iosDetails);

    for (final e in entries) {
      final id = _notificationIdFor(e.id);
      if (e.completed) {
        await _plugin.cancel(id: id);
        continue;
      }
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: _scheduleTime(e.dayYmd),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'Zvelt plan',
        body: 'Today: ${e.title}. Get ready.',
        payload: e.id,
      );
    }
  }

  Future<void> cancelForPlan(String planId) async {
    if (kIsWeb) return;
    await ensureInitialized();
    await _plugin.cancel(id: _notificationIdFor(planId));
  }
}
