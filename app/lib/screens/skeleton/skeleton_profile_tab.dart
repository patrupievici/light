import 'dart:convert';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/zvelt_tokens.dart';
import '../../config/api_config.dart' show v1Base;
import '../../services/_crash_reporter.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../services/workout_service.dart';
import '../../services/social_challenge_service.dart';
import '../analytics/progress_hub_screen.dart';
import '../analytics/strength_analytics_screen.dart';
import '../social/challenges_screen.dart';
import '../social/friends_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/account_settings_screens.dart';
import '../settings/preference_settings_screens.dart';
import '../settings/settings_kit.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE TAB — 1:1 with the Claude Design "Profile" handoff.
// Header → Identity card → 4 stat cards → MAIN → ACCOUNT → COMING LATER → Logout.
// Every row is wired to a real screen; stats are real API data.
// ─────────────────────────────────────────────────────────────────────────────

class SkeletonProfileTab extends StatefulWidget {
  const SkeletonProfileTab({super.key, required this.onLogout});
  final Future<void> Function() onLogout;

  @override
  State<SkeletonProfileTab> createState() => _SkeletonProfileTabState();
}

class _SkeletonProfileTabState extends State<SkeletonProfileTab> {
  final _auth = AuthService();
  final _profileService = ProfileService();

  String _displayName = 'Athlete';
  String? _username;
  String? _goalLabel;
  String? _levelLabel;
  int _streak = 0;
  int _totalWorkouts = 0;
  int _prCount = 0;
  int _challengeCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      await Future.wait([
        _loadProfile(),
        _loadWorkoutCount(),
        _loadPrCount(),
        _loadChallengeCount(),
      ]);
    } catch (e, st) {
      reportError(e, st, reason: 'profile-tab:initial-load');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadProfile() async {
    final me = await _profileService.getMe();
    if (me == null || !mounted) return;
    final profile = me['profile'] as Map<String, dynamic>?;
    final streak = me['streak'] as Map<String, dynamic>?;
    final training = me['trainingProfile'] as Map<String, dynamic>?;
    setState(() {
      _displayName = (profile?['displayName'] as String?)?.trim().isNotEmpty == true
          ? (profile!['displayName'] as String).trim()
          : 'Athlete';
      _username = profile?['username'] as String?;
      _streak = streak?['currentStreak'] as int? ?? 0;
      _goalLabel = _goalToLabel(training?['primaryGoal'] as String?);
      _levelLabel = _levelToLabel(training?['trainingLevel'] as String?);
    });
  }

  Future<void> _loadWorkoutCount() async {
    final token = await _auth.getAccessToken();
    if (token == null) return;
    final res = await http.get(
      Uri.parse('$v1Base/workouts?limit=1'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200 || !mounted) return;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final meta = data['meta'] as Map<String, dynamic>?;
    setState(() => _totalWorkouts = meta?['total'] as int? ?? 0);
  }

  Future<void> _loadPrCount() async {
    try {
      final ranks = await WorkoutService().getMyRanks();
      if (!mounted) return;
      setState(() => _prCount = ranks.where((r) => r.bestE1rmKg > 0).length);
    } catch (e, st) {
      reportError(e, st, reason: 'profile-tab:pr-count');
    }
  }

  Future<void> _loadChallengeCount() async {
    try {
      final active = await SocialChallengeService().loadActive();
      if (!mounted) return;
      setState(() => _challengeCount = active.length);
    } catch (_) {
      // Best-effort — 0 is a fine fallback for the stat.
    }
  }

  // ── Goal / level → display chips ─────────────────────────────────────────
  String? _goalToLabel(String? goal) {
    switch (goal) {
      case 'strength':
        return 'Build Strength';
      case 'hypertrophy':
        return 'Build Muscle';
      case 'fat_loss':
        return 'Fat Loss';
      case 'maintenance':
        return 'Maintain';
      case 'calisthenics':
        return 'Calisthenics';
      case 'explosive_power':
        return 'Explosive Power';
      case 'vertical_jump':
        return 'Vertical Jump';
      case 'endurance':
        return 'Endurance';
      default:
        return null;
    }
  }

  String? _levelToLabel(String? level) {
    switch (level) {
      case 'beginner':
        return 'Beginner';
      case 'novice':
        return 'Novice';
      case 'intermediate':
        return 'Intermediate';
      case 'advanced':
        return 'Advanced';
      default:
        return null;
    }
  }

  String get _initials {
    final parts = _displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'A';
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
  }

  // ── Navigation ───────────────────────────────────────────────────────────
  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) _load(); // refresh stats after returning
  }

  void _openSettings() => _push(SettingsScreen(onLogout: widget.onLogout));
  void _openEditProfile() => _push(AccountDetailScreen(onLogout: widget.onLogout));

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
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
                  : RefreshIndicator(
                      color: ZveltTokens.brand,
                      onRefresh: _load,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                            ZveltTokens.screenPaddingH, ZveltTokens.s1, ZveltTokens.screenPaddingH, mq.padding.bottom + ZveltTokens.s10),
                        children: [
                          _IdentityCard(
                            initials: _initials,
                            displayName: _displayName,
                            username: _username,
                            goalLabel: _goalLabel,
                            levelLabel: _levelLabel,
                            onEdit: _openEditProfile,
                          ),
                          const SizedBox(height: ZveltTokens.s4),
                          _statCards(),
                          const SizedBox(height: ZveltTokens.s5),

                          // ── MAIN ──────────────────────────────────────────
                          const SettingsSectionTitle('Main', top: 0),
                          SettingsCard(children: [
                            SettingsRow(
                              icon: AppIcons.chart_line_up,
                              tint: ZveltTokens.brand,
                              title: 'Progress',
                              subtitle: 'Weight · Photos · Volume · Consistency',
                              onTap: () => _push(const ProgressHubScreen()),
                            ),
                            SettingsRow(
                              icon: AppIcons.trophy,
                              tint: ZveltTokens.brand,
                              title: 'Personal Records',
                              subtitle: 'Strength · Reps · Volume · Share',
                              onTap: () => _push(const StrengthAnalyticsScreen()),
                            ),
                            SettingsRow(
                              icon: AppIcons.bolt,
                              tint: ZveltTokens.brand,
                              title: 'Challenges',
                              subtitle: 'Active · Pending · Completed · History',
                              badge: _challengeCount > 0 ? '$_challengeCount' : null,
                              onTap: () => _push(const ChallengesScreen()),
                            ),
                            SettingsRow(
                              icon: AppIcons.target,
                              tint: ZveltTokens.brand,
                              title: 'Training Goals',
                              subtitle: 'Goal · Level · Weekly target · Split',
                              onTap: () => _push(const GoalsTrainingScreen()),
                            ),
                            SettingsRow(
                              icon: AppIcons.users,
                              tint: ZveltTokens.brand,
                              title: 'Friends',
                              subtitle: 'Followers · Following · Invite · Challenge',
                              onTap: () => _push(const FriendsScreen()),
                            ),
                          ]),
                          const SizedBox(height: ZveltTokens.s5),

                          // ── ACCOUNT ───────────────────────────────────────
                          const SettingsSectionTitle('Account', top: 0),
                          SettingsCard(children: [
                            SettingsRow(
                              icon: AppIcons.bell,
                              tint: SettingsTint.gray,
                              title: 'Notifications',
                              onTap: () => _push(const NotificationSettingsScreen()),
                            ),
                            SettingsRow(
                              icon: AppIcons.shield_check,
                              tint: SettingsTint.gray,
                              title: 'Privacy',
                              onTap: () => _push(const ProfileVisibilityScreen()),
                            ),
                            SettingsRow(
                              icon: AppIcons.settings,
                              tint: SettingsTint.gray,
                              title: 'Settings',
                              onTap: _openSettings,
                            ),
                          ]),
                          const SizedBox(height: ZveltTokens.s5),

                          // ── COMING LATER (locked v2) ──────────────────────
                          const SettingsSectionTitle('Coming later', top: 0),
                          const SettingsCard(children: [
                            _LockedRow(
                              icon: AppIcons.moon,
                              title: 'Recovery & Sleep',
                              subtitle: 'Coming in v2 · Connect health data to unlock',
                            ),
                            _LockedRow(
                              icon: AppIcons.clock,
                              title: 'Body Insights',
                              subtitle: 'Coming later',
                            ),
                            _LockedRow(
                              icon: AppIcons.bolt,
                              title: 'Connected Devices',
                              subtitle: 'Apple Health · Garmin · Whoop · Fitbit',
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
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.screenPaddingH, ZveltTokens.s2, ZveltTokens.screenPaddingH, ZveltTokens.s2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Profile',
              style: ZType.display.copyWith(fontSize: 30, color: ZveltTokens.text, height: 1),
            ),
          ),
          Semantics(
            button: true,
            label: 'Settings',
            child: GestureDetector(
              onTap: _openSettings,
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZveltTokens.surface,
                  boxShadow: ZveltTokens.shadowCard,
                ),
                child: Icon(AppIcons.settings, color: ZveltTokens.text2, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCards() {
    return Row(
      children: [
        _StatCard(value: '$_totalWorkouts', label: 'Workouts', onTap: () => _push(const ProgressHubScreen())),
        const SizedBox(width: 10),
        _StatCard(value: '$_streak', label: 'Streak', onTap: () => _push(const ProgressHubScreen())),
        const SizedBox(width: 10),
        _StatCard(value: '$_prCount', label: 'PRs', onTap: () => _push(const StrengthAnalyticsScreen())),
        const SizedBox(width: 10),
        _StatCard(
          value: '$_challengeCount',
          label: 'Challenges',
          accent: true,
          onTap: () => _push(const ChallengesScreen()),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IDENTITY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.initials,
    required this.displayName,
    required this.username,
    required this.goalLabel,
    required this.levelLabel,
    required this.onEdit,
  });

  final String initials;
  final String displayName;
  final String? username;
  final String? goalLabel;
  final String? levelLabel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5, vertical: ZveltTokens.s6),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rXl),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        children: [
          // Avatar + edit badge
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: ZveltTokens.gradBrand,
                    boxShadow: [
                      BoxShadow(
                        color: ZveltTokens.brand.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Text(
                    initials,
                    style: ZType.stat.copyWith(fontSize: 32, color: ZveltTokens.onBrand, height: 1),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Semantics(
                    button: true,
                    label: 'Edit profile',
                    child: GestureDetector(
                      onTap: onEdit,
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ZveltTokens.brand,
                          border: Border.all(color: ZveltTokens.surface, width: 2),
                        ),
                        child: const Icon(AppIcons.edit, color: ZveltTokens.onBrand, size: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZveltTokens.s4),
          Text(
            displayName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ZType.h2.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w700),
          ),
          if (username != null && username!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('@$username', style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
          ],
          if (goalLabel != null || levelLabel != null) ...[
            const SizedBox(height: ZveltTokens.s3),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (goalLabel != null)
                  _Chip(text: goalLabel!, accent: true),
                if (levelLabel != null)
                  _Chip(text: levelLabel!, accent: false),
              ],
            ),
          ],
          const SizedBox(height: ZveltTokens.s4),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: ZveltTokens.surface2,
              borderRadius: BorderRadius.circular(ZveltTokens.rMd),
              child: InkWell(
                borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                onTap: onEdit,
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  child: Text('Edit Profile',
                      style: ZType.bodyL.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.accent});
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: accent ? ZveltTokens.brandTint : ZveltTokens.surface2,
        borderRadius: BorderRadius.circular(ZveltTokens.rSm),
      ),
      child: Text(
        text,
        style: ZType.bodyS.copyWith(
          color: accent ? ZveltTokens.brandDeep : ZveltTokens.text2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label, required this.onTap, this.accent = false});
  final String value;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: '$value $label',
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: ZveltTokens.s4),
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              boxShadow: ZveltTokens.shadowCard,
            ),
            child: Column(
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.num_.copyWith(
                    fontSize: 20,
                    color: accent ? ZveltTokens.brand : ZveltTokens.text,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
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
