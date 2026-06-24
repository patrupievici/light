import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../services/push_messaging_service.dart';
import '../services/social_notification_hub.dart';
import '../services/settings_store.dart';
import '../theme/zvelt_tokens.dart';
import '../widgets/zvelt_main_nav_bar.dart';
import 'home/home_tab.dart';
import 'nutrition/nutrition_tab.dart';
import 'settings/settings_screen.dart';
import 'skeleton/skeleton_profile_tab.dart';
import 'social/notifications_screen.dart';
import 'social/social_plus_screen.dart';
import 'workouts/workouts_tab.dart';

/// Main shell — **5-tab light layout** (redesign brief §3, §20):
/// Home · Train · Food · Feed · Profile.
///
/// Start Workout is no longer a floating action; it lives as the dominant hero
/// on Home and as the primary action on the Train tab. AI is a contextual
/// button inside Train/Food, never a tab.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const int _tabCount = 5;

  int _currentIndex = 0;

  /// Lazy IndexedStack: a tab builds the first time it's visited and its
  /// State then lives for the whole session — scroll position and loaded
  /// data survive tab switches. Tabs refresh themselves via pull-to-refresh
  /// and FeedRefreshNotifier bumps.
  final List<bool> _built = [true, false, false, false, false];
  final List<Widget?> _pageCache = List<Widget?>.filled(_tabCount, null);

  Widget _page(int i) {
    if (!_built[i]) return const SizedBox.shrink();
    return _pageCache[i] ??= _createPage(i);
  }

  Widget _createPage(int i) {
    switch (i) {
      case 0:
        return HomeTab(
          onOpenProfile: () => _switchTo(4),
          onOpenNotifications: _openNotifications,
          onOpenSettings: _openSettings,
          onOpenFood: () => _switchTo(2),
          onOpenFeed: () => _switchTo(3),
        );
      case 1:
        return const WorkoutsTab();
      case 2:
        return const NutritionTab();
      case 3:
        return const SocialPlusScreen();
      case 4:
        return SkeletonProfileTab(onLogout: widget.onLogout);
      default:
        return const SizedBox.shrink();
    }
  }

  void _switchTo(int i) {
    setState(() {
      _built[i] = true;
      _currentIndex = i;
    });
    if (i == 3) SocialNotificationHub.refresh();
  }

  void _openNotifications() {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        )
        .then((_) => SocialNotificationHub.refresh());
  }

  void _openSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(onLogout: widget.onLogout),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    readStartScreen().then((value) {
      if (!mounted) return;
      final index = switch (value) {
        'train' => 1,
        'food' => 2,
        'feed' => 3,
        _ => 0, // 'home' (and legacy 'progress') land on Home
      };
      setState(() {
        _currentIndex = index;
        _built[index] = true;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SocialNotificationHub.refresh();
      PushMessagingService.instance.startAfterLogin();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: IndexedStack(
        index: _currentIndex,
        children: [for (var i = 0; i < _tabCount; i++) _page(i)],
      ),
      bottomNavigationBar: ZveltMainNavBar(
        currentIndex: _currentIndex,
        onTap: _switchTo,
        items: const [
          ZveltNavItem(label: 'Home', icon: AppIcons.home),
          ZveltNavItem(label: 'Train', icon: AppIcons.gym),
          ZveltNavItem(label: 'Food', icon: AppIcons.restaurant),
          ZveltNavItem(label: 'Feed', icon: AppIcons.globe),
          ZveltNavItem(label: 'Profile', icon: AppIcons.user),
        ],
      ),
    );
  }
}
