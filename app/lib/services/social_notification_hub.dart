import 'package:flutter/foundation.dart';
import '_crash_reporter.dart';
import 'notifications_service.dart';

/// Badge Social + refresh după acțiuni sociale.
class SocialNotificationHub {
  SocialNotificationHub._();
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static final NotificationsService _svc = NotificationsService();

  static Future<void> refresh() async {
    try {
      final n = await _svc.unreadCount();
      unreadCount.value = n;
    } catch (e, st) {
      // Likely offline; record signal for monitoring but don't surface to user.
      reportError(e, st, reason: 'notifications:unread-count');
    }
  }
}
