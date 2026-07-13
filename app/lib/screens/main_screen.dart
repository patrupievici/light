import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../services/push_messaging_service.dart';
import '../services/social_notification_hub.dart';
import '../services/settings_store.dart';
import '../theme/zvelt_tokens.dart';
import '../widgets/zvelt_main_nav_bar.dart';
import 'ai/ai_chat_screen.dart';
import 'home/home_tab.dart';
import 'nutrition/nutrition_tab.dart';
import 'settings/settings_screen.dart';
import 'profile/profile_tab.dart';
import 'social/notifications_screen.dart';
import 'social/feed_tab.dart';
import '../screens/plan/plan_tab.dart' show PlanTab;

/// Main shell — **4 destinations + a center AI action** (Claude Design handoff):
/// Home · Plan · ✦ AI · Feed · Nutrition.
///
/// The ✦ center button is not a tab — it opens the AI Coach.
/// Profile is no longer a bottom-nav destination: it opens from the Home avatar
/// (top-left); Settings opens from the Home gear (top-right).
class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // 0 Home · 1 Plan · 2 Feed · 3 Nutrition. (The ✦ AI center action is not a tab.)
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
        return const PlanTab();
      case 2:
        return const FeedTab();
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
        builder: (_) => ProfileTab(onLogout: widget.onLogout),
      ),
    );
  }

  /// Center ✦ action — open the AI Coach (handoff: the center button is AI,
  /// not the quick-workout launcher).
  Future<void> _openAiCoach() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const AiChatScreen(),
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
        onCenterTap: _openAiCoach,
        centerIcon: AppIcons.sparkles,
        centerLabel: 'AI Coach',
        items: const [
          ZveltNavItem(label: 'Home', icon: AppIcons.home),
          ZveltNavItem(label: 'Plan', icon: AppIcons.calendar_check),
          ZveltNavItem(label: 'Feed', icon: AppIcons.globe),
          ZveltNavItem(label: 'Nutrition', icon: AppIcons.leaf),
        ],
      ),
    );
  }
}
