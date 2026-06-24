import 'package:flutter/foundation.dart';

/// Categories of data that may need refreshing in response to push
/// notifications or other out-of-band events.
enum RefreshScope {
  /// Social feed / posts / stories / challenges.
  feed,

  /// In-app notification inbox + unread badge.
  notifications,

  /// Friend circle, friend requests, friend activity.
  circle,

  /// Profile screen (followers, achievements, etc.).
  profile,

  /// Home dashboard (workouts, streaks, recovery).
  home,

  /// Direct-message threads. Any open [DirectChatScreen] should re-fetch
  /// its message list. The notifier is global per app — every open thread
  /// will refresh on bump, which is wasteful but harmless (each thread
  /// makes its own cheap REST call).
  dm,
}

/// Lightweight in-memory event bus that lets cached tab pages know when
/// they should re-fetch their data. Each scope owns a [ValueNotifier<int>]
/// whose value increments every time something interesting happens. Tabs
/// subscribe in `initState` and call their existing pull-to-refresh
/// `_load()` method when the value changes.
///
/// This is intentionally tiny and process-local: no streams, no packages,
/// no replay buffer. A scope notifier is reused across the app lifetime.
class FeedRefreshNotifier {
  FeedRefreshNotifier._();
  static final FeedRefreshNotifier instance = FeedRefreshNotifier._();

  final Map<RefreshScope, ValueNotifier<int>> _notifiers = {
    for (final s in RefreshScope.values) s: ValueNotifier<int>(0),
  };

  /// Returns the long-lived notifier for [scope]. Subscribe with
  /// `notifier(scope).addListener(cb)` in `initState` and remove the
  /// listener in `dispose`.
  ValueNotifier<int> notifier(RefreshScope scope) => _notifiers[scope]!;

  /// Increments the notifier for [scope], waking up any subscribers.
  void bump(RefreshScope scope) {
    final n = _notifiers[scope]!;
    n.value = n.value + 1;
  }

  /// Maps a push-notification `type` payload field to the scopes whose
  /// cached pages should reload. Unknown types return an empty list so
  /// callers can safely iterate.
  List<RefreshScope> scopesForPushType(String? type) {
    switch (type) {
      case 'post_like':
      case 'post_comment':
        return const [RefreshScope.feed, RefreshScope.notifications];
      case 'friend_request':
      case 'friend_accepted':
        return const [
          RefreshScope.circle,
          RefreshScope.notifications,
          RefreshScope.feed,
        ];
      case 'dm_message':
      case 'dm':
        return const [RefreshScope.dm, RefreshScope.notifications];
      case 'achievement_unlocked':
      case 'rank_up':
        return const [RefreshScope.profile, RefreshScope.notifications];
      default:
        return const [];
    }
  }

  /// Convenience: bump every scope implied by a push payload `type`.
  void bumpForPushType(String? type) {
    for (final scope in scopesForPushType(type)) {
      bump(scope);
    }
  }
}
