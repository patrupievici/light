import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/moderation_service.dart';
import '../../services/profile_service.dart';
import '../../services/settings_store.dart';
import '../../theme/zvelt_theme_notifier.dart';
import '../../theme/zvelt_tokens.dart';
import '../social/blocked_users_screen.dart';
import 'account_settings_screens.dart';
import 'delete_account_screen.dart';
import 'preference_settings_screens.dart';
import 'resource_settings_screens.dart';
import 'settings_kit.dart';

/// Settings — 1:1 with the Claude Design "Settings" handoff. No bottom nav.
/// Sections: Account · Preferences · Training · Notifications · Privacy &
/// Social · Subscription · Connected Data (locked v2) · Support, then Log Out.
/// Every row is wired to a real destination or a functional persisted control.
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

/// The six accent options from the handoff. Purple (periwinkle) is default.
const _accents = <({String name, Color color})>[
  (name: 'Purple', color: Color(0xFF7C7FF2)),
  (name: 'Blue', color: Color(0xFF3B82F6)),
  (name: 'Green', color: Color(0xFF18C48F)),
  (name: 'Orange', color: Color(0xFFFF9F43)),
  (name: 'Pink', color: Color(0xFFEC4899)),
  (name: 'Red', color: Color(0xFFFF4D4D)),
];

class _SettingsScreenState extends State<SettingsScreen> {
  final _profile = ProfileService();

  String _goal = 'Build Strength';
  int _daysPerWeek = 4;
  String _units = 'Metric';
  String _visibility = 'Friends only';
  int _blockedCount = 0;
  String _version = '1.0.0';
  bool _accentOpen = false;

  // Local training prefs (subtitles + defaults).
  bool _autofill = true;
  bool _showPrevious = true;
  int _restSeconds = 90;
  bool _restAutostart = true;
  bool _restVibrate = true;

  @override
  void initState() {
    super.initState();
    if (!widget.preview) _load();
  }

  Future<void> _load() async {
    await Future.wait([_loadProfile(), _loadAppInfo(), _loadBlocked(), _loadLocalPrefs()]);
  }

  Future<void> _loadProfile() async {
    final me = await _profile.getMe();
    final p = me?['profile'] as Map<String, dynamic>?;
    final tp = me?['trainingProfile'] as Map<String, dynamic>?;
    if (!mounted) return;
    setState(() {
      _goal = _goalLabel(tp?['primaryGoal']?.toString());
      _daysPerWeek = (tp?['daysPerWeek'] as num?)?.toInt() ?? 4;
      _units = p?['unitSystem'] == 'imperial' ? 'Imperial' : 'Metric';
      _visibility = switch (p?['privacyDefault']) {
        'public' => 'Public',
        'private' => 'Private',
        _ => 'Friends only',
      };
    });
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {}
  }

  Future<void> _loadBlocked() async {
    try {
      final blocked = await ModerationService().listBlocked();
      if (mounted) setState(() => _blockedCount = blocked.length);
    } catch (_) {}
  }

  Future<void> _loadLocalPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autofill = prefs.getBool(SettingsKeys.logAutofillWeight) ?? true;
      _showPrevious = prefs.getBool(SettingsKeys.logShowPrevious) ?? true;
      _restSeconds = prefs.getInt(SettingsKeys.restSeconds) ?? 90;
      _restAutostart = prefs.getBool(SettingsKeys.restAutostart) ?? true;
      _restVibrate = prefs.getBool(SettingsKeys.restVibrate) ?? true;
    });
  }

  String _goalLabel(String? value) => switch (value) {
        'hypertrophy' => 'Build Muscle',
        'maintenance' => 'Maintain',
        'fat_loss' => 'Fat Loss',
        'calisthenics' => 'Calisthenics',
        'endurance' => 'Endurance',
        'explosive_power' => 'Explosive Power',
        'vertical_jump' => 'Vertical Jump',
        _ => 'Build Strength',
      };

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _load();
  }

  // ── Workout logging defaults (functional, persisted) ─────────────────────
  Future<void> _editWorkoutLogging() async {
    await showSettingsSheet<void>(
      context,
      StatefulBuilder(
        builder: (context, setLocal) => SettingsSheet(
          title: 'Workout logging',
          eyebrow: 'TRAINING',
          child: SettingsCard(
            children: [
              SettingsSwitchRow(
                icon: AppIcons.balance_scale_left,
                tint: SettingsTint.green,
                title: 'Auto-fill last weight',
                subtitle: 'Pre-fill each set with your previous load',
                value: _autofill,
                onChanged: (v) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(SettingsKeys.logAutofillWeight, v);
                  setLocal(() {});
                  if (mounted) setState(() => _autofill = v);
                },
              ),
              SettingsSwitchRow(
                icon: AppIcons.list,
                tint: SettingsTint.blue,
                title: 'Show previous set',
                subtitle: 'Display last session’s reps × weight',
                value: _showPrevious,
                onChanged: (v) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(SettingsKeys.logShowPrevious, v);
                  setLocal(() {});
                  if (mounted) setState(() => _showPrevious = v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Rest timer defaults (functional, persisted) ──────────────────────────
  Future<void> _editRestTimer() async {
    await showSettingsSheet<void>(
      context,
      StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> save() async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt(SettingsKeys.restSeconds, _restSeconds);
            await prefs.setBool(SettingsKeys.restAutostart, _restAutostart);
            await prefs.setBool(SettingsKeys.restVibrate, _restVibrate);
            if (mounted) setState(() {});
          }

          return SettingsSheet(
            title: 'Rest timer',
            eyebrow: 'TRAINING',
            child: Column(
              children: [
                SettingsCard(
                  children: [
                    SettingsStepperRow(
                      label: 'Default rest',
                      valueLabel: '${_restSeconds}s',
                      onDec: _restSeconds > 15
                          ? () {
                              setLocal(() => _restSeconds -= 15);
                              save();
                            }
                          : null,
                      onInc: _restSeconds < 300
                          ? () {
                              setLocal(() => _restSeconds += 15);
                              save();
                            }
                          : null,
                    ),
                    SettingsSwitchRow(
                      icon: AppIcons.bolt,
                      tint: SettingsTint.amber,
                      title: 'Auto-start',
                      subtitle: 'Start the timer when a set is logged',
                      value: _restAutostart,
                      onChanged: (v) {
                        setLocal(() => _restAutostart = v);
                        save();
                      },
                    ),
                    SettingsSwitchRow(
                      icon: AppIcons.bell,
                      tint: SettingsTint.red,
                      title: 'Vibrate on finish',
                      value: _restVibrate,
                      onChanged: (v) {
                        setLocal(() => _restVibrate = v);
                        save();
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Subscription (RevenueCat not wired yet — honest "coming soon") ────────
  Future<void> _proSheet() async {
    await showSettingsSheet<void>(
      context,
      SettingsSheet(
        title: 'Zvelt Pro',
        eyebrow: 'COMING SOON',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Unlimited ranks, advanced explainability, the program builder and '
              'extended analytics. Pro launches soon — you’ll be the first to know.',
              style: ZType.bodyM.copyWith(color: ZveltTokens.text2, height: 1.5),
            ),
            const SizedBox(height: ZveltTokens.s5),
            SettingsActionButton(
              label: 'Got it',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }

  void _restore() {
    settingsSnack(context, 'No previous purchases found on this account.');
  }

  Future<void> _deleteAccount() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => DeleteAccountScreen(onAccountDeleted: widget.onLogout),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await settingsConfirm(
      context,
      title: 'Log out?',
      body: 'You can sign back in any time with your email and password.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (ok) await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsModalShell(
      title: 'Settings',
      children: [
        // ── ACCOUNT ──────────────────────────────────────────────────────
        const SettingsSectionTitle('Account', top: ZveltTokens.s2),
        SettingsCard(children: [
          SettingsRow(
            icon: AppIcons.user,
            tint: SettingsTint.orange,
            title: 'Edit Profile',
            subtitle: 'Name, username, avatar, bio',
            onTap: () => _open(AccountDetailScreen(onLogout: widget.onLogout)),
          ),
          SettingsRow(
            icon: AppIcons.lock,
            tint: SettingsTint.blue,
            title: 'Email & Login',
            subtitle: 'Password, sign-in method',
            onTap: () => _open(AccountDetailScreen(onLogout: widget.onLogout)),
          ),
          SettingsRow(
            icon: AppIcons.cross_circle,
            tint: SettingsTint.red,
            title: 'Delete Account',
            subtitle: 'Permanently remove your data',
            titleColor: ZveltTokens.error,
            onTap: _deleteAccount,
          ),
        ]),

        // ── PREFERENCES ──────────────────────────────────────────────────
        const SettingsSectionTitle('Preferences'),
        SettingsCard(children: [
          _themeRow(),
          SettingsRow(
            icon: AppIcons.ruler_horizontal,
            tint: SettingsTint.blue,
            title: 'Units',
            subtitle: _units == 'Imperial' ? 'lb · in · mi · kcal' : 'kg · cm · km · kcal',
            onTap: () => _open(const UnitsScreen()),
          ),
          _accentRow(),
        ]),

        // ── TRAINING ─────────────────────────────────────────────────────
        const SettingsSectionTitle('Training'),
        SettingsCard(children: [
          SettingsRow(
            icon: AppIcons.target,
            tint: SettingsTint.orange,
            title: 'Training Goal',
            subtitle: _goal,
            onTap: () => _open(const GoalsTrainingScreen()),
          ),
          SettingsRow(
            icon: AppIcons.chart_line_up,
            tint: SettingsTint.green,
            title: 'Weekly Target',
            subtitle: '$_daysPerWeek workouts / week',
            onTap: () => _open(const GoalsTrainingScreen()),
          ),
          SettingsRow(
            icon: AppIcons.list,
            tint: SettingsTint.violet,
            title: 'Workout Logging',
            subtitle: [
              if (_autofill) 'Auto-fill last weight',
              if (_showPrevious) 'show previous set',
            ].join(', ').isEmpty ? 'Manual entry' : [
              if (_autofill) 'Auto-fill last weight',
              if (_showPrevious) 'show previous set',
            ].join(', '),
            onTap: _editWorkoutLogging,
          ),
          SettingsRow(
            icon: AppIcons.bolt,
            tint: SettingsTint.amber,
            title: 'Rest Timer Defaults',
            subtitle: '${_restSeconds}s'
                '${_restAutostart ? ' · Auto-start' : ''}'
                '${_restVibrate ? ' · Vibrate' : ''}',
            onTap: _editRestTimer,
          ),
        ]),

        // ── NOTIFICATIONS ────────────────────────────────────────────────
        const SettingsSectionTitle('Notifications'),
        SettingsCard(children: [
          SettingsRow(
            icon: AppIcons.bell,
            tint: SettingsTint.red,
            title: 'Workout Reminders',
            subtitle: 'Streak, rest day, missed workout',
            onTap: () => _open(const NotificationSettingsScreen()),
          ),
          SettingsRow(
            icon: AppIcons.bolt,
            tint: SettingsTint.orange,
            title: 'Challenge Alerts',
            subtitle: 'Invites, rank changes, ending soon',
            onTap: () => _open(const NotificationSettingsScreen()),
          ),
          SettingsRow(
            icon: AppIcons.heart,
            tint: SettingsTint.violet,
            title: 'Social Notifications',
            subtitle: 'Likes, comments, new followers, PRs',
            onTap: () => _open(const NotificationSettingsScreen()),
          ),
          SettingsRow(
            icon: AppIcons.restaurant,
            tint: SettingsTint.green,
            title: 'Nutrition Reminders',
            subtitle: 'Meals, protein, water',
            onTap: () => _open(const NotificationSettingsScreen()),
          ),
        ]),

        // ── PRIVACY & SOCIAL ─────────────────────────────────────────────
        const SettingsSectionTitle('Privacy & Social'),
        SettingsCard(children: [
          SettingsRow(
            icon: AppIcons.globe,
            tint: SettingsTint.blue,
            title: 'Profile Visibility',
            subtitle: _visibility,
            onTap: () => _open(const ProfileVisibilityScreen()),
          ),
          SettingsRow(
            icon: AppIcons.gym,
            tint: SettingsTint.green,
            title: 'Workout Visibility',
            subtitle: 'Who can see your sessions',
            onTap: () => _open(const ProfileVisibilityScreen()),
          ),
          SettingsRow(
            icon: AppIcons.trophy,
            tint: SettingsTint.amber,
            title: 'PR Visibility',
            subtitle: 'Who can see your records',
            onTap: () => _open(const ProfileVisibilityScreen()),
          ),
          SettingsRow(
            icon: AppIcons.users,
            tint: SettingsTint.violet,
            title: 'Challenge Invites',
            subtitle: 'Who can invite you',
            onTap: () => _open(const ProfileVisibilityScreen()),
          ),
          SettingsRow(
            icon: AppIcons.ban,
            tint: SettingsTint.red,
            title: 'Blocked Users',
            subtitle: '$_blockedCount blocked',
            onTap: () => _open(const BlockedUsersScreen()),
          ),
        ]),

        // ── SUBSCRIPTION ─────────────────────────────────────────────────
        const SettingsSectionTitle('Subscription'),
        SettingsCard(children: [
          SettingsRow(
            icon: AppIcons.bolt,
            tint: SettingsTint.orange,
            title: 'Zvelt Pro',
            subtitle: 'Coming soon',
            onTap: _proSheet,
          ),
          SettingsRow(
            icon: AppIcons.refresh,
            tint: SettingsTint.gray,
            title: 'Restore Purchases',
            onTap: _restore,
          ),
        ]),

        // ── CONNECTED DATA (locked v2) ───────────────────────────────────
        const SettingsSectionTitle('Connected Data'),
        const SettingsCard(children: [
          _LockedRow(
            icon: AppIcons.heart,
            title: 'Apple Health / Health Connect',
            subtitle: 'Coming in v2 · Steps, sleep, HR, weight sync',
          ),
        ]),

        // ── SUPPORT ──────────────────────────────────────────────────────
        const SettingsSectionTitle('Support'),
        SettingsCard(children: [
          SettingsRow(
            icon: AppIcons.megaphone,
            tint: SettingsTint.green,
            title: 'Help & Feedback',
            onTap: () => _open(const FeedbackScreen(kind: FeedbackKind.feature)),
          ),
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
          SettingsRow(
            icon: AppIcons.info,
            tint: SettingsTint.gray,
            title: 'App Version',
            trailingText: _version,
            chevron: false,
          ),
        ]),

        const SizedBox(height: ZveltTokens.s5),
        SettingsActionButton(
          label: 'Log out',
          icon: AppIcons.sign_out_alt,
          destructive: true,
          onTap: _confirmLogout,
        ),
      ],
    );
  }

  // ── Theme: inline System / Light / Dark segmented ──────────────────────
  Widget _themeRow() {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ZveltThemeNotifier.mode,
      builder: (context, mode, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SettingsIconTile(icon: AppIcons.sparkles, tint: SettingsTint.violet),
                const SizedBox(width: ZveltTokens.s4),
                Text('Theme', style: ZType.bodyL.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: ZveltTokens.s3),
            SettingsSegmented<ThemeMode>(
              value: mode,
              options: const [
                (value: ThemeMode.system, label: 'System'),
                (value: ThemeMode.light, label: 'Light'),
                (value: ThemeMode.dark, label: 'Dark'),
              ],
              onChanged: (m) => ZveltThemeNotifier.set(m),
            ),
          ],
        ),
      ),
    );
  }

  // ── Accent: collapsed row → 6 swatches ─────────────────────────────────
  Widget _accentRow() {
    return ValueListenableBuilder<int>(
      valueListenable: AppPreferencesNotifier.accent,
      builder: (context, accentInt, _) {
        final current = Color(accentInt);
        return Column(
          children: [
            InkWell(
              onTap: () => setState(() => _accentOpen = !_accentOpen),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3 + 2),
                child: Row(
                  children: [
                    const SettingsIconTile(icon: AppIcons.settings_sliders, tint: SettingsTint.amber),
                    const SizedBox(width: ZveltTokens.s4),
                    Expanded(
                      child: Text('Accent Color',
                          style: ZType.bodyL.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: current),
                    ),
                    const SizedBox(width: ZveltTokens.s2),
                    Icon(_accentOpen ? AppIcons.angle_small_down : AppIcons.angle_small_right,
                        color: ZveltTokens.text4, size: 22),
                  ],
                ),
              ),
            ),
            if (_accentOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, 0, ZveltTokens.s4, ZveltTokens.s4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final a in _accents)
                      GestureDetector(
                        onTap: () => AppPreferencesNotifier.setAccent(
                            a.color.toARGB32()),
                        child: Column(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: a.color,
                                border: (current.toARGB32() == a.color.toARGB32())
                                    ? Border.all(color: a.color, width: 3)
                                    : null,
                                boxShadow: (current.toARGB32() == a.color.toARGB32())
                                    ? [BoxShadow(color: a.color.withValues(alpha: 0.5), blurRadius: 8)]
                                    : null,
                              ),
                              child: (current.toARGB32() == a.color.toARGB32())
                                  ? const Icon(AppIcons.check, color: Colors.white, size: 18)
                                  : null,
                            ),
                            const SizedBox(height: 4),
                            Text(a.name, style: ZType.bodyS.copyWith(color: ZveltTokens.text3, fontSize: 10)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCKED (v2) ROW — inert, dimmed, "v2" tag.
// ─────────────────────────────────────────────────────────────────────────────

class _LockedRow extends StatelessWidget {
  const _LockedRow({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3 + 2),
        child: Row(
          children: [
            SettingsIconTile(icon: icon, tint: SettingsTint.gray),
            const SizedBox(width: ZveltTokens.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: ZType.bodyL.copyWith(fontWeight: FontWeight.w600)),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(subtitle, style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: ZveltTokens.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('v2',
                  style: ZType.monoXS.copyWith(color: ZveltTokens.text3, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
