import 'package:zvelt_app/theme/app_icons.dart';
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/api_config.dart';
import '../../services/app_data_cache.dart';
import '../../services/auth_service.dart';
import '../../services/messages_service.dart';
import '../../services/moderation_service.dart';
import '../../services/profile_service.dart';
import '../../services/settings_store.dart';
import '../../services/social_feed_service.dart';
import '../../services/social_notification_hub.dart';
import '../../theme/zvelt_theme_notifier.dart';
import '../../theme/zvelt_tokens.dart';
import '../social/blocked_users_screen.dart';
import '../social/bookmarks_screen.dart';
import '../social/conversations_screen.dart';
import 'account_settings_screens.dart';
import 'language_screen.dart';
import 'preference_settings_screens.dart';
import 'resource_settings_screens.dart';
import 'settings_kit.dart';
import 'shortcuts_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.onLogout,
    this.preview = false,
  });

  final Future<void> Function() onLogout;
  final bool preview;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final _auth = AuthService();
  final _profile = ProfileService();

  String _physical = 'BW \u00b7 height \u00b7 sex';
  String _goal = 'Strength \u00b7 6 days';
  String _units = 'Metric';
  String _visibility = 'Friends only';
  bool _notifications = true;
  bool _diagnostics = false;
  int _shortcutCount = 3;
  int _blockedCount = 0;
  int _bookmarkCount = 0;
  int _conversationCount = 0;
  int _gettingStartedCount = 0;
  DateTime? _cloudLastSync;
  String _version = 'v1.0.0 - build 3';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.preview) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadCounts();
  }

  Future<void> _load() async {
    await Future.wait(
        [_loadProfile(), _loadPrefs(), _loadAppInfo(), _loadCounts()]);
  }

  Future<void> _loadProfile() async {
    final me = await _profile.getMe();
    final p = me?['profile'] as Map<String, dynamic>?;
    final tp = me?['trainingProfile'] as Map<String, dynamic>?;
    if (!mounted) return;
    final bw = (p?['bodyweightKg'] as num?)?.toDouble();
    final height = (p?['heightCm'] as num?)?.toDouble();
    final sex = p?['sex']?.toString();
    final parts = <String>[
      if (bw != null) '${bw.toStringAsFixed(bw % 1 == 0 ? 0 : 1)} kg',
      if (height != null) '${height.round()} cm',
      if (sex != null && sex.isNotEmpty) sex,
    ];
    setState(() {
      if (parts.isNotEmpty) _physical = parts.join(' \u00b7 ');
      _goal =
          '${_goalLabel(tp?['primaryGoal']?.toString())} \u00b7 ${(tp?['daysPerWeek'] as num?)?.toInt() ?? 6} days';
      _units = p?['unitSystem'] == 'imperial' ? 'Imperial' : 'Metric';
      _visibility = switch (p?['privacyDefault']) {
        'public' => 'Public',
        'private' => 'Private',
        _ => 'Friends only',
      };
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    const shortcutKeys = [
      SettingsKeys.scEmpty,
      SettingsKeys.scAi,
      SettingsKeys.scRun,
      SettingsKeys.scMeal,
      SettingsKeys.scRace,
      SettingsKeys.scPhoto,
    ];
    const setupKeys = [
      SettingsKeys.gsProfile,
      SettingsKeys.gsData,
      SettingsKeys.gsDevice,
      SettingsKeys.gsWorkout,
      SettingsKeys.gsFriends,
    ];
    final rawLast = prefs.getString(SettingsKeys.cloudLastSync);
    if (!mounted) return;
    setState(() {
      _notifications = prefs.getBool(SettingsKeys.notifMaster) ?? true;
      _diagnostics = prefs.getBool(SettingsKeys.diagnostics) ?? false;
      _units =
          (prefs.getString(SettingsKeys.unitSystem) ?? _units.toLowerCase()) ==
                  'imperial'
              ? 'Imperial'
              : 'Metric';
      _shortcutCount = shortcutKeys.indexed.where((entry) {
        final defaultsOn = entry.$1 < 3;
        return prefs.getBool(entry.$2) ?? defaultsOn;
      }).length;
      _gettingStartedCount =
          setupKeys.where((key) => prefs.getBool(key) ?? false).length;
      _cloudLastSync = rawLast == null ? null : DateTime.tryParse(rawLast);
    });
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(
            () => _version = 'v${info.version} - build ${info.buildNumber}');
      }
    } catch (_) {}
  }

  Future<void> _loadCounts() async {
    final results = await Future.wait<Object?>([
      _safeResult(ModerationService().listBlocked(), const <Object>[]),
      _safeResult(SocialFeedService().getBookmarks(limit: 20), null),
      _safeResult(MessagesService().listConversations(), const <Object>[]),
    ]);
    if (!mounted) return;
    final bookmarks = results[1];
    setState(() {
      _blockedCount = (results[0] as List).length;
      _bookmarkCount = bookmarks is SocialFeedPage ? bookmarks.posts.length : 0;
      _conversationCount = (results[2] as List).length;
    });
  }

  Future<Object?> _safeResult(Future<Object?> future, Object? fallback) async {
    try {
      return await future;
    } catch (_) {
      return fallback;
    }
  }

  String _goalLabel(String? value) => switch (value) {
        'hypertrophy' => 'Hypertrophy',
        'maintenance' => 'Stay healthy',
        'fat_loss' => 'Fat loss',
        'calisthenics' => 'Calisthenics',
        _ => 'Strength',
      };

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _load();
  }

  String get _themeLabel => switch (ZveltThemeNotifier.mode.value) {
        ThemeMode.light => 'Light',
        ThemeMode.system => 'System',
        _ => 'Dark',
      };

  Future<void> _appearance() async {
    await showSettingsSheet<void>(
      context,
      SettingsSheet(
        title: 'Choose a theme',
        eyebrow: 'APPEARANCE',
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: ZveltThemeNotifier.mode,
          builder: (context, mode, _) => SettingsCard(
            children: [
              SettingsRadioRow(
                title: 'Light',
                subtitle: 'Bright, daytime look',
                selected: mode == ThemeMode.light,
                leading: const SettingsIconTile(
                    icon: AppIcons.sun, tint: SettingsTint.amber),
                onTap: () => ZveltThemeNotifier.set(ThemeMode.light),
              ),
              SettingsRadioRow(
                title: 'Dark',
                subtitle: 'Easy on the eyes at night',
                selected: mode == ThemeMode.dark,
                leading: const SettingsIconTile(
                    icon: AppIcons.moon, tint: SettingsTint.violet),
                onTap: () => ZveltThemeNotifier.set(ThemeMode.dark),
              ),
              SettingsRadioRow(
                title: 'System',
                subtitle: 'Match your device',
                selected: mode == ThemeMode.system,
                leading: const SettingsIconTile(
                    icon: AppIcons.settings,
                    tint: SettingsTint.blue),
                onTap: () => ZveltThemeNotifier.set(ThemeMode.system),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _exportData() async {
    final ok = await settingsConfirm(
      context,
      title: 'Export your data?',
      body:
          'Zvelt will create a portable JSON copy of your account, training, social and health data.',
      confirmLabel: 'Create export',
    );
    if (!ok) return;
    final token = await _auth.getAccessToken();
    if (token == null || !mounted) return;
    try {
      final res = await http.get(Uri.parse('$v1Base/me/export-data'), headers: {
        'Authorization': 'Bearer $token'
      }).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (res.statusCode == 200) {
        if (kIsWeb) {
          settingsSnack(context,
              'Export generated. Use the mobile app to share the file.');
          return;
        }
        final dir = await getTemporaryDirectory();
        final file =
            File('${dir.path}${Platform.pathSeparator}zvelt-data-export.json');
        await file.writeAsString(res.body, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/json')],
            text: 'Your Zvelt data export',
          ),
        );
      } else {
        settingsSnack(context, 'Export request failed (${res.statusCode}).',
            error: true);
      }
    } catch (_) {
      if (mounted) {
        settingsSnack(context, 'Export request failed. Try again online.',
            error: true);
      }
    }
  }

  Future<void> _clearCache() async {
    final ok = await settingsConfirm(
      context,
      title: 'Clear cache and reload?',
      body:
          'Temporary profile, plan and image caches will be cleared. Your account and settings stay intact.',
      confirmLabel: 'Clear cache',
    );
    if (!ok) return;
    await AppDataCache.instance.clearSessionCaches();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await SocialNotificationHub.refresh();
    if (mounted) settingsSnack(context, 'Cache cleared - data reloaded.');
    await _load();
  }

  Future<void> _sendLogs() async {
    try {
      if (!kIsWeb) await FirebaseCrashlytics.instance.sendUnsentReports();
      if (mounted) {
        settingsSnack(context, 'Diagnostic reports sent to the developer.');
      }
    } catch (_) {
      if (mounted) {
        settingsSnack(context, 'Could not send diagnostics.', error: true);
      }
    }
  }

  Future<void> _setDiagnostics(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(SettingsKeys.diagnostics, value);
    if (!kIsWeb) {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(value && !kDebugMode);
    }
    if (mounted) setState(() => _diagnostics = value);
  }

  Future<void> _rate() async {
    var rating = 0;
    await showSettingsSheet<void>(
      context,
      StatefulBuilder(
        builder: (context, setLocal) => SettingsSheet(
          title: 'Rate Zvelt',
          eyebrow: 'YOUR FEEDBACK',
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: '$i stars',
                      onPressed: () => setLocal(() => rating = i),
                      icon: Icon(
                          i <= rating
                              ? AppIcons.star
                              : AppIcons.star,
                          color: ZveltTokens.warn,
                          size: 34),
                    ),
                ],
              ),
              const SizedBox(height: ZveltTokens.s4),
              SettingsActionButton(
                label: rating >= 4 ? 'Rate in the store' : 'Submit feedback',
                icon: rating >= 4
                    ? AppIcons.arrow_up_right_from_square
                    : AppIcons.paper_plane,
                onTap: () async {
                  if (rating == 0) {
                    settingsSnack(context, 'Pick a rating first.', error: true);
                    return;
                  }
                  Navigator.of(context).pop();
                  if (rating >= 4) {
                    await _openStore();
                  } else {
                    await _open(
                        const FeedbackScreen(kind: FeedbackKind.feature));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openStore() async {
    const appStoreId = String.fromEnvironment('APP_STORE_ID', defaultValue: '');
    final uri = !kIsWeb && Platform.isIOS && appStoreId.isNotEmpty
        ? Uri.parse('https://apps.apple.com/app/id$appStoreId')
        : Uri.parse(
            'https://play.google.com/store/apps/details?id=com.lunaoscar.zvelt');
    await _launch(uri);
  }

  Future<void> _launch(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      settingsSnack(context, 'Could not open this link.', error: true);
    }
  }

  String get _cloudSubtitle {
    final value = _cloudLastSync;
    if (value == null) return 'On - ready to sync';
    final minutes = DateTime.now().difference(value).inMinutes;
    return minutes < 1 ? 'On - synced just now' : 'On - synced ${minutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsModalShell(
      title: 'Settings',
      children: [
        const SettingsSectionTitle('Account', top: ZveltTokens.s2),
        SettingsCard(
          children: [
            SettingsRow(
              icon: AppIcons.user,
              tint: SettingsTint.orange,
              title: 'Account',
              subtitle: 'Profile, name & sign-in',
              onTap: () =>
                  _open(AccountDetailScreen(onLogout: widget.onLogout)),
            ),
            SettingsRow(
              icon: AppIcons.balance_scale_left,
              tint: SettingsTint.green,
              title: 'Physical data',
              subtitle: _physical,
              onTap: () => _open(const PhysicalDataSettingsScreen()),
            ),
            SettingsRow(
              icon: AppIcons.target,
              tint: SettingsTint.orange,
              title: 'Goals & training max',
              subtitle: _goal,
              onTap: () => _open(const GoalsTrainingScreen()),
            ),
          ],
        ),
        const SettingsSectionTitle('General'),
        SettingsCard(
          children: [
            SettingsRow(
              icon: AppIcons.sparkles,
              tint: SettingsTint.violet,
              title: 'Appearance',
              subtitle: _themeLabel,
              onTap: _appearance,
            ),
            SettingsRow(
              icon: AppIcons.bell,
              tint: SettingsTint.red,
              title: 'Notifications',
              subtitle: _notifications ? 'On' : 'Off',
              onTap: () => _open(const NotificationSettingsScreen()),
            ),
            SettingsRow(
              icon: AppIcons.settings_sliders,
              tint: SettingsTint.amber,
              title: 'Customization',
              subtitle: 'Accent \u00b7 start screen \u00b7 motion',
              onTap: () => _open(const CustomizationScreen()),
            ),
            SettingsRow(
              icon: AppIcons.bolt,
              tint: SettingsTint.violet,
              title: 'Shortcuts',
              subtitle: '$_shortcutCount quick-launch actions',
              onTap: () => _open(const ShortcutsScreen()),
            ),
            SettingsRow(
              icon: AppIcons.globe,
              tint: SettingsTint.green,
              title: 'Language',
              // English is the only shipped translation (see LanguageScreen).
              subtitle: 'English',
              onTap: () => _open(const LanguageScreen()),
            ),
            SettingsRow(
              icon: AppIcons.ruler_horizontal,
              tint: SettingsTint.blue,
              title: 'Units',
              subtitle: _units,
              onTap: () => _open(const UnitsScreen()),
            ),
          ],
        ),
        const SettingsSectionTitle('Privacy'),
        SettingsCard(
          children: [
            SettingsRow(
              icon: AppIcons.lock,
              tint: SettingsTint.blue,
              title: 'Profile visibility',
              subtitle: _visibility,
              onTap: () => _open(const ProfileVisibilityScreen()),
            ),
            SettingsRow(
              icon: AppIcons.ban,
              tint: SettingsTint.red,
              title: 'Blocked users',
              subtitle: '$_blockedCount blocked',
              onTap: () => _open(const BlockedUsersScreen()),
            ),
            SettingsRow(
              icon: AppIcons.bookmark,
              tint: SettingsTint.amber,
              title: 'My bookmarks',
              subtitle: '$_bookmarkCount saved',
              onTap: () => _open(const BookmarksScreen()),
            ),
            SettingsRow(
              icon: AppIcons.comment_alt,
              tint: SettingsTint.violet,
              title: 'Messages',
              subtitle: '$_conversationCount conversations',
              onTap: () => _open(const ConversationsScreen()),
            ),
          ],
        ),
        const SettingsSectionTitle('Data'),
        SettingsCard(
          children: [
            // 'Health & devices' row removed for v1 — Health/wearable/Strava
            // integrations are v2. IntegrationsScreen stays in the codebase
            // (dormant); re-add this row when integrations ship.
            SettingsRow(
              icon: AppIcons.cloud,
              tint: SettingsTint.blue,
              title: 'Cloud sync',
              subtitle: _cloudSubtitle,
              onTap: () => _open(const CloudSyncScreen()),
            ),
            SettingsRow(
              icon: AppIcons.download,
              tint: SettingsTint.green,
              title: 'Export my data',
              subtitle: 'Download a copy',
              onTap: _exportData,
            ),
          ],
        ),
        const SettingsSectionTitle('Resources'),
        SettingsCard(
          children: [
            SettingsRow(
              icon: AppIcons.flag,
              tint: SettingsTint.green,
              title: 'Getting started',
              subtitle: '$_gettingStartedCount of 5 complete',
              onTap: () => _open(const GettingStartedScreen()),
            ),
            SettingsRow(
              icon: AppIcons.book,
              tint: SettingsTint.amber,
              title: 'Knowledge base',
              subtitle: 'Guides & FAQ',
              onTap: () => _open(const KnowledgeBaseScreen()),
            ),
            SettingsRow(
              icon: AppIcons.megaphone,
              tint: SettingsTint.green,
              title: 'Request a feature',
              onTap: () =>
                  _open(const FeedbackScreen(kind: FeedbackKind.feature)),
            ),
            SettingsRow(
              icon: AppIcons.bug,
              tint: SettingsTint.red,
              title: 'Report a bug',
              onTap: () => _open(const FeedbackScreen(kind: FeedbackKind.bug)),
            ),
            SettingsRow(
              icon: AppIcons.star,
              tint: SettingsTint.amber,
              title: 'Rate Zvelt',
              subtitle: "Tell us how we're doing",
              onTap: _rate,
            ),
          ],
        ),
        const SettingsSectionTitle('Legal'),
        SettingsCard(
          children: [
            SettingsRow(
              icon: AppIcons.document,
              tint: SettingsTint.gray,
              title: 'Terms of Service',
              onTap: () => _open(const LegalDocumentScreen(privacy: false)),
            ),
            SettingsRow(
              icon: AppIcons.shield_check,
              tint: SettingsTint.gray,
              title: 'Privacy Policy',
              onTap: () => _open(const LegalDocumentScreen(privacy: true)),
            ),
          ],
        ),
        const SizedBox(height: ZveltTokens.s4),
        SettingsActionButton(
            label: 'Clear cache & reload all data', onTap: _clearCache),
        const SizedBox(height: ZveltTokens.cardGap),
        SettingsActionButton(label: 'Send logs to developer', onTap: _sendLogs),
        const SizedBox(height: ZveltTokens.cardGap),
        SettingsCard(
          children: [
            SettingsSwitchRow(
              icon: AppIcons.chart_line_up,
              tint: SettingsTint.gray,
              title: 'Enable diagnostics',
              value: _diagnostics,
              onChanged: _setDiagnostics,
            ),
          ],
        ),
        const SizedBox(height: ZveltTokens.s6),
        // Wrap (not Row) so the 4 links reflow to a second line on narrow
        // phones / large text scale instead of overflowing.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: ZveltTokens.s4,
          runSpacing: ZveltTokens.s2,
          children: [
            _SocialLink(
                label: 'Instagram',
                onTap: () =>
                    _launch(Uri.parse('https://instagram.com/zveltapp'))),
            _SocialLink(
                label: 'X',
                onTap: () => _launch(Uri.parse('https://x.com/zveltapp'))),
            _SocialLink(
                label: 'YouTube',
                onTap: () => _launch(Uri.parse('https://youtube.com/@zvelt'))),
            _SocialLink(
                label: 'Reddit',
                onTap: () => _launch(Uri.parse('https://reddit.com/r/zvelt'))),
          ],
        ),
        const SizedBox(height: ZveltTokens.s5),
        // scaleDown so the wordmark + version never overflow on a tiny phone.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      color: ZveltTokens.brand, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Text('Zvelt', style: ZType.h1.copyWith(fontSize: 26)),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(_version,
                    style: ZType.monoS.copyWith(color: ZveltTokens.text4)),
              ),
            ],
          ),
        ),
        const SizedBox(height: ZveltTokens.s2),
        Center(
            child: Text('Made for athletes who level up.',
                style: ZType.bodyS.copyWith(color: ZveltTokens.text4))),
        const SizedBox(height: ZveltTokens.s1),
        Center(
          child: GestureDetector(
            onTap: () => _launch(Uri.parse('https://www.flaticon.com/uicons')),
            child: Text('Icons by Flaticon',
                style: ZType.monoXS.copyWith(color: ZveltTokens.text4)),
          ),
        ),
      ],
    );
  }
}

class _SocialLink extends StatelessWidget {
  const _SocialLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 44)),
      child: Text(label,
          style: ZType.bodyS
              .copyWith(color: ZveltTokens.text3, fontWeight: FontWeight.w600)),
    );
  }
}
