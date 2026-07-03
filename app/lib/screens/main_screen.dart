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
import 'workouts/quick_launch_sheet.dart';
import 'workouts/workouts_tab.dart';

/// Main shell — **4 destinations + a center Quick-Start action**:
/// Home · Train · ⚡ · Feed · Nutrition.
///
/// The ⚡ center button is not a tab — it opens the Quick-Start workout sheet.
/// Profile is no longer a bottom-nav destination: it opens from the Home avatar
/// (top-left); Settings opens from the Home gear (top-right).
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.onLogout, this.onSessionChanged});

  final Future<void> Function() onLogout;

  /// Fired after signing into a different account from Settings, so AuthGate
  /// can clear per-user caches and remount the shell for the new user.
  final Future<void> Function()? onSessionChanged;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // 0 Home · 1 Train · 2 Feed · 3 Nutrition. (The ⚡ center action is not a tab.)
  static const int _tabCount = 4;
  static const int _feedIndex = 2;

  int _currentIndex = 0;

  /// Lazy IndexedStack: a tab builds the first time it's visited and its
  /// State then lives for the whole session — scroll position and loaded
  /// data survive tab switches. Tabs refresh themselves via pull-to-refresh
  /// and FeedRefreshNotifier bumps.
  final List<bool> _built = [true, false, false, false];
  final List<Widget?> _pageCache = List<Widget?>.filled(_tabCount, null);

  Widget _page(int i) {
    if (!_built[i]) return const SizedBox.shrink();
    return _pageCache[i] ??= _createPage(i);
  }

  Widget _createPage(int i) {
    switch (i) {
      case 0:
        return HomeTab(
          onOpenProfile: _openProfile,
          onOpenNotifications: _openNotifications,
          onOpenSettings: _openSettings,
          onOpenFood: () => _switchTo(3),
          onOpenFeed: () => _switchTo(_feedIndex),
        );
      case 1:
        return const WorkoutsTab();
      case 2:
        return const SocialPlusScreen();
      case 3:
        return const NutritionTab();
      default:
        return const SizedBox.shrink();
    }
  }

  void _switchTo(int i) {
    setState(() {
      _built[i] = true;
      _currentIndex = i;
    });
    if (i == _feedIndex) SocialNotificationHub.refresh();
  }

  /// Profile is no longer a tab — it opens as a pushed route from the Home
  /// avatar. SkeletonProfileTab shows a back arrow when it can pop.
  void _openProfile() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SkeletonProfileTab(onLogout: widget.onLogout),
      ),
    );
  }

  /// Center ⚡ action — the Quick-Start workout sheet, then refresh the Train tab
  /// so a freshly-started/finished workout shows on return.
  Future<void> _startQuickWorkout() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const QuickLaunchSheet(),
      ),
    );
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
        builder: (_) => SettingsScreen(
          onLogout: widget.onLogout,
          onSessionChanged: widget.onSessionChanged,
        ),
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
        'feed' => 2,
        'food' => 3,
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
        onCenterTap: _startQuickWorkout,
        items: const [
          ZveltNavItem(label: 'Home', icon: AppIcons.home),
          ZveltNavItem(label: 'Train', icon: AppIcons.gym),
          ZveltNavItem(label: 'Feed', icon: AppIcons.globe),
          ZveltNavItem(label: 'Nutrition', icon: AppIcons.restaurant),
        ],
      ),
    );
  }
}
