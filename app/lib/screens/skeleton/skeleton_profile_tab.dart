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
import '../profile_screen.dart';
import '../social/notifications_screen.dart';
import '../social/bookmarks_screen.dart';
import '../../services/social_notification_hub.dart';
import '../analytics/progress_hub_screen.dart';
import '../analytics/weekly_effort_screen.dart';
import '../ai/ai_chat_screen.dart';
import '../profile/achievements_screen.dart';
import '../../widgets/z/z_eyebrow.dart';
import '../../widgets/zvelt_primary_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE TAB
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

  String? _displayName;
  String? _username;
  String? _bio;
  String? _memberSince;
  String _unitSystem = 'metric';
  double? _weightKg;
  int _streak = 0;
  int _totalWorkouts = 0;
  int _totalAchievements = 0;
  int _earnedAchievements = 0;
  List<Map<String, dynamic>> _recentAchievements = [];
  List<ExerciseRankDto> _personalRecords = [];
  bool _loading = true;
  int _gameLevel = 1;
  String _gameLevelName = '';
  int _totalXp = 0;
  String _privacyDefault = 'friends';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadProfile(),
        _loadWorkoutCount(),
        _loadAchievements(),
        _loadPersonalRecords(),
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
    setState(() {
      _displayName = profile?['displayName'] as String? ?? 'Athlete';
      _username = profile?['username'] as String?;
      _bio = profile?['bio'] as String?;
      _unitSystem = profile?['unitSystem'] as String? ?? 'metric';
      final bw = profile?['bodyweightKg'] ?? profile?['bodweightKg'] ?? profile?['bodyweight_kg'];
      if (bw != null) {
        _weightKg = bw is num ? bw.toDouble() : double.tryParse(bw.toString());
      }
      _streak = streak?['currentStreak'] as int? ?? 0;
      // Member-since from profile.createdAt (full Prisma row in /me) — null
      // hides the segment rather than inventing a date.
      final created = profile?['createdAt'] as String?;
      final createdDt = created != null ? DateTime.tryParse(created) : null;
      if (createdDt != null) {
        const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        _memberSince = '${mo[createdDt.month - 1]} ${createdDt.year}';
      }
      final gx = me['gameXp'] as Map<String, dynamic>?;
      _gameLevel = (gx?['level'] as num?)?.toInt() ?? 1;
      _gameLevelName = gx?['levelName'] as String? ?? '';
      // Real cumulative XP from backend. Accepts a few aliases the API has used
      // over time (totalXp, xp, totalGameXp) before falling back to 0.
      _totalXp = (gx?['totalXp'] as num?)?.toInt()
          ?? (gx?['xp'] as num?)?.toInt()
          ?? (gx?['totalGameXp'] as num?)?.toInt()
          ?? (me['totalXp'] as num?)?.toInt()
          ?? 0;
      _privacyDefault = profile?['privacyDefault'] as String? ?? 'friends';
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

  Future<void> _loadAchievements() async {
    final token = await _auth.getAccessToken();
    if (token == null) return;
    final res = await http.get(
      Uri.parse('$v1Base/achievements/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200 || !mounted) return;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final all = data['achievements'] as List<dynamic>? ?? [];
    final earned = all.where((a) => (a as Map)['earned'] == true).toList();
    setState(() {
      _totalAchievements = all.length;
      _earnedAchievements = earned.length;
      _recentAchievements = earned
          .cast<Map<String, dynamic>>()
          .take(3)
          .toList();
    });
  }

  Future<void> _loadPersonalRecords() async {
    try {
      final ranks = await WorkoutService().getMyRanks();
      if (!mounted) return;
      final withE1rm = ranks.where((r) => r.bestE1rmKg > 0).toList()
        ..sort((a, b) => b.bestE1rmKg.compareTo(a.bestE1rmKg));
      setState(() => _personalRecords = withE1rm.take(5).toList());
    } catch (e, st) {
      reportError(e, st, reason: 'profile-tab:personal-records');
    }
  }

  String get _initials {
    final name = _displayName ?? 'A';
    // Same guard as the home tab: empty/double-spaced names used to throw
    // RangeError inside build and red-screen the profile tab.
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'A';
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
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
            _buildProfileHeader(context),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: ZveltTokens.brand))
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: ZveltTokens.brand,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(ZveltTokens.s4, 0, ZveltTokens.s4, mq.padding.bottom + ZveltTokens.s8),
                        children: [
                          const SizedBox(height: ZveltTokens.s1),
                          // ── Avatar + Name + Tier ────────────────────────
                          _ProfileHero(
                            initials: _initials,
                            displayName: _displayName ?? 'Athlete',
                            username: _username,
                            memberSince: _memberSince,
                            gameLevelName: _gameLevelName,
                            gameLevel: _gameLevel,
                            streak: _streak,
                          ),
                          const SizedBox(height: ZveltTokens.s4),

                          // ── Stats strip ─────────────────────────────────
                          _StatsStrip(
                            streak: _streak,
                            workouts: _totalWorkouts,
                            xp: _totalXp,
                          ),
                          const SizedBox(height: ZveltTokens.s5),

                  // ── Personal records (mockup 12) ──────────────────────────
                  if (_personalRecords.isNotEmpty) ...[
                    const _SectionHeader(title: 'Personal Records'),
                    const SizedBox(height: ZveltTokens.s3),
                    _SectionCard(
                      children: [
                        for (var i = 0; i < _personalRecords.length; i++) ...[
                          if (i > 0) _Divider(),
                          _PersonalRecordRow(rank: _personalRecords[i]),
                        ],
                      ],
                    ),
                    const SizedBox(height: ZveltTokens.s5),
                  ],

                  // ── Achievements preview ──────────────────────────────────
                  if (_recentAchievements.isNotEmpty) ...[
                    _SectionHeader(
                      title: 'Recent badges',
                      trailing: '$_earnedAchievements / $_totalAchievements',
                      onTap: _openAchievements,
                    ),
                    const SizedBox(height: ZveltTokens.s3),
                    _AchievementsPreview(
                      achievements: _recentAchievements,
                      onTap: _openAchievements,
                    ),
                    const SizedBox(height: ZveltTokens.s5),
                  ],

                  // ── Sections ──────────────────────────────────────────────
                  const _SectionHeader(title: 'Account'),
                  const SizedBox(height: ZveltTokens.s2),
                  _SectionCard(children: [
                    _SectionRow(
                      icon: AppIcons.user,
                      title: 'Physical data',
                      subtitle: _weightKg != null
                          ? '${_weightKg!.toStringAsFixed(1)} kg'
                          : 'Not set',
                      onTap: () => _openPhysicalData(),
                    ),
                    _Divider(),
                    _SectionRow(
                      icon: AppIcons.ruler_horizontal,
                      title: 'Units',
                      subtitle: _unitSystem == 'metric' ? 'Metric (kg, cm)' : 'Imperial (lbs, in)',
                      onTap: () => _showUnitsDialog(),
                    ),
                    _Divider(),
                    _SectionRow(
                      icon: AppIcons.edit,
                      title: 'Edit profile',
                      subtitle: 'Name, username, bio',
                      onTap: () => _openEditProfile(),
                    ),
                  ]),
                  const SizedBox(height: ZveltTokens.s4),

                  const _SectionHeader(title: 'Activity'),
                  const SizedBox(height: ZveltTokens.s2),
                  _SectionCard(children: [
                    _SectionRow(
                      icon: AppIcons.trophy,
                      title: 'Achievements',
                      subtitle: '$_earnedAchievements earned',
                      onTap: () => _openAchievements(),
                    ),
                    _Divider(),
                    _SectionRow(
                      icon: AppIcons.bookmark,
                      title: 'My Bookmarks',
                      subtitle: 'Posts you saved',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const BookmarksScreen()),
                      ),
                    ),
                    _Divider(),
                    _SectionRow(
                      icon: AppIcons.chart_line_up,
                      title: 'Analytics & charts',
                      subtitle: 'Training, nutrition, steps, ranks',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const ProgressHubScreen()),
                      ),
                    ),
                    _Divider(),
                    _SectionRow(
                      icon: AppIcons.chart_line_up,
                      title: 'Weekly effort',
                      subtitle: 'Volume (kg×reps) — full screen',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const WeeklyEffortScreen()),
                      ),
                    ),
                    _Divider(),
                    _SectionRow(
                      icon: AppIcons.brain_circuit,
                      title: 'AI coach',
                      subtitle: 'Tips training & nutrition (DeepSeek)',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const AiChatScreen()),
                      ),
                    ),
                  ]),
                  const SizedBox(height: ZveltTokens.s4),

                  const _SectionHeader(title: 'App'),
                  const SizedBox(height: ZveltTokens.s2),
                  _SectionCard(children: [
                    _SectionRow(
                      icon: AppIcons.bell,
                      title: 'Notifications',
                      subtitle: 'Friend requests, likes, comments',
                      onTap: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                        );
                        SocialNotificationHub.refresh();
                      },
                    ),
                    _Divider(),
                    _SectionRow(
                      icon: AppIcons.shield_check,
                      title: 'Privacy',
                      subtitle: 'Who sees your activity',
                      onTap: () => _showPrivacyDialog(),
                    ),
                  ]),
                  const SizedBox(height: ZveltTokens.s6),
                        ],  // ListView children
                      ),    // ListView
                    ),      // RefreshIndicator
                  ),        // Expanded
                ],          // Column children
              ),            // Column
            ),              // SafeArea
          );                // Scaffold
        }

  Widget _buildProfileHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s2, ZveltTokens.s4, ZveltTokens.s1),
      child: Row(
        children: [
          // Back arrow only when pushed as a route; as the Profile tab root
          // there's nothing to pop, so reserve the slot to keep title centered.
          if (Navigator.of(context).canPop())
            _CircleIconButton(
              icon: AppIcons.arrow_small_left,
              semanticLabel: 'Back',
              onTap: () => Navigator.of(context).maybePop(),
            )
          else
            const SizedBox(width: 40),
          Expanded(
            child: Center(
              child: Text(
                'Profile',
                style: ZType.h4.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          _loading
              ? const SizedBox(width: 40)
              : _CircleIconButton(
                  icon: AppIcons.edit,
                  semanticLabel: 'Edit profile',
                  onTap: _openEditProfile,
                ),
        ],
      ),
    );
  }

  void _openPhysicalData() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    _load();
  }

  void _openAchievements() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const AchievementsScreen()),
    );
  }

  void _openEditProfile() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditProfileSheet(
        displayName: _displayName ?? '',
        username: _username ?? '',
        bio: _bio ?? '',
        onSave: (name, username, bio) async {
          await _profileService.updateProfile(
            displayName: name,
            username: username,
            bio: bio,
          );
          await _load();
        },
      ),
    );
  }

  void _showUnitsDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Units'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['metric', 'imperial'].map((u) => RadioListTile<String>(
            value: u,
            // ignore: deprecated_member_use
            groupValue: _unitSystem,
            // ignore: deprecated_member_use
            onChanged: (v) => Navigator.pop(ctx, v),
            title: Text(
              u == 'metric' ? 'Metric (kg, cm)' : 'Imperial (lbs, in)',
              style: TextStyle(color: ZveltTokens.text),
            ),
            activeColor: ZveltTokens.brand,
          )).toList(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    // try/catch + status check: offline this used to throw an UNHANDLED
    // async exception (logged as a fatal crash in Crashlytics) and a 4xx/5xx
    // silently reverted the selection with zero feedback.
    try {
      final token = await _auth.getAccessToken();
      if (token == null) {
        _showSnack('Please sign in again to change units.');
        return;
      }
      final res = await http.patch(
        Uri.parse('$v1Base/me/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'unitSystem': result}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        await _load();
      } else {
        _showSnack("Couldn't save units (${res.statusCode}) — try again.");
      }
    } catch (_) {
      if (mounted) _showSnack("Couldn't save units — check your connection.");
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showPrivacyDialog() async {
    const options = [
      {'value': 'private', 'label': 'Private — only you'},
      {'value': 'friends', 'label': 'Friends — your connections'},
      {'value': 'public', 'label': 'Public — everyone'},
    ];
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ZveltTokens.surface,
        title: const Text('Default post privacy'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((item) => ListTile(
            title: Text(item['label']!, style: ZType.bodyM.copyWith(color: ZveltTokens.text)),
            trailing: _privacyDefault == item['value']
                ? const Icon(AppIcons.check, color: ZveltTokens.brand, size: 18)
                : null,
            onTap: () => Navigator.pop(ctx, item['value']),
          )).toList(),
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      final token = await _auth.getAccessToken();
      if (token == null) {
        _showSnack('Please sign in again to change privacy.');
        return;
      }
      final res = await http.patch(
        Uri.parse('$v1Base/me/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'privacyDefault': result}),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _privacyDefault = result);
        _showSnack('Privacy updated');
      } else {
        // Non-200 used to fail in total silence — for a privacy control
        // that's the worst possible failure mode.
        _showSnack("Couldn't update privacy (${res.statusCode}) — try again.");
      }
    } catch (_) {
      if (mounted) {
        _showSnack("Couldn't update privacy — check your connection.");
      }
    }
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE HEADER
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE HERO (design-matching: large centered avatar + tier badge)
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.initials,
    required this.displayName,
    this.username,
    this.memberSince,
    required this.gameLevelName,
    required this.gameLevel,
    required this.streak,
  });

  final String initials;
  final String displayName;
  final String? username;
  /// 'Jan 2025' — from profile.createdAt; null hides the segment (honest).
  final String? memberSince;
  final String gameLevelName;
  final int gameLevel;
  final int streak;

  static const _roman = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X'];

  /// Design chip copy: "Tier VII · Ironbound" — roman tier + level name.
  String get _tierLabel {
    final tier = _roman[(gameLevel - 1).clamp(0, _roman.length - 1)];
    return gameLevelName.isNotEmpty ? 'Tier $tier · $gameLevelName' : 'Tier $tier';
  }

  @override
  Widget build(BuildContext context) {
    // ── V2 redesign (design screens-modals.jsx ProfileScreen): clean
    // centered hero — 88px gradBrand avatar, 28px display caps name,
    // "@user · Member since X" meta line, Tier + streak chips. Replaces
    // the V1 leftovers (SpaceGrotesk 900 italic, glow ring, hardcoded
    // #FF5A1F / gold #FFD183 chip).
    final meta = [
      if (username != null && username!.isNotEmpty) '@$username',
      if (memberSince != null) 'Member since $memberSince',
    ].join(' · ');

    return Column(
      children: [
        const SizedBox(height: 8),
        Semantics(
          image: true,
          label: '$displayName profile avatar',
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: ZveltTokens.gradBrand,
              boxShadow: [
                BoxShadow(
                  color: ZveltTokens.brand.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: ZType.stat.copyWith(
                fontSize: 34,
                color: ZveltTokens.onBrand,
                height: 1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          displayName.toUpperCase(),
          textAlign: TextAlign.center,
          style: ZType.display.copyWith(
            fontSize: 28,
            color: ZveltTokens.text,
            height: 1,
          ),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            meta,
            style: ZType.bodyS.copyWith(
              color: ZveltTokens.text2,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Brand chip — tier
            Container(
              padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: 5),
              decoration: BoxDecoration(
                color: ZveltTokens.brandTint,
                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
              ),
              child: Text(
                _tierLabel,
                style: ZType.monoXS.copyWith(
                  fontWeight: FontWeight.w600,
                  color: ZveltTokens.brandDeep,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: ZveltTokens.s2),
            // Neutral chip — streak
            Container(
              padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s3, vertical: 5),
              decoration: BoxDecoration(
                color: ZveltTokens.surface,
                borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                border: Border.all(color: ZveltTokens.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AppIcons.flame,
                      size: 11, color: ZveltTokens.brand),
                  const SizedBox(width: 4),
                  Text(
                    '${streak}d',
                    style: ZType.monoXS.copyWith(
                      fontWeight: FontWeight.w600,
                      color: ZveltTokens.text,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS STRIP (3-column horizontal strip: Workouts | Streak | XP)
// ─────────────────────────────────────────────────────────────────────────────

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.streak,
    required this.workouts,
    required this.xp,
  });

  final int streak;
  final int workouts;
  final int xp;

  @override
  Widget build(BuildContext context) {
    // ── V2 redesign: design's "Lifetime" card — ZCard + eyebrow header +
    // 3-col grid (24px stat over 10px eyebrow label). Same REAL values as
    // before (sessions / streak / XP — we don't track lifetime hours, so
    // the design's "Hours" column is honestly absent). Replaces the V1
    // strip (SpaceGrotesk italic + dark-theme #1A2030 divider).
    final stats = [
      _StripStat(value: '$workouts', label: 'Sessions'),
      _StripStat(value: '${streak}d', label: 'Streak'),
      _StripStat(value: xp.toLocaleString(), label: 'XP'),
    ];
    return Container(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ZEyebrow('Lifetime'),
          const SizedBox(height: ZveltTokens.s3),
          Row(
            children: [
              for (final s in stats)
                Expanded(
                  child: Semantics(
                    label: '${s.value} ${s.label}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.value,
                          style: ZType.num_.copyWith(
                            fontSize: 24,
                            color: ZveltTokens.text,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: ZveltTokens.s1),
                        Text(
                          s.label.toUpperCase(),
                          style: ZType.eyebrow.copyWith(
                            fontSize: 11,
                            color: ZveltTokens.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StripStat {
  const _StripStat({required this.value, required this.label});
  final String value;
  final String label;
}

extension _IntFormat on int {
  String toLocaleString() {
    final s = toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACHIEVEMENTS PREVIEW
// ─────────────────────────────────────────────────────────────────────────────

class _AchievementsPreview extends StatelessWidget {
  const _AchievementsPreview({required this.achievements, this.onTap});
  final List<Map<String, dynamic>> achievements;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: achievements.map((a) {
        final tier = (a['tier'] as String? ?? 'bronze').toUpperCase();
        final title = a['title'] as String? ?? '';
        return Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Semantics(
              button: true,
              label: 'Badge: $title, $tier tier',
              child: Container(
              margin: const EdgeInsets.only(right: ZveltTokens.s2),
              padding: const EdgeInsets.all(ZveltTokens.s4),
              decoration: BoxDecoration(
                color: ZveltTokens.surface,
                borderRadius: BorderRadius.circular(ZveltTokens.rLg),
                boxShadow: ZveltTokens.shadowCard,
              ),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: ZveltTokens.brandTint,
                      borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                    ),
                    child: const Icon(AppIcons.trophy,
                        color: ZveltTokens.brand, size: 22),
                  ),
                  const SizedBox(height: ZveltTokens.s2),
                  Text(
                    title,
                    style: ZType.bodyS.copyWith(
                      color: ZveltTokens.text,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tier,
                    style: ZType.eyebrow.copyWith(color: ZveltTokens.text3),
                  ),
                ],
              ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing, this.onTap});
  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(title, style: ZType.h3.copyWith(fontWeight: FontWeight.w700)),
        const Spacer(),
        if (trailing != null)
          GestureDetector(
            onTap: onTap,
            child: Text(trailing!,
                style: ZType.bodyS.copyWith(color: ZveltTokens.brand)),
          ),
      ],
    );
  }
}

/// One personal-record row (mockup 12): exercise name + best estimated 1RM.
class _PersonalRecordRow extends StatelessWidget {
  const _PersonalRecordRow({required this.rank});
  final ExerciseRankDto rank;

  @override
  Widget build(BuildContext context) {
    final kg = rank.bestE1rmKg;
    final kgStr = kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
      child: Row(
        children: [
          const Icon(AppIcons.trophy, size: 18, color: ZveltTokens.warn),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
            child: Text(rank.exerciseName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZType.bodyM.copyWith(color: ZveltTokens.text)),
          ),
          Text('$kgStr kg',
              style: ZType.num_.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(children: children),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: ZveltTokens.brand, size: 20),
      title: Text(title,
          style: ZType.bodyM.copyWith(color: ZveltTokens.text)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: ZType.bodyS.copyWith(color: ZveltTokens.text2))
          : null,
      trailing: Icon(AppIcons.angle_small_right, color: ZveltTokens.text2, size: 18),
      onTap: onTap,
      dense: true,
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(height: 1, indent: 52, color: ZveltTokens.border);
}

/// White circular icon button (header back / edit) — matches the Claude
/// Design Profile mockup.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap, this.semanticLabel});
  final IconData icon;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ZveltTokens.surface,
            boxShadow: ZveltTokens.shadowCard,
          ),
          child: Icon(icon, color: ZveltTokens.text, size: 20),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EDIT PROFILE SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.displayName,
    required this.username,
    required this.bio,
    required this.onSave,
  });
  final String displayName;
  final String username;
  final String bio;
  final Future<void> Function(String, String, String) onSave;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  static const int _displayNameMax = 40;
  static const int _bioMax = 280;
  static const int _usernameMin = 3;
  static const int _usernameMax = 30;
  static final RegExp _usernameRe = RegExp(r'^[a-zA-Z0-9_]+$');

  late final TextEditingController _nameCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _bioCtrl;
  bool _saving = false;
  String? _nameError;
  String? _usernameError;
  String? _bioError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.displayName);
    _usernameCtrl = TextEditingController(text: widget.username);
    _bioCtrl = TextEditingController(text: widget.bio);
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _usernameCtrl.dispose(); _bioCtrl.dispose();
    super.dispose();
  }

  /// Returns true if all fields are valid. Sets per-field error strings.
  bool _validate(String name, String username, String bio) {
    String? nameErr;
    String? userErr;
    String? bioErr;
    if (name.isEmpty) {
      nameErr = 'Display name is required';
    } else if (name.length > _displayNameMax) {
      nameErr = 'Display name must be $_displayNameMax characters or fewer';
    }
    if (username.isNotEmpty) {
      if (username.length < _usernameMin || username.length > _usernameMax) {
        userErr = 'Username must be $_usernameMin–$_usernameMax characters';
      } else if (!_usernameRe.hasMatch(username)) {
        userErr = 'Letters, numbers and underscores only';
      }
    }
    if (bio.length > _bioMax) {
      bioErr = 'Bio must be $_bioMax characters or fewer';
    }
    setState(() {
      _nameError = nameErr;
      _usernameError = userErr;
      _bioError = bioErr;
    });
    return nameErr == null && userErr == null && bioErr == null;
  }

  Future<void> _onSavePressed() async {
    final name = _nameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    if (!_validate(name, username, bio)) return;

    setState(() => _saving = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onSave(name, username, bio);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: ZveltTokens.success,
        ),
      );
      nav.pop();
    } on ProfileUpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Surface USERNAME_TAKEN inline on the username field.
        if (e.code == 'USERNAME_TAKEN') {
          _usernameError = e.message;
        }
      });
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: ZveltTokens.error),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: ZveltTokens.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(
            margin: const EdgeInsets.symmetric(vertical: ZveltTokens.s3),
            width: 36, height: 4,
            decoration: BoxDecoration(color: ZveltTokens.border, borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, ZveltTokens.s1, ZveltTokens.s5, ZveltTokens.s4),
            child: Text('Edit profile', style: ZType.h4.copyWith(
              color: ZveltTokens.text,
            )),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, 0, ZveltTokens.s5, ZveltTokens.s3),
            child: TextField(
              controller: _nameCtrl,
              maxLength: _displayNameMax,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: 'Display name',
                errorText: _nameError,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, 0, ZveltTokens.s5, ZveltTokens.s3),
            child: TextField(
              controller: _usernameCtrl,
              maxLength: _usernameMax,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: 'Username',
                prefixText: '@',
                errorText: _usernameError,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, 0, ZveltTokens.s5, ZveltTokens.s5),
            child: TextField(
              controller: _bioCtrl,
              maxLines: 3,
              maxLength: _bioMax,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: 'Bio',
                errorText: _bioError,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(ZveltTokens.s5, 0, ZveltTokens.s5, ZveltTokens.s6),
            child: ZveltPrimaryButton(
              label: _saving ? 'Saving...' : 'Save',
              enabled: !_saving,
              onTap: _onSavePressed,
            ),
          ),
        ],
      ),
    );
  }
}
