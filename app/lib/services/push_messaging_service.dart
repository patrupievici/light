import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'http_client.dart' show TimeoutResponse;

import '../config/api_config.dart' show v1Base;
import '../config/app_navigator.dart';
import '../config/firebase_options.dart';
import '_crash_reporter.dart';
import 'auth_service.dart' show AuthService;
import 'feed_refresh_notifier.dart';
import 'messages_service.dart';
import '../screens/social/friends_screen.dart';
import '../screens/social/post_detail_screen.dart';
import '../screens/social/direct_chat_screen.dart';

/// FCM: înregistrare token, deep link la tap pe notificare (social).
///
/// Pe **Android**, în foreground FCM nu afișează mereu tray-ul — folosim
/// `flutter_local_notifications` (MIT, pub.dev) pentru același payload ca la push.
/// iOS folosește [FirebaseMessaging.setForegroundNotificationPresentationOptions].
class PushMessagingService {
  PushMessagingService._();
  static final PushMessagingService instance = PushMessagingService._();

  final _auth = AuthService();
  bool _started = false;
  StreamSubscription<String>? _tokenRefreshSub;

  static const _dmChannelId = 'zvelt_dm_foreground';
  static const _dmChannelName = 'Messages';

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _localNotificationsReady = false;

  Future<void> startAfterLogin() async {
    if (_started) return;
    if (!DefaultFirebaseOptions.fcmEnabled) return;
    if (kIsWeb) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }

      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);

      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint('[PushMessagingService] FCM token refreshed -> re-registering');
        final jwt = await _auth.getAccessToken();
        if (jwt == null) {
          debugPrint('[PushMessagingService] skipped re-register: user is logged out');
          return;
        }
        await _registerToken(newToken);
      });

      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _handleOpen(initial));
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        unawaited(_onForegroundFcmMessage(message));
      });

      _started = true;
    } catch (e) {
      debugPrint('[fcm] start failed: $e');
    }
  }

  Future<void> stopOnLogout() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    if (!DefaultFirebaseOptions.fcmEnabled) {
      _started = false;
      return;
    }
    try {
      final token = await FirebaseMessaging.instance.getToken();
      final jwt = await _auth.getAccessToken();
      if (token != null && jwt != null) {
        await http.delete(
          Uri.parse('$v1Base/me/push-token').replace(queryParameters: {'token': token}),
          headers: {'Authorization': 'Bearer $jwt'},
        ).withTimeout();
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e, st) {
      reportError(e, st, reason: 'push:stop-on-logout');
    }
    _started = false;
  }

  Future<void> _registerToken(String token) async {
    final jwt = await _auth.getAccessToken();
    if (jwt == null) return;
    String platform = 'android';
    if (defaultTargetPlatform == TargetPlatform.iOS) platform = 'ios';
    try {
      await http.post(
        Uri.parse('$v1Base/me/push-token'),
        headers: {
          'Authorization': 'Bearer $jwt',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token': token, 'platform': platform}),
      ).withTimeout();
    } catch (e) {
      debugPrint('[fcm] register token failed: $e');
    }
  }

  Future<void> _ensureLocalNotificationsForPush() async {
    if (_localNotificationsReady || kIsWeb) return;
    await _localNotifications.initialize(
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
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _onLocalNotificationTap(response.payload);
      },
    );
    final android = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _dmChannelId,
        _dmChannelName,
        description: 'Direct messages while the app is open',
        importance: Importance.high,
      ),
    );
    await android?.requestNotificationsPermission();
    _localNotificationsReady = true;
  }

  void _onLocalNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      navigateFromPushData(map);
    } catch (e) {
      debugPrint('[fcm] local notification payload: $e');
    }
  }

  Future<void> _onForegroundFcmMessage(RemoteMessage message) async {
    final type = message.data['type']?.toString() ?? '';

    // Hint cached tab pages to refresh themselves. Safe to call for every
    // foreground push — unknown `type`s map to no scopes.
    try {
      FeedRefreshNotifier.instance.bumpForPushType(type);
    } catch (e) {
      debugPrint('[fcm] refresh hint failed: $e');
    }

    if (type != 'dm_message') return;

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _ensureLocalNotificationsForPush();
        await _showDmAndroidForegroundNotification(message);
      } catch (e) {
        debugPrint('[fcm] foreground DM banner: $e');
      }
    }
  }

  Future<void> _showDmAndroidForegroundNotification(RemoteMessage message) async {
    final d = message.data;
    final n = message.notification;
    final dn = d['actorDisplayName']?.toString().trim();
    final un = d['actorUsername']?.toString().trim();
    String title = (n?.title ?? '').trim();
    if (title.isEmpty) {
      if (dn != null && dn.isNotEmpty) {
        title = dn;
      } else if (un != null && un.isNotEmpty) {
        title = '@$un';
      } else {
        title = 'Message';
      }
    }
    String body = (n?.body ?? '').trim();
    if (body.isEmpty) {
      body = d['bodyPreview']?.toString() ?? 'New message';
    }

    final payloadMap = Map<String, dynamic>.from(message.data);
    final payload = jsonEncode(payloadMap);

    final id = _notificationIdForDm(payloadMap);

    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _dmChannelId,
          _dmChannelName,
          channelDescription: 'Direct messages while the app is open',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  int _notificationIdForDm(Map<String, dynamic> d) {
    final nid = d['notificationId']?.toString();
    if (nid != null && nid.isNotEmpty) return nid.hashCode & 0x7FFFFFFF;
    final cid = d['conversationId']?.toString() ?? '';
    final aid = d['actorId']?.toString() ?? '';
    return '$cid|$aid'.hashCode & 0x7FFFFFFF;
  }

  void _handleOpen(RemoteMessage msg) {
    navigateFromPushData(Map<String, dynamic>.from(msg.data));
  }

  /// Folosit la tap pe notificare (FCM sau locală) și poate fi extins.
  void navigateFromPushData(Map<String, dynamic> data) {
    final nav = AppNavigator.key.currentState;
    if (nav == null) return;

    final type = data['type']?.toString() ?? '';

    switch (type) {
      case 'post_like':
      case 'post_comment':
        final postId = data['postId']?.toString();
        if (postId != null && postId.isNotEmpty) {
          nav.push(MaterialPageRoute<void>(builder: (_) => PostDetailScreen(postId: postId)));
        }
        break;
      case 'friend_request':
      case 'friend_accepted':
        nav.push(MaterialPageRoute<void>(builder: (_) => const FriendsScreen()));
        break;
      case 'dm_message':
        final cid = data['conversationId']?.toString();
        final aid = data['actorId']?.toString();
        if (cid != null && cid.isNotEmpty && aid != null && aid.isNotEmpty) {
          // Already reading this conversation? Don't stack a duplicate
          // screen — the in-chat refresh listener shows the new message.
          if (DirectChatScreen.activeConversationId == cid) break;
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => DirectChatScreen(
                conversationId: cid,
                peer: DmPeer(
                  userId: aid,
                  username: data['actorUsername']?.toString(),
                  displayName: data['actorDisplayName']?.toString(),
                ),
              ),
            ),
          );
        }
        break;
    }
  }
}
