import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zvelt_app/theme/app_icons.dart';

import '../../models/social_challenge.dart';
import '../../services/social_challenge_service.dart';
import '../../theme/zvelt_tokens.dart';
import '../../widgets/zvelt_empty_state.dart';
import '../../widgets/zvelt_error_state.dart';
import 'create_challenge_flow.dart';

/// CHALLENGES (mockup 10): Active / My Challenges tabs of challenge cards with
/// inline leaderboards, + Create Challenge. Replaces the old configurator-first
/// "Race Hub" as the entry from the Feed. Server-backed via SocialChallengeService.
class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _Standings {
  _Standings({required this.rows, required this.myRank, required this.myTotal});
  final List<Map<String, dynamic>> rows; // ordered; index 0 = rank 1
  final int myRank; // 0 = not in standings
  final double myTotal;
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  final _service = SocialChallengeService();

  List<SocialChallenge> _all = [];
  final Map<String, _Standings> _standings = {};
  bool _loading = true;
  bool _error = false;
  int _tab = 0; // 0 = Active, 1 = My Challenges
  final Set<String> _togglingJoin = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final list = await _service.loadActive();
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
      // Best-effort standings per challenge — never blocks the list render.
      for (final c in list) {
        _service.getStandings(c.id).then((res) {
          if (!mounted) return;
          final rows = ((res['data'] as List<dynamic>?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final me = res['me'] as Map<String, dynamic>?;
          setState(() {
            _standings[c.id] = _Standings(
              rows: rows,
              myRank: (me?['rank'] as num?)?.toInt() ?? 0,
              myTotal: (me?['total'] as num?)?.toDouble() ?? 0,
            );
          });
        }).catchError((_) {});
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
      if (mounted) setState(() => _loading = false);
    }
  }

  List<SocialChallenge> get _visible {
    final now = DateTime.now();
    if (_tab == 0) {
      return _all.where((c) => c.endsAt.isAfter(now)).toList();
    }
    return _all.where((c) => c.isMine).toList();
  }

  Future<void> _create() async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const CreateChallengeFlow(),
    ));
    if (mounted) unawaited(_load());
  }

  Future<void> _toggleJoin(SocialChallenge c) async {
    if (_togglingJoin.contains(c.id)) return;
    setState(() => _togglingJoin.add(c.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (c.joined) {
        await _service.leaveChallenge(c.id);
      } else {
        await _service.joinChallenge(c.id);
      }
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: ZveltTokens.error,
      ));
    } finally {
      if (mounted) setState(() => _togglingJoin.remove(c.id));
    }
  }

  void _viewLeaderboard(SocialChallenge c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _LeaderboardSheet(challenge: c, standings: _standings[c.id]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(ZveltTokens.s4, top + ZveltTokens.s2,
                ZveltTokens.s4, ZveltTokens.s3),
            child: Row(
              children: [
                _CircleBtn(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Icon(AppIcons.angle_small_left,
                      size: 16, color: ZveltTokens.text2),
                ),
                const SizedBox(width: ZveltTokens.s3),
                Text('Challenges',
                    style: ZType.h3.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          // ── Active / My tabs ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4),
            child: _SegTabs(
              labels: const ['Active', 'My Challenges'],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          const SizedBox(height: ZveltTokens.s4),
          // ── List ────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: ZveltTokens.brand))
                : _error
                    ? ZveltErrorState(
                        title: "Couldn't load challenges", onRetry: _load)
                    : RefreshIndicator(
                        color: ZveltTokens.brand,
                        onRefresh: _load,
                        child: _visible.isEmpty
                            ? ListView(children: [
                                const SizedBox(height: 80),
                                ZveltEmptyState(
                                  compact: true,
                                  icon: AppIcons.trophy,
                                  title: _tab == 0
                                      ? 'No active challenges'
                                      : 'You haven\'t created any',
                                  subtitle:
                                      'Create one and invite your friends.',
                                ),
                              ])
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                    ZveltTokens.s4,
                                    0,
                                    ZveltTokens.s4,
                                    ZveltTokens.s10),
                                itemCount: _visible.length,
                                itemBuilder: (_, i) {
                                  final c = _visible[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: ZveltTokens.cardGap),
                                    child: _ChallengeCard(
                                      challenge: c,
                                      standings: _standings[c.id],
                                      joining: _togglingJoin.contains(c.id),
                                      onView: () => _viewLeaderboard(c),
                                      onToggleJoin: () => _toggleJoin(c),
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
          // ── Create button ───────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(ZveltTokens.s4, ZveltTokens.s2,
                  ZveltTokens.s4, ZveltTokens.s3),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.brand,
                    foregroundColor: ZveltTokens.onBrand,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rMd)),
                  ),
                  onPressed: _create,
                  icon: const Icon(AppIcons.plus, size: 18),
                  label: Text('Create Challenge',
                      style: ZType.h4.copyWith(color: ZveltTokens.onBrand)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.challenge,
    required this.standings,
    required this.joining,
    required this.onView,
    required this.onToggleJoin,
  });

  final SocialChallenge challenge;
  final _Standings? standings;
  final bool joining;
  final VoidCallback onView;
  final VoidCallback onToggleJoin;

  @override
  Widget build(BuildContext context) {
    final daysLeft = challenge.endsAt.difference(DateTime.now()).inDays;
    final daysLabel = daysLeft <= 0
        ? 'Ends today'
        : '$daysLeft day${daysLeft == 1 ? '' : 's'} left';
    final rows = standings?.rows ?? const [];
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
          Row(
            children: [
              Expanded(
                child: Text(challenge.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZType.h4.copyWith(color: ZveltTokens.text)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                ),
                child: Text(daysLabel,
                    style: ZType.monoXS.copyWith(
                        color: ZveltTokens.brandDeep,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s3),
          if (rows.isEmpty)
            Text(
              standings == null
                  ? 'Loading standings…'
                  : 'No one has joined yet — be the first.',
              style: ZType.bodyS.copyWith(color: ZveltTokens.text3),
            )
          else
            for (var i = 0; i < rows.length && i < 3; i++)
              _leaderRow(i, rows[i], standings!.myRank == i + 1),
          if ((standings?.myRank ?? 0) > 3) ...[
            Divider(height: ZveltTokens.s4, color: ZveltTokens.hairline),
            _leaderRow(standings!.myRank - 1,
                {'displayName': 'You', 'total': standings!.myTotal}, true),
          ],
          const SizedBox(height: ZveltTokens.s3),
          Row(
            children: [
              // isMine guard: creators are auto-accepted server-side, so a
              // "Join" CTA on your OWN challenge is always wrong — the offline
              // local copy of an unsynced draft could still carry joined=false.
              if (!challenge.joined && !challenge.isMine)
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ZveltTokens.brandDeep,
                      side: const BorderSide(color: ZveltTokens.brand),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(ZveltTokens.rMd)),
                    ),
                    onPressed: joining ? null : onToggleJoin,
                    child: joining
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Join'),
                  ),
                ),
              if (!challenge.joined && !challenge.isMine)
                const SizedBox(width: ZveltTokens.s2),
              Expanded(
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: ZveltTokens.bg2,
                    foregroundColor: ZveltTokens.text,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(ZveltTokens.rMd)),
                  ),
                  onPressed: onView,
                  child: const Text('View Leaderboard'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _leaderRow(int idx, Map<String, dynamic> s, bool isMe) {
    const medal = [Color(0xFFFFB020), Color(0xFFB6BCC8), Color(0xFFCD7F45)];
    final total = (s['total'] as num?)?.toDouble() ?? 0;
    final totalLabel =
        total % 1 == 0 ? total.toInt().toString() : total.toStringAsFixed(1);
    final name = (s['displayName'] as String?) ?? 'Athlete';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('${idx + 1}',
                style: ZType.num_.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: idx < 3 ? medal[idx] : ZveltTokens.text3)),
          ),
          const SizedBox(width: ZveltTokens.s2),
          Expanded(
            child: Text(isMe ? 'You' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZType.bodyM.copyWith(
                    color: isMe ? ZveltTokens.brandDeep : ZveltTokens.text,
                    fontWeight: isMe ? FontWeight.w700 : FontWeight.w400)),
          ),
          Text(totalLabel,
              style:
                  ZType.num_.copyWith(color: ZveltTokens.text2, fontSize: 13)),
        ],
      ),
    );
  }
}

class _LeaderboardSheet extends StatelessWidget {
  const _LeaderboardSheet({required this.challenge, required this.standings});
  final SocialChallenge challenge;
  final _Standings? standings;

  @override
  Widget build(BuildContext context) {
    final rows = standings?.rows ?? const [];
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
      ),
      padding: EdgeInsets.fromLTRB(
          ZveltTokens.s5,
          ZveltTokens.s4,
          ZveltTokens.s5,
          MediaQuery.paddingOf(context).bottom + ZveltTokens.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: ZveltTokens.surface3,
                  borderRadius: BorderRadius.circular(ZveltTokens.rPill)),
            ),
          ),
          const SizedBox(height: ZveltTokens.s4),
          Text(challenge.title, style: ZType.h3),
          const SizedBox(height: ZveltTokens.s4),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ZveltTokens.s5),
              child: Text('No one has joined yet — be the first.',
                  style: ZType.bodyS.copyWith(color: ZveltTokens.text3)),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final isMe = (standings?.myRank ?? 0) == i + 1;
                  final total = (rows[i]['total'] as num?)?.toDouble() ?? 0;
                  final totalLabel = total % 1 == 0
                      ? total.toInt().toString()
                      : total.toStringAsFixed(1);
                  final name = (rows[i]['displayName'] as String?) ?? 'Athlete';
                  return Container(
                    margin: const EdgeInsets.only(bottom: ZveltTokens.s1),
                    padding: const EdgeInsets.symmetric(
                        horizontal: ZveltTokens.s3, vertical: ZveltTokens.s3),
                    decoration: BoxDecoration(
                      color: isMe ? ZveltTokens.brandTint : ZveltTokens.bg2,
                      borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                            width: 26,
                            child: Text('${i + 1}',
                                style: ZType.num_.copyWith(fontSize: 14))),
                        Expanded(
                          child: Text(isMe ? 'You' : name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ZType.bodyM.copyWith(
                                  color: isMe
                                      ? ZveltTokens.brandDeep
                                      : ZveltTokens.text,
                                  fontWeight: isMe
                                      ? FontWeight.w700
                                      : FontWeight.w400)),
                        ),
                        Text(totalLabel,
                            style:
                                ZType.num_.copyWith(color: ZveltTokens.text)),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SegTabs extends StatelessWidget {
  const _SegTabs(
      {required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ZveltTokens.bg2,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        index == i ? ZveltTokens.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(ZveltTokens.rPill),
                    boxShadow: index == i ? ZveltTokens.shadowCard : null,
                  ),
                  child: Text(
                    labels[i],
                    style: ZType.bodyS.copyWith(
                      color: index == i ? ZveltTokens.text : ZveltTokens.text3,
                      fontWeight:
                          index == i ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZveltTokens.surface,
      shape: CircleBorder(side: BorderSide(color: ZveltTokens.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 40, height: 40, child: Center(child: child)),
      ),
    );
  }
}
