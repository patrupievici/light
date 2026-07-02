import 'package:flutter/material.dart';

import '../../services/social_challenge_service.dart';
import '../../services/friends_service.dart';
import '../../services/workout_service.dart';
import '../../theme/app_icons.dart';
import '../../theme/zvelt_tokens.dart';
import 'challenge_detail_screen.dart';

/// Create Challenge flow (Feed & Challenges v1) — Type → Setup → Friends →
/// Review → Send. Sends the scoring config so the backend engine auto-scores
/// from real workouts. Pops `true` on success.
class CreateChallengeFlow extends StatefulWidget {
  const CreateChallengeFlow({
    super.key,
    this.initialScoringType,
    this.initialExerciseId,
    this.initialExerciseName,
  });

  /// Optional presets — used by "Challenge this PR" to land on a pre-filled
  /// PR Battle for a specific lift, skipping the type-picker step.
  final String? initialScoringType;
  final String? initialExerciseId;
  final String? initialExerciseName;

  @override
  State<CreateChallengeFlow> createState() => _CreateChallengeFlowState();
}

class _ChallengeType {
  const _ChallengeType(this.id, this.name, this.desc, this.icon);
  final String id;
  final String name;
  final String desc;
  final IconData icon;
}

const _kTypes = <_ChallengeType>[
  _ChallengeType('workout_streak', 'Workout Streak', 'Most consecutive days trained', AppIcons.flame),
  _ChallengeType('most_workouts', 'Most Workouts', 'Most valid sessions in the period', AppIcons.gym),
  _ChallengeType('total_volume', 'Total Volume', 'Most kg lifted (weight × reps)', AppIcons.chart_line_up),
  _ChallengeType('pr_battle', 'Exercise PR Battle', 'Biggest e1RM gain on one lift', AppIcons.trophy),
  _ChallengeType('consistency', 'Consistency', 'Hit your target training days', AppIcons.calendar_check),
];

const _kDurations = [3, 7, 14, 30];

class _CreateChallengeFlowState extends State<CreateChallengeFlow> {
  final _challenges = SocialChallengeService();
  final _friendsSvc = FriendsService();
  final _workouts = WorkoutService();

  int _step = 0;
  String? _type;
  final _titleCtrl = TextEditingController();
  int _durationDays = 7;
  bool _startTomorrow = false;
  int _targetDays = 4;
  String? _exerciseId;
  String? _exerciseName;

  List<FriendSummary> _friends = const [];
  final Set<String> _selectedFriends = {};
  bool _loadingFriends = true;

  List<ExerciseDto> _exercises = const [];
  String _exSearch = '';
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _applyPreset();
  }

  void _applyPreset() {
    final preType = widget.initialScoringType;
    if (preType == null || !_kTypes.any((t) => t.id == preType)) return;
    _type = preType;
    _titleCtrl.text = _defaultTitle(preType);
    if (preType == 'pr_battle') {
      _exerciseId = widget.initialExerciseId;
      _exerciseName = widget.initialExerciseName;
      if (_exerciseId == null) _loadExercisesIfNeeded();
      if (_exerciseName != null) {
        // For PR Battle, name the challenge after the lift, e.g. "Bench PR Battle".
        _titleCtrl.text = '${widget.initialExerciseName} PR Battle';
      }
    }
    // Skip the type picker — the user already chose this from a PR card.
    _step = 1;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    try {
      final f = await _friendsSvc.listFriends();
      if (mounted) setState(() => _friends = f);
    } catch (_) {
      // empty roster is fine — a solo challenge is allowed.
    } finally {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  Future<void> _loadExercisesIfNeeded() async {
    if (_exercises.isNotEmpty) return;
    try {
      final res = await _workouts.getExercises();
      if (mounted) setState(() => _exercises = res.data);
    } catch (_) {}
  }

  String _defaultTitle(String typeId) =>
      _kTypes.firstWhere((t) => t.id == typeId).name;

  bool get _setupValid {
    if (_titleCtrl.text.trim().isEmpty) return false;
    if (_type == 'pr_battle' && _exerciseId == null) return false;
    return true;
  }

  void _next() {
    if (_step < 3) setState(() => _step++);
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _send() async {
    if (_type == null || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await _challenges.createScoredChallenge(
        scoringType: _type!,
        title: _titleCtrl.text.trim(),
        durationDays: _durationDays,
        startTomorrow: _startTomorrow,
        exerciseId: _type == 'pr_battle' ? _exerciseId : null,
        targetDays: _type == 'consistency' ? _targetDays.clamp(1, _durationDays) : null,
        inviteUserIds: _selectedFriends.toList(),
      );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Challenge created.')));
      if (id.isEmpty) {
        Navigator.of(context).pop(true);
        return;
      }
      // Land on the new challenge's detail + leaderboard.
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => ChallengeDetailScreen(
          challengeId: id,
          title: _titleCtrl.text.trim(),
          scoringType: _type,
          endsAt: DateTime.now().add(Duration(days: _durationDays + (_startTomorrow ? 1 : 0))),
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: ZveltTokens.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      appBar: AppBar(
        backgroundColor: ZveltTokens.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(AppIcons.angle_small_left),
          color: ZveltTokens.text,
          onPressed: _back,
        ),
        title: Text('New Challenge', style: ZType.h4.copyWith(color: ZveltTokens.text)),
      ),
      body: Column(
        children: [
          // step progress
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  Expanded(
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: i <= _step ? ZveltTokens.brand : ZveltTokens.surface3,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                  if (i < 3) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              child: switch (_step) {
                0 => _stepType(),
                1 => _stepSetup(),
                2 => _stepFriends(),
                _ => _stepReview(),
              },
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  // ── Step 0: type ─────────────────────────────────────────────────────────
  Widget _stepType() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What kind of challenge?',
            style: ZType.h2.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        for (final t in _kTypes) ...[
          _SelectCard(
            selected: _type == t.id,
            icon: t.icon,
            title: t.name,
            subtitle: t.desc,
            onTap: () => setState(() {
              _type = t.id;
              if (_titleCtrl.text.trim().isEmpty) _titleCtrl.text = _defaultTitle(t.id);
              if (t.id == 'pr_battle') _loadExercisesIfNeeded();
            }),
          ),
          const SizedBox(height: ZveltTokens.cardGap),
        ],
      ],
    );
  }

  // ── Step 1: setup ────────────────────────────────────────────────────────
  Widget _stepSetup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Set it up', style: ZType.h2.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Text('NAME', style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            boxShadow: ZveltTokens.shadowCard,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(
            controller: _titleCtrl,
            onChanged: (_) => setState(() {}),
            style: ZType.bodyM.copyWith(color: ZveltTokens.text),
            decoration: const InputDecoration(
              hintText: 'Challenge name',
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('DURATION', style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final d in _kDurations)
              _Chip(
                label: '$d days',
                selected: _durationDays == d,
                onTap: () => setState(() => _durationDays = d),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('START', style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
        const SizedBox(height: 8),
        Row(
          children: [
            _Chip(label: 'Now', selected: !_startTomorrow, onTap: () => setState(() => _startTomorrow = false)),
            const SizedBox(width: 8),
            _Chip(label: 'Tomorrow', selected: _startTomorrow, onTap: () => setState(() => _startTomorrow = true)),
          ],
        ),
        if (_type == 'consistency') ...[
          const SizedBox(height: 20),
          Text('TARGET DAYS', style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
          const SizedBox(height: 8),
          _Stepper(
            value: _targetDays,
            min: 1,
            max: _durationDays,
            onChanged: (v) => setState(() => _targetDays = v),
          ),
        ],
        if (_type == 'pr_battle') ...[
          const SizedBox(height: 20),
          Text('EXERCISE', style: ZType.eyebrow.copyWith(color: ZveltTokens.text2)),
          const SizedBox(height: 8),
          _exercisePicker(),
        ],
      ],
    );
  }

  Widget _exercisePicker() {
    if (_exerciseId != null) {
      return _SelectCard(
        selected: true,
        icon: AppIcons.gym,
        title: _exerciseName ?? 'Exercise',
        subtitle: 'Tap to change',
        onTap: () => setState(() {
          _exerciseId = null;
          _exerciseName = null;
        }),
      );
    }
    if (_exercises.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(ZveltTokens.s4),
        child: Center(child: CircularProgressIndicator(color: ZveltTokens.brand)),
      );
    }
    final q = _exSearch.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _exercises.take(20).toList()
        : _exercises.where((e) => e.name.toLowerCase().contains(q)).take(20).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            boxShadow: ZveltTokens.shadowCard,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(
            onChanged: (v) => setState(() => _exSearch = v),
            style: ZType.bodyM.copyWith(color: ZveltTokens.text),
            decoration: const InputDecoration(hintText: 'Search exercise…', border: InputBorder.none),
          ),
        ),
        const SizedBox(height: 8),
        for (final e in filtered)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SelectCard(
              selected: false,
              icon: AppIcons.gym,
              title: e.name,
              subtitle: '',
              onTap: () => setState(() {
                _exerciseId = e.id;
                _exerciseName = e.name;
              }),
            ),
          ),
      ],
    );
  }

  // ── Step 2: friends ──────────────────────────────────────────────────────
  Widget _stepFriends() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Invite friends', style: ZType.h2.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Optional — you can start solo and invite later.',
            style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
        const SizedBox(height: 16),
        if (_loadingFriends)
          const Padding(
            padding: EdgeInsets.all(ZveltTokens.s6),
            child: Center(child: CircularProgressIndicator(color: ZveltTokens.brand)),
          )
        else if (_friends.isEmpty)
          Text('No friends yet — add some from the Feed to challenge them.',
              style: ZType.bodyS.copyWith(color: ZveltTokens.text2))
        else
          for (final f in _friends) ...[
            _SelectCard(
              selected: _selectedFriends.contains(f.userId),
              icon: AppIcons.user,
              title: (f.displayName?.isNotEmpty ?? false) ? f.displayName! : (f.username ?? 'Athlete'),
              subtitle: f.username != null ? '@${f.username}' : '',
              onTap: () => setState(() {
                if (!_selectedFriends.add(f.userId)) _selectedFriends.remove(f.userId);
              }),
            ),
            const SizedBox(height: ZveltTokens.cardGap),
          ],
      ],
    );
  }

  // ── Step 3: review ───────────────────────────────────────────────────────
  Widget _stepReview() {
    final type = _kTypes.firstWhere((t) => t.id == _type, orElse: () => _kTypes.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review', style: ZType.h2.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rXl),
            boxShadow: ZveltTokens.shadowCard,
          ),
          padding: const EdgeInsets.all(ZveltTokens.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_titleCtrl.text.trim().isEmpty ? type.name : _titleCtrl.text.trim(),
                  style: ZType.h3.copyWith(color: ZveltTokens.text)),
              const SizedBox(height: 4),
              Text(type.name, style: ZType.bodyS.copyWith(color: ZveltTokens.brand, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              _reviewRow('Duration', '$_durationDays days'),
              _reviewRow('Starts', _startTomorrow ? 'Tomorrow' : 'Today'),
              if (_type == 'pr_battle') _reviewRow('Exercise', _exerciseName ?? '—'),
              if (_type == 'consistency') _reviewRow('Target', '${_targetDays.clamp(1, _durationDays)} days'),
              _reviewRow('Friends', _selectedFriends.isEmpty ? 'Solo' : '${_selectedFriends.length} invited'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
          Text(value, style: ZType.bodyM.copyWith(color: ZveltTokens.text, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Bottom bar ───────────────────────────────────────────────────────────
  Widget _bottomBar() {
    final canNext = switch (_step) {
      0 => _type != null,
      1 => _setupValid,
      _ => true,
    };
    final isLast = _step == 3;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
        child: Row(
          children: [
            if (_step > 0)
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: _sending ? null : _back,
                  child: const Text('Back'),
                ),
              ),
            if (_step > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: (isLast ? !_sending : canNext) ? (isLast ? _send : _next) : null,
                child: Text(isLast ? (_sending ? 'Sending…' : 'Send Challenge') : 'Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── shared bits ──────────────────────────────────────────────────────────────
class _SelectCard extends StatelessWidget {
  const _SelectCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? ZveltTokens.brandTint : ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            boxShadow: ZveltTokens.shadowCard,
            border: selected ? Border.all(color: ZveltTokens.brand, width: 1.5) : null,
          ),
          padding: const EdgeInsets.all(ZveltTokens.s4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected ? ZveltTokens.brand : ZveltTokens.brandTint,
                  borderRadius: BorderRadius.circular(ZveltTokens.rMd),
                ),
                child: Icon(icon, size: 20, color: selected ? ZveltTokens.onBrand : ZveltTokens.brand),
              ),
              const SizedBox(width: ZveltTokens.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.bodyM.copyWith(
                            color: selected ? ZveltTokens.brandDeep : ZveltTokens.text,
                            fontWeight: FontWeight.w700)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZType.bodyS.copyWith(color: ZveltTokens.text2)),
                    ],
                  ],
                ),
              ),
              if (selected) const Icon(AppIcons.check, size: 20, color: ZveltTokens.brand),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? ZveltTokens.brand : ZveltTokens.surface,
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          border: selected ? null : Border.all(color: ZveltTokens.border),
        ),
        child: Text(
          label,
          style: ZType.bodyS.copyWith(
            color: selected ? ZveltTokens.onBrand : ZveltTokens.text2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged});
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _btn(AppIcons.minus, value > min ? () => onChanged(value - 1) : null),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('$value', style: ZType.h3.copyWith(color: ZveltTokens.text)),
        ),
        _btn(AppIcons.plus, value < max ? () => onChanged(value + 1) : null),
      ],
    );
  }

  Widget _btn(IconData icon, VoidCallback? onTap) {
    final on = onTap != null;
    return Material(
      color: on ? ZveltTokens.brandTint : ZveltTokens.surface3,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: on ? ZveltTokens.brand : ZveltTokens.text3),
        ),
      ),
    );
  }
}
