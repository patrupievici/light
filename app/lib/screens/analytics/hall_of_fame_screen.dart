import 'dart:convert';
import 'package:zvelt_app/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/api_config.dart' show v1Base;
import '../../services/_crash_reporter.dart';
import '../../services/auth_service.dart';
import '../../services/workout_service.dart';
import '../../services/http_client.dart';
import '../../theme/zvelt_tokens.dart';

// ─── Data models ─────────────────────────────────────────────────────────────

class _LeaderEntry {
  const _LeaderEntry({
    required this.rank,
    required this.name,
    required this.lpTotal,
    required this.delta,
    required this.tier,
    this.isMe = false,
  });
  final int rank;
  final String name;
  final int lpTotal;
  final String delta;
  final String tier;
  final bool isMe;
}

class _BadgeData {
  const _BadgeData(
      {required this.icon,
      required this.label,
      required this.tier,
      required this.color,
      required this.unlocked});
  final IconData icon;
  final String label;
  final String tier;
  final Color color;
  final bool unlocked;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class HallOfFameScreen extends StatefulWidget {
  const HallOfFameScreen({super.key});

  @override
  State<HallOfFameScreen> createState() => _HallOfFameScreenState();
}

class _HallOfFameScreenState extends State<HallOfFameScreen> {
  final _auth = AuthService();
  final _workoutService = WorkoutService();

  bool _loading = true;
  String? _error;

  List<_LeaderEntry> _leaderboard = [];
  List<_BadgeData> _badges = [];
  Map<String, dynamic>? _myProfile;
  List<ExerciseRankDto> _myRanks = [];
  int _myStreakDays = 0;
  bool _leaderboardReal = false; // true if API returned real data

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _auth.getAccessToken();
      final headers = token != null
          ? {'Authorization': 'Bearer $token'}
          : <String, String>{};

      final results = await Future.wait([
        _fetchProfile(headers),
        _workoutService.getMyRanks(),
        _fetchLeaderboard(headers),
        _fetchStreak(),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final ranks = results[1] as List<ExerciseRankDto>;
      final leaderboard = results[2] as List<_LeaderEntry>;
      final streak = results[3] as int;

      if (!mounted) return;
      setState(() {
        _myProfile = profile;
        _myRanks = ranks;
        _myStreakDays = streak;
        _leaderboard = leaderboard;
        _leaderboardReal = leaderboard.isNotEmpty;
        _badges = _computeBadges(ranks, streak, profile);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyLoadError(e);
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _fetchProfile(
      Map<String, String> headers) async {
    try {
      final res = await http
          .get(Uri.parse('$v1Base/me'), headers: headers)
          .withTimeout();
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>?;
      }
    } catch (e, st) {
      reportError(e, st, reason: 'hall-of-fame:fetch-me');
    }
    return null;
  }

  Future<List<_LeaderEntry>> _fetchLeaderboard(
      Map<String, String> headers) async {
    try {
      final res = await http
          .get(
            Uri.parse('$v1Base/leaderboard/season')
                .replace(queryParameters: {'limit': '8'}),
            headers: headers,
          )
          .withTimeout();
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = data['data'] as List<dynamic>? ?? [];
        return list.asMap().entries.map((e) {
          final j = e.value as Map<String, dynamic>;
          final name = (j['username'] ?? j['displayName'] ?? 'User').toString();
          final lp = (j['lpTotal'] as num?)?.toInt() ?? 0;
          final delta = (j['deltaRank'] as num?)?.toInt() ?? 0;
          final tier = (j['tier'] as String?) ?? 'Iron';
          final isMe = j['isMe'] as bool? ?? false;
          return _LeaderEntry(
            rank: e.key + 1,
            name: name,
            lpTotal: lp,
            delta: delta >= 0 ? '+$delta' : '$delta',
            tier: tier,
            isMe: isMe,
          );
        }).toList();
      }
    } catch (e, st) {
      reportError(e, st, reason: 'hall-of-fame:fetch-leaders');
    }
    return [];
  }

  Future<int> _fetchStreak() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return int.tryParse(prefs.getString('today_streak') ?? '0') ?? 0;
    } catch (e) {
      debugPrint('[HallOfFame] streak read best-effort skip: $e');
      return 0;
    }
  }

  List<_BadgeData> _computeBadges(
      List<ExerciseRankDto> ranks, int streak, Map<String, dynamic>? profile) {
    final tierOrder = {
      'Iron': 0,
      'Bronze': 1,
      'Silver': 2,
      'Gold': 3,
      'Platinum': 4,
      'Diamond': 5,
      'Olympian': 6
    };
    final maxTierIndex = ranks.isEmpty
        ? -1
        : ranks
            .map((r) => tierOrder[r.tier] ?? 0)
            .reduce((a, b) => a > b ? a : b);
    final totalLP = ranks.fold<int>(0, (s, r) => s + r.lpTotal);
    final workoutCount = (profile?['workoutCount'] as num?)?.toInt() ?? 0;

    return [
      _BadgeData(
        icon: AppIcons.bolt,
        label: 'First PR',
        tier: 'Bronze',
        color: const Color(0xFFCD7F32),
        unlocked: ranks.isNotEmpty,
      ),
      _BadgeData(
        icon: AppIcons.flame,
        label: '7-Day Streak',
        tier: 'Silver',
        color: const Color(0xFFC0C0C2),
        unlocked: streak >= 7,
      ),
      _BadgeData(
        icon: AppIcons.trophy,
        label: 'Top 5%',
        tier: 'Gold',
        color: const Color(0xFFFFB14A),
        unlocked: maxTierIndex >= 3, // Gold or above
      ),
      _BadgeData(
        icon: AppIcons.star,
        label: 'PR Master',
        tier: 'Gold',
        color: const Color(0xFFFFB14A),
        unlocked: ranks.length >= 5,
      ),
      _BadgeData(
        icon: AppIcons.target,
        label: '100+ Workouts',
        tier: 'Platinum',
        color: const Color(0xFFE5E4E2),
        unlocked: workoutCount >= 100,
      ),
      _BadgeData(
        icon: AppIcons.gym,
        label: 'Iron Will',
        tier: 'Diamond',
        color: const Color(0xFF4FC3F7),
        unlocked: totalLP >= 500,
      ),
    ];
  }

  String _myDisplayName() {
    final p = _myProfile;
    if (p == null) return 'You';
    final dn = (p['displayName'] ?? p['username'] ?? '').toString().trim();
    return dn.isNotEmpty ? dn : 'You';
  }

  int _myLpTotal() => _myRanks.fold(0, (s, r) => s + r.lpTotal);

  String _myBestTier() {
    if (_myRanks.isEmpty) return 'Iron';
    const order = [
      'Iron',
      'Bronze',
      'Silver',
      'Gold',
      'Platinum',
      'Diamond',
      'Olympian'
    ];
    int best = 0;
    for (final r in _myRanks) {
      final idx = order.indexOf(r.tier);
      if (idx > best) best = idx;
    }
    return order[best];
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _SubHeader(
              title: 'Hall of Fame',
              onBack: () => Navigator.pop(context),
              right: ExcludeSemantics(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: ZveltTokens.gradBtn,
                    boxShadow: [
                      BoxShadow(color: ZveltTokens.brandGlow, blurRadius: 16)
                    ],
                  ),
                  child: const Icon(AppIcons.trophy,
                      color: Colors.white, size: 18),
                ),
              ),
              safeTop: top,
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
                child: Center(
                    child: CircularProgressIndicator(color: ZveltTokens.brand)))
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.cloud_disabled,
                        color: ZveltTokens.text2, size: 40),
                    const SizedBox(height: ZveltTokens.s3),
                    Text(_error ?? 'Could not load data.',
                        style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                        textAlign: TextAlign.center),
                    const SizedBox(height: ZveltTokens.s4),
                    Semantics(
                      button: true,
                      label: 'Retry loading',
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: _load,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: ZveltTokens.s6,
                              vertical: ZveltTokens.s3),
                          decoration: BoxDecoration(
                            gradient: ZveltTokens.gradBtn,
                            borderRadius:
                                BorderRadius.circular(ZveltTokens.rPill),
                          ),
                          child: Text('Retry',
                              style: ZType.bodyS.copyWith(
                                  color: ZveltTokens.onBrand,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH, 0,
                  ZveltTokens.screenPaddingH, ZveltTokens.s8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    _MyStatCard(
                      name: _myDisplayName(),
                      lpTotal: _myLpTotal(),
                      tier: _myBestTier(),
                      streak: _myStreakDays,
                      rankCount: _myRanks.length,
                    ),
                    const SizedBox(height: ZveltTokens.s4),
                    if (_leaderboardReal && _leaderboard.length >= 3) ...[
                      _PodiumRow(entries: _leaderboard.take(3).toList()),
                      const SizedBox(height: ZveltTokens.s4),
                    ],
                    _LeaderboardCard(
                      entries: _leaderboardReal
                          ? _leaderboard.skip(3).toList()
                          : _buildFallbackLeaderboard(),
                      isReal: _leaderboardReal,
                    ),
                    const SizedBox(height: ZveltTokens.s4),
                    _BadgesCard(badges: _badges),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // When global leaderboard API is not available, show user's top exercises as a personal leaderboard
  List<_LeaderEntry> _buildFallbackLeaderboard() {
    if (_myRanks.isEmpty) return [];
    final sorted = List.of(_myRanks)
      ..sort((a, b) => b.lpTotal.compareTo(a.lpTotal));
    final top5 = sorted.take(5).toList();
    return top5.asMap().entries.map((e) {
      final r = e.value;
      return _LeaderEntry(
        rank: e.key + 1,
        name: r.exerciseName,
        lpTotal: r.lpTotal,
        delta: r.tier,
        tier: r.tier,
        isMe: true,
      );
    }).toList();
  }
}

// ─── My Stat Card (replaces Champion card when no global leaderboard) ─────────

class _MyStatCard extends StatelessWidget {
  const _MyStatCard({
    required this.name,
    required this.lpTotal,
    required this.tier,
    required this.streak,
    required this.rankCount,
  });
  final String name;
  final int lpTotal;
  final String tier;
  final int streak;
  final int rankCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          ZveltTokens.s6, ZveltTokens.s6, ZveltTokens.s6, ZveltTokens.s6),
      decoration: BoxDecoration(
        color: ZveltTokens.surfaceTinted,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowHero,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  ZveltTokens.brand.withValues(alpha: 0.18),
                  Colors.transparent
                ]),
              ),
            ),
          ),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: ZveltTokens.s3, vertical: ZveltTokens.s1),
                decoration: BoxDecoration(
                  color: ZveltTokens.surface,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(AppIcons.star,
                        size: 11, color: ZveltTokens.brand),
                    const SizedBox(width: ZveltTokens.s2),
                    Text('YOUR SEASON STATS',
                        style:
                            ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
                  ],
                ),
              ),
              const SizedBox(height: ZveltTokens.s4),
              Semantics(
                label: '$name, $tier tier, $rankCount ranked lifts',
                image: true,
                excludeSemantics: true,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 98,
                      height: 98,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: ZveltTokens.gradBtn,
                        boxShadow: [
                          BoxShadow(
                              color: ZveltTokens.brandGlow, blurRadius: 32)
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: _Avatar(name: name, size: 92),
                      ),
                    ),
                    Positioned(
                      top: -20,
                      child: CustomPaint(
                          size: const Size(44, 22), painter: _CrownPainter()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                style: ZType.displayM
                    .copyWith(fontSize: 34, color: ZveltTokens.text, height: 1),
              ),
              const SizedBox(height: ZveltTokens.s1),
              Text(
                '${tier.toUpperCase()} TIER · $rankCount RANKED LIFTS',
                style: ZType.eyebrow
                    .copyWith(fontSize: 11, color: ZveltTokens.text2),
              ),
              const SizedBox(height: ZveltTokens.s4),
              Semantics(
                container: true,
                label:
                    '${_fmt(lpTotal)} LP total, $rankCount exercises, $streak day streak',
                excludeSemantics: true,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ChampStat(label: 'LP Total', value: _fmt(lpTotal)),
                    _ChampStatDivider(),
                    _ChampStat(label: 'Exercises', value: '$rankCount'),
                    _ChampStatDivider(),
                    _ChampStat(label: 'Streak', value: '${streak}d'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _ChampStat extends StatelessWidget {
  const _ChampStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: ZType.num_
                  .copyWith(fontSize: 20, color: ZveltTokens.text, height: 1)),
          const SizedBox(height: ZveltTokens.s1),
          Text(label.toUpperCase(),
              style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
        ],
      );
}

class _ChampStatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s5),
        child: Container(width: 1, height: 28, color: ZveltTokens.hairline),
      );
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gold = Paint()..color = ZveltTokens.brand2;
    final outline = Paint()
      ..color = ZveltTokens.brandDeep
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..moveTo(2, size.height)
      ..lineTo(4, size.height * 0.3)
      ..lineTo(size.width * 0.34, size.height * 0.7)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width * 0.66, size.height * 0.7)
      ..lineTo(size.width - 4, size.height * 0.3)
      ..lineTo(size.width - 2, size.height)
      ..close();
    canvas.drawPath(path, gold);
    canvas.drawPath(path, outline);
    canvas.drawCircle(
        const Offset(6, 6), 2, Paint()..color = ZveltTokens.brand3);
    canvas.drawCircle(
        Offset(size.width / 2, 2), 2, Paint()..color = ZveltTokens.brand3);
    canvas.drawCircle(
        Offset(size.width - 6, 6), 2, Paint()..color = ZveltTokens.brand3);
  }

  @override
  bool shouldRepaint(_CrownPainter _) => false;
}

// ─── Podium Row ───────────────────────────────────────────────────────────────

class _PodiumRow extends StatelessWidget {
  const _PodiumRow({required this.entries});
  final List<_LeaderEntry> entries;

  @override
  Widget build(BuildContext context) {
    // Sort: [2nd, 1st, 3rd]
    final sorted = List.of(entries)..sort((a, b) => a.rank.compareTo(b.rank));
    final display =
        sorted.length >= 3 ? [sorted[1], sorted[0], sorted[2]] : sorted;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: display.map((p) {
        final height = p.rank == 1
            ? 110.0
            : p.rank == 2
                ? 80.0
                : 65.0;
        final podColor = p.rank == 1
            ? ZveltTokens.brand
            : p.rank == 2
                ? const Color(0xFFC0C0C2)
                : const Color(0xFFCD7F32);
        return Expanded(
          child: Semantics(
            container: true,
            label:
                'Rank ${p.rank}, ${p.name}${p.isMe ? ' (you)' : ''}, ${_fmtLp(p.lpTotal)} LP',
            excludeSemantics: true,
            child: Column(
              children: [
                if (p.rank == 1) ...[
                  Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(bottom: ZveltTokens.s1),
                      decoration: const BoxDecoration(
                          color: ZveltTokens.brand,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: ZveltTokens.brandGlow, blurRadius: 8)
                          ])),
                ],
                _Avatar(name: p.name, size: p.rank == 1 ? 64 : 52),
                const SizedBox(height: 6),
                Text(p.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: p.isMe ? ZveltTokens.info : ZveltTokens.text)),
                const SizedBox(height: 2),
                Text('${_fmtLp(p.lpTotal)} LP',
                    style: TextStyle(
                        fontSize: 11,
                        color: ZveltTokens.text2,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rSm)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        podColor.withValues(alpha: 0.22),
                        podColor.withValues(alpha: 0.08)
                      ],
                    ),
                    border: Border.all(color: podColor.withValues(alpha: 0.3)),
                  ),
                  child: Center(
                      child: Text('#${p.rank}',
                          style: ZType.stat
                              .copyWith(fontSize: 20, color: podColor))),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  static String _fmtLp(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

// ─── Leaderboard ─────────────────────────────────────────────────────────────

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({required this.entries, required this.isReal});
  final List<_LeaderEntry> entries;
  final bool isReal;

  @override
  Widget build(BuildContext context) {
    return _ZCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ZveltTokens.s5, ZveltTokens.s4, ZveltTokens.s5, ZveltTokens.s3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isReal ? 'LEADERBOARD' : 'YOUR TOP LIFTS',
                    style: ZType.eyebrow
                        .copyWith(fontSize: 11, color: ZveltTokens.text2),
                  ),
                ),
                if (!isReal)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: ZveltTokens.s2, vertical: ZveltTokens.s1),
                    decoration: BoxDecoration(
                      color: ZveltTokens.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                      border: Border.all(
                          color: ZveltTokens.info.withValues(alpha: 0.3)),
                    ),
                    child: const Text('PERSONAL',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: ZveltTokens.info,
                            letterSpacing: 1)),
                  ),
              ],
            ),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ZveltTokens.s5, 0, ZveltTokens.s5, ZveltTokens.s5),
              child: Text('Log workouts and earn LP to appear here.',
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
            )
          else
            ...List.generate(entries.length, (i) {
              final e = entries[i];
              final positive = e.delta.startsWith('+');
              final rowLabel = isReal
                  ? 'Rank ${e.rank}, ${e.name}${e.isMe ? ' (you)' : ''}, ${_fmtLp(e.lpTotal)} LP, ${e.tier}, ${e.delta} positions'
                  : 'Rank ${e.rank}, ${e.name}, ${_fmtLp(e.lpTotal)} LP, ${e.tier}';
              return Semantics(
                container: true,
                label: rowLabel,
                excludeSemantics: true,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: ZveltTokens.s3),
                  decoration: BoxDecoration(
                    color: e.isMe
                        ? ZveltTokens.info.withValues(alpha: 0.06)
                        : null,
                    border: i < entries.length - 1
                        ? Border(
                            bottom: BorderSide(color: ZveltTokens.hairline))
                        : null,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text('#${e.rank}',
                            style: ZType.stat.copyWith(
                                fontSize: 15,
                                color: e.isMe
                                    ? ZveltTokens.info
                                    : ZveltTokens.text2)),
                      ),
                      const SizedBox(width: 8),
                      _Avatar(name: e.name, size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                    child: Text(e.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: e.isMe
                                                ? ZveltTokens.info
                                                : ZveltTokens.text))),
                                if (e.isMe) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: ZveltTokens.s2, vertical: ZveltTokens.s1),
                                    decoration: BoxDecoration(
                                        color: ZveltTokens.info
                                            .withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(ZveltTokens.rPill)),
                                    child: Text('YOU',
                                        style: ZType.eyebrow.copyWith(
                                            fontSize: 7,
                                            color: ZveltTokens.info)),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                                isReal
                                    ? '${_fmtLp(e.lpTotal)} LP · ${e.tier}'
                                    : '${_fmtLp(e.lpTotal)} LP',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: ZveltTokens.text2,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      if (isReal)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: ZveltTokens.s2, vertical: ZveltTokens.s1),
                          decoration: BoxDecoration(
                            color: positive
                                ? ZveltTokens.success.withValues(alpha: 0.1)
                                : ZveltTokens.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                          ),
                          child: Text(e.delta,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: positive
                                      ? ZveltTokens.success
                                      : ZveltTokens.error)),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: ZveltTokens.s2, vertical: ZveltTokens.s1),
                          decoration: BoxDecoration(
                            color: ZveltTokens.border.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                          ),
                          child: Text(e.tier,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: ZveltTokens.text2)),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  static String _fmtLp(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

// ─── Badges ───────────────────────────────────────────────────────────────────

class _BadgesCard extends StatelessWidget {
  const _BadgesCard({required this.badges});
  final List<_BadgeData> badges;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('HONOR BADGES',
            style:
                ZType.eyebrow.copyWith(fontSize: 11, color: ZveltTokens.text2)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.88,
          children: badges.map((b) {
            final locked = !b.unlocked;
            return Semantics(
              container: true,
              label:
                  '${b.label}, ${b.tier} tier, ${locked ? 'locked' : 'unlocked'}',
              excludeSemantics: true,
              child: _ZCard(
                padding:
                    const EdgeInsets.symmetric(vertical: ZveltTokens.s4, horizontal: ZveltTokens.s2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: locked
                            ? ZveltTokens.surface2
                            : b.color.withValues(alpha: 0.15),
                        border: Border.all(
                            color: locked
                                ? ZveltTokens.border
                                : b.color.withValues(alpha: 0.4)),
                        boxShadow: locked
                            ? null
                            : [
                                BoxShadow(
                                    color: b.color.withValues(alpha: 0.25),
                                    blurRadius: 10)
                              ],
                      ),
                      child: Icon(b.icon,
                          size: 22,
                          color: locked
                              ? ZveltTokens.text2.withValues(alpha: 0.3)
                              : b.color),
                    ),
                    const SizedBox(height: 8),
                    Text(b.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: locked
                                ? ZveltTokens.text2.withValues(alpha: 0.4)
                                : ZveltTokens.text)),
                    const SizedBox(height: 2),
                    Text(locked ? 'LOCKED' : b.tier.toUpperCase(),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: locked
                                ? ZveltTokens.text2.withValues(alpha: 0.3)
                                : b.color,
                            letterSpacing: 1.2)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── Avatar ───────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final hue = (name.codeUnits.fold(0, (s, c) => s + c) % 360).toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSVColor.fromAHSV(1, hue, 0.7, 0.9).toColor(),
            HSVColor.fromAHSV(1, (hue + 30) % 360, 0.9, 0.6).toColor(),
          ],
        ),
      ),
      child: Center(
        child: Text(initials,
            style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: size * 0.38,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _ZCard extends StatelessWidget {
  const _ZCard({required this.child, this.padding = const EdgeInsets.all(18)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: child,
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader(
      {required this.title,
      required this.onBack,
      required this.right,
      required this.safeTop});
  final String title;
  final VoidCallback onBack;
  final Widget right;
  final double safeTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(ZveltTokens.screenPaddingH,
          safeTop + ZveltTokens.s2, ZveltTokens.screenPaddingH, ZveltTokens.s4),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onBack,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: ZveltTokens.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: ZveltTokens.border)),
                child: Icon(AppIcons.angle_small_left,
                    size: 16, color: ZveltTokens.text2),
              ),
            ),
          ),
          const SizedBox(width: ZveltTokens.s3),
          Expanded(
              child: Text(title,
                  style: ZType.h4.copyWith(color: ZveltTokens.text))),
          right,
        ],
      ),
    );
  }
}
