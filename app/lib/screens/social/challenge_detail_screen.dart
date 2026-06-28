import 'package:flutter/material.dart';

import '../../services/social_challenge_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';

/// Challenge Detail (Feed & Challenges v1) — header + your-status card + full
/// leaderboard + rules, with accept/decline for a pending invite. Standings are
/// the backend's official scores (challenge-recalc.service).
class ChallengeDetailScreen extends StatefulWidget {
  const ChallengeDetailScreen({
    super.key,
    required this.challengeId,
    this.title,
    this.scoringType,
    this.endsAt,
    this.showAcceptDecline = false,
  });

  final String challengeId;
  final String? title;
  final String? scoringType;
  final DateTime? endsAt;
  final bool showAcceptDecline;

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen> {
  final _service = SocialChallengeService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  int _myRank = 0; // 0 = not in standings
  num _myTotal = 0;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _service.getStandings(widget.challengeId);
      final data = (s['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final me = s['me'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _rows = data;
        _myRank = (me?['rank'] as num?)?.toInt() ?? 0;
        _myTotal = (me?['total'] as num?) ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _accept() async {
    if (_acting) return;
    setState(() => _acting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.joinChallenge(widget.challengeId);
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _decline() async {
    if (_acting) return;
    setState(() => _acting = true);
    final nav = Navigator.of(context);
    try {
      await _service.declineChallenge(widget.challengeId);
      nav.pop();
    } catch (_) {
      if (mounted) setState(() => _acting = false);
    }
  }

  (String, String) _typeInfo() {
    switch (widget.scoringType) {
      case 'workout_streak':
        return ('Workout Streak', 'Most consecutive days with a valid workout. Score = longest streak ×100 + total valid days ×10.');
      case 'most_workouts':
        return ('Most Workouts', 'Most valid sessions (max 2 counted/day). Score = workouts ×100 + active days ×10.');
      case 'total_volume':
        return ('Total Volume', 'Most kg lifted (weight × reps) across valid workouts.');
      case 'pr_battle':
        return ('Exercise PR Battle', 'Biggest e1RM gain vs your 90-day baseline on the chosen lift.');
      case 'consistency':
        return ('Consistency', 'Hit your target days. Score = completed days ×100, +25 if you hit them all.');
      default:
        return ('Challenge', 'Log valid workouts to climb the leaderboard.');
    }
  }

  String _daysLeft() {
    final end = widget.endsAt;
    if (end == null) return '';
    final d = end.difference(DateTime.now()).inDays;
    if (d < 0) return 'Ended';
    if (d == 0) return 'Ends today';
    return '$d day${d == 1 ? '' : 's'} left';
  }

  @override
  Widget build(BuildContext context) {
    final (typeLabel, rulesText) = _typeInfo();
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(AppIcons.angle_small_left),
          color: ZveltTokens.text,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Challenge', style: ZType.h4.copyWith(color: ZveltTokens.text)),
      ),
      body: RefreshIndicator(
        color: ZveltTokens.brand,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
          children: [
            _headerCard(typeLabel),
            const SizedBox(height: ZveltTokens.s4),
            if (_myRank > 0) ...[
              _statusCard(),
              const SizedBox(height: ZveltTokens.s4),
            ],
            Text('LEADERBOARD', style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
            const SizedBox(height: ZveltTokens.s3),
            _leaderboard(),
            const SizedBox(height: ZveltTokens.s5),
            Text('RULES', style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
            const SizedBox(height: ZveltTokens.s3),
            _rulesCard(rulesText),
            if (widget.showAcceptDecline) ...[
              const SizedBox(height: ZveltTokens.s5),
              _acceptDecline(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _headerCard(String typeLabel) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: ZveltTokens.gradBrand,
        borderRadius: BorderRadius.circular(ZveltTokens.rXl),
        boxShadow: ZveltTokens.shadowHero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(typeLabel.toUpperCase(),
              style: ZType.eyebrow.copyWith(color: Colors.white.withValues(alpha: 0.85), letterSpacing: 0.1 * 10)),
          const SizedBox(height: 8),
          Text(widget.title?.trim().isNotEmpty == true ? widget.title!.trim() : typeLabel,
              style: ZType.h2.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          if (_daysLeft().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_daysLeft(), style: ZType.bodyS.copyWith(color: Colors.white.withValues(alpha: 0.85))),
          ],
        ],
      ),
    );
  }

  Widget _statusCard() {
    final gap = _myRank > 1 && _rows.length >= _myRank - 1
        ? ((_rows[_myRank - 2]['total'] as num?) ?? 0) - _myTotal
        : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZveltTokens.s5),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rXl),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Row(
        children: [
          Expanded(child: _stat('#$_myRank', 'your rank')),
          Expanded(child: _stat('${_myTotal % 1 == 0 ? _myTotal.toInt() : _myTotal}', 'points')),
          if (gap != null && gap > 0)
            Expanded(child: _stat('${gap % 1 == 0 ? gap.toInt() : gap}', 'to next')),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZType.h3.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: ZType.bodyS.copyWith(color: ZveltTokens.text2, fontSize: 11)),
        ],
      );

  Widget _leaderboard() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(ZveltTokens.s6),
        child: Center(child: CircularProgressIndicator(color: ZveltTokens.brand)),
      );
    }
    if (_error != null) {
      return Text(_error!, style: ZType.bodyS.copyWith(color: ZveltTokens.text2));
    }
    if (_rows.isEmpty) {
      return Text('No one on the board yet — log a valid workout to get on it.',
          style: ZType.bodyS.copyWith(color: ZveltTokens.text2));
    }
    return Container(
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rXl),
        boxShadow: ZveltTokens.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < _rows.length; i++) _row(i),
        ],
      ),
    );
  }

  Widget _row(int i) {
    final r = _rows[i];
    final rank = i + 1;
    final isMe = rank == _myRank;
    final name = (r['displayName'] as String?)?.trim();
    final total = (r['total'] as num?) ?? 0;
    return Container(
      color: isMe ? ZveltTokens.brandTint : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$rank',
                textAlign: TextAlign.center,
                style: ZType.bodyM.copyWith(
                    color: rank <= 3 ? ZveltTokens.brand : ZveltTokens.text3,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: ZveltTokens.s2),
          Expanded(
            child: Text(name?.isNotEmpty == true ? name! : 'Athlete',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZType.bodyM.copyWith(
                    color: ZveltTokens.text,
                    fontWeight: isMe ? FontWeight.w700 : FontWeight.w600)),
          ),
          Text('${total % 1 == 0 ? total.toInt() : total} pts',
              style: ZType.bodyM.copyWith(
                  color: isMe ? ZveltTokens.brandDeep : ZveltTokens.text,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _rulesCard(String rulesText) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZveltTokens.s5),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rXl),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rulesText, style: ZType.bodyS.copyWith(color: ZveltTokens.text, height: 1.5)),
          const SizedBox(height: 10),
          Text('Valid workout = 15 min · 3 exercises · 6 completed sets.',
              style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
        ],
      ),
    );
  }

  Widget _acceptDecline() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _acting ? null : _decline,
            child: const Text('Decline'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _acting ? null : _accept,
            child: Text(_acting ? '…' : 'Accept challenge'),
          ),
        ),
      ],
    );
  }
}
