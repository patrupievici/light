import 'package:flutter/material.dart';

import '../../../theme/app_icons.dart';
import '../../../theme/zvelt_tokens.dart';

/// Which primary card the Quick Start hub leads with.
enum QsPrimaryKind { resume, next, completed, choose }

/// Immutable data backing the Quick Start hub's primary card.
class QsHubData {
  const QsHubData({
    this.primary = QsPrimaryKind.choose,
    this.resumeTitle = 'Workout',
    this.resumeMeta = '',
    this.resumeProgress = 0.0, // 0..1
    this.nextTitle = 'Next Workout',
    this.nextMuscles = '',
    this.nextMeta = '',
    this.completedTitle = 'Workout',
    this.completedSummary = '',
  });

  final QsPrimaryKind primary;

  // resume
  final String resumeTitle, resumeMeta;
  final double resumeProgress;

  // next
  final String nextTitle, nextMuscles, nextMeta;

  // completed
  final String completedTitle, completedSummary;
}

/// QUICK START HUB — the ⚡ lightning full-screen sheet, 1:1 with the handoff.
///
/// A full-screen scrollable screen with four internal flows switched by the
/// internal [_qsFlow] state (null = Hub · 'smart' · 'cardio' ·
/// push|pull|legs|fullbody = template preview). Purely presentational: it owns
/// only its flow navigation and the Smart-builder pill selections; every real
/// action exits via a callback.
class QuickStartHub extends StatefulWidget {
  const QuickStartHub({
    super.key,
    this.data = const QsHubData(),
    this.aiTitle,
    this.onAiWorkout,
    this.onClose,
    this.onResume,
    this.onStartNext,
    this.onPreviewNext,
    this.onEditNext,
    this.onSkipNext,
    this.onShareCompleted,
    this.onLogAnother,
    this.onChooseProgram,
    this.onStartEmpty,
    this.onGenerateSmart, // void Function(String goal, int duration, String equip)
    this.onCardio, // ValueChanged<String> kind: run|walk|bike|custom
    this.onTemplate, // ValueChanged<String> id: push|pull|legs|fullbody (start)
    this.onBrowseLibrary,
    this.templates = const <QsTemplate>[
      QsTemplate('push', 'Push', 'Chest · Shoulders · Triceps', 6, [
        ('Bench Press', '4×8 · 70kg'),
        ('Incline DB Press', '3×10 · 22kg'),
        ('Shoulder Press', '3×10 · 50kg'),
        ('Lateral Raise', '3×15 · 8kg'),
        ('Triceps Pushdown', '3×12 · 30kg'),
        ('Overhead Ext.', '3×12 · 24kg'),
      ]),
      QsTemplate('pull', 'Pull', 'Back · Biceps', 6, [
        ('Pull-up', '4×6 · BW'),
        ('Barbell Row', '4×8 · 70kg'),
        ('Cable Row', '3×10 · 55kg'),
        ('Face Pull', '3×15 · 20kg'),
        ('Barbell Curl', '3×10 · 32kg'),
        ('Hammer Curl', '3×12 · 14kg'),
      ]),
      QsTemplate('legs', 'Legs', 'Quads · Hamstrings · Glutes', 5, [
        ('Squat', '4×5 · 100kg'),
        ('Romanian DL', '3×8 · 80kg'),
        ('Leg Press', '3×12 · 120kg'),
        ('Leg Curl', '3×12 · 45kg'),
        ('Calf Raise', '4×15 · 60kg'),
      ]),
      QsTemplate('fullbody', 'Full Body', 'Chest · Back · Legs · Shoulders', 5, [
        ('Squat', '3×8 · 80kg'),
        ('Pull-up', '3×6 · BW'),
        ('Bench Press', '3×8 · 65kg'),
        ('Romanian DL', '3×8 · 70kg'),
        ('Shoulder Press', '3×10 · 40kg'),
      ]),
    ],
  });

  final QsHubData data;
  final List<QsTemplate> templates;

  /// Title of the AI coach's cached suggestion — subtitle of the AI tile when
  /// available. Null keeps honest generic copy (never a fabricated title).
  final String? aiTitle;
  final VoidCallback? onAiWorkout;
  final VoidCallback? onClose,
      onResume,
      onStartNext,
      onPreviewNext,
      onEditNext,
      onSkipNext,
      onShareCompleted,
      onLogAnother,
      onChooseProgram,
      onStartEmpty,
      onBrowseLibrary;
  final void Function(String goal, int duration, String equip)? onGenerateSmart;
  final ValueChanged<String>? onCardio;
  final ValueChanged<String>? onTemplate;

  @override
  State<QuickStartHub> createState() => _QuickStartHubState();
}

/// Immutable data backing one Quick Start template card / preview.
class QsTemplate {
  const QsTemplate(this.id, this.name, this.muscles, this.count, this.exercises);
  final String id, name, muscles;
  final int count;

  /// (exercise name, "Sets×Reps · Weight" detail)
  final List<(String, String)> exercises;
}

class _QuickStartHubState extends State<QuickStartHub> {
  /// null = Hub · 'smart' · 'cardio' · push|pull|legs|fullbody = preview.
  String? _qsFlow;

  // Smart-builder pill state.
  String _smartGoal = 'muscle';
  int _smartDuration = 45;
  String _smartEquip = 'gym';

  QsTemplate _templateById(String id) => widget.templates
      .firstWhere((t) => t.id == id, orElse: () => widget.templates.first);

  void _go(String? flow) => setState(() => _qsFlow = flow);

  @override
  Widget build(BuildContext context) {
    final Widget body;
    switch (_qsFlow) {
      case 'smart':
        body = _smartFlow();
      case 'cardio':
        body = _cardioFlow();
      case null:
        body = _hubFlow();
      default:
        body = _templateFlow(_templateById(_qsFlow!));
    }

    return Scaffold(
      backgroundColor: ZveltTokens.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 50),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _grabber(),
              body,
            ],
          ),
        ),
      ),
    );
  }

  // ── Top grabber pill → onClose ──────────────────────────────────────────────
  Widget _grabber() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 22),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onClose,
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: ZveltTokens.surface3,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FLOW 1 — Hub
  // ════════════════════════════════════════════════════════════════════════════
  Widget _hubFlow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _hubHeader(),
        _primaryCard(),
        _sectionLabel('SHORTCUTS'),
        _shortcuts(),
        if (widget.onAiWorkout != null) ...[
          const SizedBox(height: 24),
          _sectionLabel("COACH'S PICK"),
          _aiWorkoutCard(),
        ],
        const SizedBox(height: 24),
        _sectionLabel('TEMPLATES'),
        _templatesGrid(),
        const SizedBox(height: 24),
        _browseLibrary(),
      ],
    );
  }

  // A. Header
  Widget _hubHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Quick Start',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    letterSpacing: -0.02 * 28,
                    height: 1.1,
                    color: ZveltTokens.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Start your next workout or choose what to train.',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontWeight: FontWeight.w400,
                    fontSize: 13,
                    height: 1.4,
                    color: ZveltTokens.text2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ClipRect(
            child: Transform.translate(
              offset: const Offset(0, 18),
              child: Image.asset(
                'assets/mascot/m9.png',
                height: 110,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // B. Primary card — exactly one based on data.primary.
  Widget _primaryCard() {
    switch (widget.data.primary) {
      case QsPrimaryKind.resume:
        return _resumeCard();
      case QsPrimaryKind.next:
        return _nextCard();
      case QsPrimaryKind.completed:
        return _completedCard();
      case QsPrimaryKind.choose:
        return _chooseCard();
    }
  }

  Widget _resumeCard() {
    final d = widget.data;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE85D04), Color(0xFFF48C06)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x61E85D04),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _superLabel('UNFINISHED WORKOUT'),
          const SizedBox(height: 8),
          Text(d.resumeTitle, style: _cardTitle()),
          if (d.resumeMeta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(d.resumeMeta, style: _whiteBody(0.88)),
          ],
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: LinearProgressIndicator(
              value: d.resumeProgress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          _solidCta(
            label: 'Resume →',
            bg: Colors.white,
            fg: const Color(0xFFE85D04),
            onTap: widget.onResume,
          ),
        ],
      ),
    );
  }

  Widget _nextCard() {
    final d = widget.data;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: ZveltTokens.gradBrand,
        borderRadius: BorderRadius.circular(24),
        boxShadow: ZveltTokens.glowBrand,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _superLabel('NEXT WORKOUT'),
          const SizedBox(height: 8),
          Text(d.nextTitle, style: _cardTitle()),
          if (d.nextMuscles.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(d.nextMuscles, style: _whiteBody(0.88)),
          ],
          if (d.nextMeta.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(d.nextMeta, style: _whiteBody(0.75)),
          ],
          const SizedBox(height: 16),
          _solidCta(
            label: 'Start →',
            bg: Colors.white,
            fg: ZveltTokens.brand,
            onTap: widget.onStartNext,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _textBtn('Preview', widget.onPreviewNext),
              const SizedBox(width: 8),
              _textBtn('Edit', widget.onEditNext),
              const SizedBox(width: 8),
              _textBtn('Skip', widget.onSkipNext),
            ],
          ),
        ],
      ),
    );
  }

  Widget _completedCard() {
    final d = widget.data;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF34D399), Color(0xFF10B981)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x5C10B981),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _superLabel('WORKOUT COMPLETED'),
          const SizedBox(height: 8),
          Text(d.completedTitle, style: _cardTitle()),
          if (d.completedSummary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(d.completedSummary, style: _whiteBody(0.9)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _solidCta(
                  label: 'Share to Feed',
                  bg: Colors.white,
                  fg: const Color(0xFF10B981),
                  onTap: widget.onShareCompleted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _solidCta(
                  label: 'Log another',
                  bg: Colors.white.withValues(alpha: 0.22),
                  fg: Colors.white,
                  onTap: widget.onLogAnother,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chooseCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No active program yet',
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: ZveltTokens.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Start free or choose a training plan.',
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontWeight: FontWeight.w400,
              fontSize: 13,
              height: 1.4,
              color: ZveltTokens.text2,
            ),
          ),
          const SizedBox(height: 16),
          _solidCta(
            label: 'Choose a program →',
            bg: ZveltTokens.brandTint,
            fg: ZveltTokens.brand,
            padding: 13,
            onTap: widget.onChooseProgram,
          ),
        ],
      ),
    );
  }

  // C. Shortcuts
  Widget _shortcuts() {
    return Row(
      children: [
        Expanded(child: _shortcutCard(AppIcons.plus, 'Empty', widget.onStartEmpty)),
        const SizedBox(width: 12),
        Expanded(child: _shortcutCard(AppIcons.sparkles, 'Smart', () => _go('smart'))),
        const SizedBox(width: 12),
        Expanded(child: _shortcutCard(AppIcons.running, 'Cardio', () => _go('cardio'))),
      ],
    );
  }

  Widget _shortcutCard(IconData icon, String label, VoidCallback? onTap) {
    return Material(
      color: ZveltTokens.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: ZveltTokens.shadowCard,
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _iconTile(icon, 40, 12, 20),
              const SizedBox(height: 10),
              Text(
                label,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: ZveltTokens.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // C½. AI Workout — the coach's suggested session (preview → start).
  Widget _aiWorkoutCard() {
    return Semantics(
      button: true,
      label: 'AI workout — preview the coach\'s suggested session',
      child: Material(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onAiWorkout,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: ZveltTokens.shadowCard,
            ),
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                _iconTile(AppIcons.sparkles, 44, 14, 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AI Workout',
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: ZveltTokens.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.aiTitle ?? 'Built for you by Zvelt Coach',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                          height: 1.3,
                          color: ZveltTokens.text2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(AppIcons.angle_small_right,
                    size: 20, color: ZveltTokens.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // D. Templates
  Widget _templatesGrid() {
    final templates = widget.templates;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < templates.length; r += 2) ...[
          if (r > 0) const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _templateCard(templates[r])),
              const SizedBox(width: 12),
              if (r + 1 < templates.length)
                Expanded(child: _templateCard(templates[r + 1]))
              else
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ],
      ],
    );
  }

  Widget _templateCard(QsTemplate t) {
    return Material(
      color: ZveltTokens.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _go(t.id),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: ZveltTokens.shadowCard,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.name,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: -0.01 * 18,
                  color: ZveltTokens.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.muscles,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  height: 1.4,
                  color: ZveltTokens.text2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${t.count} exercises →',
                style: const TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  color: ZveltTokens.brand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // E. Browse library
  Widget _browseLibrary() {
    return Center(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onBrowseLibrary,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              'Browse library →',
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: ZveltTokens.text2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FLOW 2 — Smart
  // ════════════════════════════════════════════════════════════════════════════
  Widget _smartFlow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _flowHeader('Smart Workout'),
        const SizedBox(height: 24),
        _sectionLabel('GOAL'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pill('Muscle gain', _smartGoal == 'muscle', () => setState(() => _smartGoal = 'muscle')),
            _pill('Strength', _smartGoal == 'strength', () => setState(() => _smartGoal = 'strength')),
            _pill('Fat loss', _smartGoal == 'fat', () => setState(() => _smartGoal = 'fat')),
            _pill('General fitness', _smartGoal == 'fitness', () => setState(() => _smartGoal = 'fitness')),
          ],
        ),
        const SizedBox(height: 20),
        _sectionLabel('DURATION'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in [30, 45, 60])
              _pill('$m min', _smartDuration == m, () => setState(() => _smartDuration = m)),
          ],
        ),
        const SizedBox(height: 20),
        _sectionLabel('EQUIPMENT'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _pill('Gym', _smartEquip == 'gym', () => setState(() => _smartEquip = 'gym')),
            _pill('Dumbbells', _smartEquip == 'dumbbells', () => setState(() => _smartEquip = 'dumbbells')),
            _pill('Bodyweight', _smartEquip == 'bodyweight', () => setState(() => _smartEquip = 'bodyweight')),
          ],
        ),
        const SizedBox(height: 28),
        _brandCta(
          'Generate Smart Workout ⚡',
          () => widget.onGenerateSmart?.call(_smartGoal, _smartDuration, _smartEquip),
        ),
      ],
    );
  }

  Widget _pill(String label, bool active, VoidCallback onTap) {
    return Material(
      color: active ? ZveltTokens.brand : ZveltTokens.bg2,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: active ? Colors.white : ZveltTokens.text2,
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FLOW 3 — Cardio
  // ════════════════════════════════════════════════════════════════════════════
  Widget _cardioFlow() {
    const rows = <(String, IconData, String, String)>[
      ('run', AppIcons.running, 'Run', 'Outdoor or treadmill · timer + distance'),
      ('walk', AppIcons.navigation, 'Walk', 'Incline, leisure or power walk'),
      ('bike', AppIcons.bike, 'Bike', 'Road bike or stationary cycling'),
      ('custom', AppIcons.bolt, 'Custom cardio', 'Any activity — log duration + effort'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _flowHeader('Cardio'),
        const SizedBox(height: 24),
        for (final r in rows) _cardioRow(r.$1, r.$2, r.$3, r.$4),
      ],
    );
  }

  Widget _cardioRow(String kind, IconData icon, String title, String desc) {
    final dashed = kind == 'custom';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onCardio?.call(kind),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: ZveltTokens.shadowCard,
              border: dashed ? Border.all(color: ZveltTokens.surface3, width: 2) : null,
            ),
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                _iconTile(icon, 44, 14, 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: ZveltTokens.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        desc,
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                          height: 1.3,
                          color: ZveltTokens.text2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(AppIcons.angle_small_right, size: 20, color: ZveltTokens.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FLOW 4 — Template preview
  // ════════════════════════════════════════════════════════════════════════════
  Widget _templateFlow(QsTemplate t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _flowHeader(t.name, subtitle: t.muscles),
        const SizedBox(height: 20),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ZveltTokens.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: ZveltTokens.shadowCard,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < t.exercises.length; i++)
                _previewRow(t.exercises[i], last: i == t.exercises.length - 1),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _brandCta('Start ${t.name} →', () => widget.onTemplate?.call(t.id)),
      ],
    );
  }

  Widget _previewRow((String, String) ex, {required bool last}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: ZveltTokens.border)),
      ),
      child: Row(
        children: [
          _iconTile(AppIcons.gym, 44, 14, 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ex.$1,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: ZveltTokens.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  ex.$2,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: ZveltTokens.text2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared bits ─────────────────────────────────────────────────────────────
  Widget _flowHeader(String title, {String? subtitle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Material(
          color: ZveltTokens.surface,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _go(null),
            customBorder: const CircleBorder(),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: ZveltTokens.shadowCard,
              ),
              child: Icon(AppIcons.arrow_small_left, size: 22, color: ZveltTokens.text),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: ZveltTokens.text,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontWeight: FontWeight.w400,
                    fontSize: 13,
                    color: ZveltTokens.text2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: ZveltTokens.fontPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.1 * 11,
          color: ZveltTokens.text2,
        ),
      ),
    );
  }

  Widget _iconTile(IconData icon, double size, double radius, double iconSize) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ZveltTokens.brandTint,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, color: ZveltTokens.brand, size: iconSize),
    );
  }

  Widget _superLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: ZveltTokens.fontPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: 0.1 * 11,
        color: Colors.white.withValues(alpha: 0.8),
      ),
    );
  }

  TextStyle _cardTitle() => const TextStyle(
        fontFamily: ZveltTokens.fontPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 24,
        height: 1.2,
        color: Colors.white,
      );

  TextStyle _whiteBody(double alpha) => TextStyle(
        fontFamily: ZveltTokens.fontPrimary,
        fontWeight: FontWeight.w400,
        fontSize: 13,
        height: 1.4,
        color: Colors.white.withValues(alpha: alpha),
      );

  Widget _solidCta({
    required String label,
    required Color bg,
    required Color fg,
    VoidCallback? onTap,
    double padding = 15,
  }) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: padding),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  Widget _textBtn(String label, VoidCallback? onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ),
      ),
    );
  }

  Widget _brandCta(String label, VoidCallback? onTap) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: ZveltTokens.glowBrand,
      ),
      child: Material(
        color: ZveltTokens.brand,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
