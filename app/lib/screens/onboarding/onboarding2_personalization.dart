// Zvelt — Onboarding 2 · ACT 2 (Personalization). Screens 5–10.
//
// These screens carry the OnbProgress bar (n/6). They collect every answer the
// backend needs (name, username, goal[+goalText], level, sex, age, height,
// weight, diet) into the shared [OnbData]. ScrGoal fires the plan prewarm via
// [onPrewarm] on the way out; ScrBuilding kicks the real backend sync via
// [onStartSync] and runs the animated "building your plan" reveal.
//
// Faithful 1:1 port of `_onb/onboarding-screens-1.jsx` (ScrProfile · ScrGoal ·
// ScrLevel · ScrBiology · ScrNutritionStyle · ScrBuilding) onto
// ZveltTokens / ZType + the kit widgets in onboarding2.dart.

part of 'onboarding2.dart';

/// Personalization act runs 6 progress steps (screens 5–10 → 1/6 … 6/6).
const int _kPersonalizationTotal = 6;

// ═════════════════════════════════════════════════════════════════════════════
// OPTION TABLES — mirror the JSX const GOALS / LEVELS / DIETS arrays 1:1.
// ═════════════════════════════════════════════════════════════════════════════

/// A single-select option row spec (id + icon + copy + optional accent colors).
class _OnbOption {
  const _OnbOption({
    required this.id,
    required this.icon,
    required this.title,
    required this.sub,
    this.color = ZveltTokens.brand,
    this.bg,
  });

  final String id;
  final IconData icon;
  final String title;
  final String sub;
  final Color color;
  final Color? bg;
}

/// Screen 6 · GOALS (JSX const GOALS).
const List<_OnbOption> _kGoals = [
  _OnbOption(
    id: 'muscle',
    icon: AppIcons.gym,
    title: 'Build muscle',
    sub: 'Add lean size & strength',
  ),
  _OnbOption(
    id: 'fat',
    icon: AppIcons.flame,
    title: 'Lose fat',
    sub: 'Lean out, keep strength',
  ),
  _OnbOption(
    id: 'strong',
    // Distinct from 'muscle' (dumbbell): trophy reads as strength/achievement.
    // The old balance-scale glyph meant "weigh", not "stronger".
    icon: AppIcons.trophy,
    title: 'Get stronger',
    sub: 'Move heavier, smarter',
  ),
  _OnbOption(
    id: 'health',
    icon: AppIcons.heart,
    title: 'Improve health',
    sub: 'Energy, sleep, longevity',
  ),
];

/// Screen 7 · LEVELS (JSX const LEVELS).
const List<_OnbOption> _kLevels = [
  _OnbOption(
    id: 'beg',
    icon: AppIcons.sparkles,
    title: 'Beginner',
    sub: 'New or returning',
  ),
  _OnbOption(
    id: 'int',
    icon: AppIcons.arrow_trend_up,
    title: 'Intermediate',
    sub: '6+ months consistent',
  ),
  _OnbOption(
    id: 'adv',
    icon: AppIcons.bolt,
    title: 'Advanced',
    sub: 'Years under the bar',
  ),
];

/// Screen 9 · DIETS (JSX const DIETS — each with its own category accent).
final List<_OnbOption> _kDiets = [
  const _OnbOption(
    id: 'balanced',
    icon: AppIcons.salad,
    title: 'Balanced',
    sub: 'A bit of everything',
  ),
  _OnbOption(
    id: 'protein',
    icon: AppIcons.flame,
    title: 'High protein',
    sub: 'Muscle-first macros',
    color: ZveltTokens.brand,
    bg: ZveltTokens.brandTint,
  ),
  const _OnbOption(
    id: 'plant',
    icon: AppIcons.leaf,
    title: 'Plant-based',
    sub: 'Veg-forward fuel',
    color: ZveltTokens.strength,
    bg: ZveltTokens.strength2,
  ),
  const _OnbOption(
    id: 'lowcarb',
    icon: AppIcons.target,
    title: 'Low carb',
    sub: 'Lean & steady energy',
    color: ZveltTokens.sleep,
    bg: ZveltTokens.sleep2,
  ),
];

/// Sex segmented options. Label → OnbData code ('f' | 'm' | 'x') so
/// [OnbData.toPayload] → [OnboardingService] `_sexFromCode` maps correctly.
const List<(String, String)> _kSexes = [
  ('Female', 'f'),
  ('Male', 'm'),
  ('Other', 'x'),
];

// ─────────────────────────────────────────────────────────────────────────────
// 05 · ScrProfile (step 1/6) — avatar + name (required) + username.
// ─────────────────────────────────────────────────────────────────────────────
class ScrProfile extends StatelessWidget {
  const ScrProfile({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  Widget build(BuildContext context) {
    final name = args.data.name.trim();
    final ready = name.isNotEmpty;
    final initial = name.isEmpty ? 'Z' : name[0].toUpperCase();

    return OnbShell(
      // Authed users entered here directly — no auth act to reverse into.
      onBack: args.authed ? null : args.back,
      progress: (1, _kPersonalizationTotal),
      footer: OnbPrimaryButton(
        label: 'Continue',
        onTap: ready ? args.next : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'Step 1 · Profile',
            title: "Let's make it yours.",
          ),
          // Avatar with brand ring + camera affordance (decorative).
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: ZveltTokens.s6),
              child: _ProfileAvatar(initial: initial),
            ),
          ),
          OnbField(
            label: 'Your name',
            value: args.data.name,
            placeholder: 'e.g. Similea',
            onChanged: (v) => args.setData(() => args.data.name = v),
          ),
          const SizedBox(height: ZveltTokens.s3),
          OnbField(
            label: 'Username',
            value: args.data.username,
            placeholder: '@yourhandle',
            onChanged: (v) => args.setData(() => args.data.username = v),
          ),
        ],
      ),
    );
  }
}

/// 92px brand-ring avatar with the user's initial + a camera badge.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.initial});
  final String initial;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Profile photo',
      excludeSemantics: true,
      child: SizedBox(
        width: 100,
        height: 100,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: ZveltTokens.gradBrand,
                boxShadow: [
                  BoxShadow(
                    color: ZveltTokens.brand.withValues(alpha: 0.28),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZveltTokens.surface,
                  border: Border.all(color: ZveltTokens.border),
                  boxShadow: ZveltTokens.shadowCard,
                ),
                child: Icon(
                  AppIcons.camera,
                  size: 16,
                  color: ZveltTokens.text2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 06 · ScrGoal (step 2/6) — single-select goal + optional free text.
//      Fires the plan prewarm on next (gated on a selection).
// ─────────────────────────────────────────────────────────────────────────────
class ScrGoal extends StatelessWidget {
  const ScrGoal({super.key, required this.args, required this.onPrewarm});
  final OnbScreenArgs args;

  /// Called right before advancing so the AI plan starts generating early.
  final VoidCallback onPrewarm;

  @override
  Widget build(BuildContext context) {
    final selected = args.data.goal;
    return OnbShell(
      onBack: args.back,
      progress: (2, _kPersonalizationTotal),
      footer: OnbPrimaryButton(
        label: 'Continue',
        onTap: selected == null
            ? null
            : () {
                onPrewarm();
                args.next();
              },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'Step 2 · Goal',
            title: "What's the mission?",
          ),
          for (final g in _kGoals) ...[
            SelectCard(
              icon: g.icon,
              title: g.title,
              sub: g.sub,
              color: g.color,
              bg: g.bg,
              selected: selected == g.id,
              onTap: () => args.setData(() => args.data.goal = g.id),
            ),
            if (g.id != _kGoals.last.id) const SizedBox(height: ZveltTokens.s3),
          ],
          // Optional free-text vision — feeds the deterministic plan engine.
          const SizedBox(height: ZveltTokens.s4),
          OnbField(
            label: 'In your words (optional)',
            value: args.data.goalText,
            placeholder: 'e.g. Bench 100kg by summer',
            onChanged: (v) => args.setData(() => args.data.goalText = v),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 07 · ScrLevel (step 3/6) — single-select experience (beg / int / adv).
// ─────────────────────────────────────────────────────────────────────────────
class ScrLevel extends StatelessWidget {
  const ScrLevel({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  Widget build(BuildContext context) {
    final selected = args.data.level;
    return OnbShell(
      onBack: args.back,
      progress: (3, _kPersonalizationTotal),
      footer: OnbPrimaryButton(
        label: 'Continue',
        onTap: selected == null ? null : args.next,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'Step 3 · Experience',
            title: 'Where are you now?',
          ),
          for (final l in _kLevels) ...[
            SelectCard(
              icon: l.icon,
              title: l.title,
              sub: l.sub,
              color: l.color,
              bg: l.bg,
              selected: selected == l.id,
              onTap: () => args.setData(() => args.data.level = l.id),
            ),
            if (l.id != _kLevels.last.id) const SizedBox(height: ZveltTokens.s3),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 08 · ScrBiology (step 4/6) — sex segmented + age / height / weight inputs.
// ─────────────────────────────────────────────────────────────────────────────
class ScrBiology extends StatelessWidget {
  const ScrBiology({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      progress: (4, _kPersonalizationTotal),
      footer: OnbPrimaryButton(label: 'Continue', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'Step 4 · About you',
            title: 'The basics on you.',
            sub: 'So your AI coach can calibrate your plan, calories '
                'and recovery.',
          ),
          // Sex segmented control.
          Row(
            children: [
              for (var i = 0; i < _kSexes.length; i++) ...[
                Expanded(
                  child: _SexChip(
                    label: _kSexes[i].$1,
                    selected: args.data.sex == _kSexes[i].$2,
                    onTap: () =>
                        args.setData(() => args.data.sex = _kSexes[i].$2),
                  ),
                ),
                if (i != _kSexes.length - 1)
                  const SizedBox(width: ZveltTokens.s2),
              ],
            ],
          ),
          const SizedBox(height: ZveltTokens.s4),
          OnbField(
            label: 'Age',
            value: args.data.age,
            placeholder: '28',
            suffix: 'years',
            numeric: true,
            onChanged: (v) =>
                args.setData(() => args.data.age = _digits(v)),
          ),
          const SizedBox(height: ZveltTokens.s3),
          OnbField(
            label: 'Height',
            value: args.data.height,
            placeholder: '178',
            suffix: 'cm',
            numeric: true,
            onChanged: (v) =>
                args.setData(() => args.data.height = _digits(v)),
          ),
          const SizedBox(height: ZveltTokens.s3),
          OnbField(
            label: 'Weight',
            value: args.data.weight,
            placeholder: '74',
            suffix: 'kg',
            numeric: true,
            onChanged: (v) =>
                args.setData(() => args.data.weight = _digits(v)),
          ),
        ],
      ),
    );
  }

  /// Mirror the JSX `v.replace(/\D/g, '')` — keep digits only (whole numbers).
  static String _digits(String v) => v.replaceAll(RegExp(r'\D'), '');
}

/// One pill of the sex segmented control. Selected = brand tint + 2px border.
class _SexChip extends StatelessWidget {
  const _SexChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? ZveltTokens.brandTint : ZveltTokens.surface,
            borderRadius: BorderRadius.circular(ZveltTokens.rMd),
            border: Border.all(
              color: selected ? ZveltTokens.brand : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? ZveltTokens.brandDeep : ZveltTokens.text2,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 09 · ScrNutritionStyle (step 5/6) — single-select diet style.
// ─────────────────────────────────────────────────────────────────────────────
class ScrNutritionStyle extends StatelessWidget {
  const ScrNutritionStyle({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  Widget build(BuildContext context) {
    final selected = args.data.diet;
    return OnbShell(
      onBack: args.back,
      progress: (5, _kPersonalizationTotal),
      footer: OnbPrimaryButton(
        label: 'Continue',
        onTap: selected == null ? null : args.next,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'Step 5 · Nutrition',
            title: 'How do you eat?',
          ),
          for (final d in _kDiets) ...[
            SelectCard(
              icon: d.icon,
              title: d.title,
              sub: d.sub,
              color: d.color,
              bg: d.bg,
              selected: selected == d.id,
              onTap: () => args.setData(() => args.data.diet = d.id),
            ),
            if (d.id != _kDiets.last.id) const SizedBox(height: ZveltTokens.s3),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 10 · ScrBuilding (step 6/6) — AI plan-building animation. Kicks the sync.
//
// The real side effect fires on mount:
//   - [onStartSync]  → starts the full backend completeOnboarding future,
//                      stored on OnbData so ScrEnter can await it (~8s grace).
//                      The router also reaffirms the plan prewarm there.
// The animated checklist is purely cosmetic; the CTA unlocks when the visual
// reaches the end of its sequence.
// ─────────────────────────────────────────────────────────────────────────────
class ScrBuilding extends StatefulWidget {
  const ScrBuilding({
    super.key,
    required this.args,
    required this.onStartSync,
  });
  final OnbScreenArgs args;

  /// Kicks the real backend sync; the router stores the future on OnbData so
  /// ScrEnter can await it. Idempotent.
  final VoidCallback onStartSync;

  @override
  State<ScrBuilding> createState() => _ScrBuildingState();
}

class _ScrBuildingState extends State<ScrBuilding>
    with SingleTickerProviderStateMixin {
  static const List<String> _steps = [
    'Analyzing your goal',
    'Calibrating training load',
    'Designing your nutrition',
    'Briefing your AI coach',
    'Matching your community',
  ];

  late final AnimationController _spin;
  Timer? _tick;
  int _done = 0;

  bool get _complete => _done >= _steps.length;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    // Fire the real work as soon as this screen mounts: kick the full backend
    // sync that ScrEnter awaits (the plan prewarm already fired at ScrGoal).
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onStartSync());

    // Drive the cosmetic checklist (JSX 620ms cadence).
    _advance();
  }

  void _advance() {
    if (_done >= _steps.length) return;
    _tick = Timer(const Duration(milliseconds: 620), () {
      if (!mounted) return;
      setState(() => _done++);
      _advance();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      progress: (6, _kPersonalizationTotal),
      footer: OnbPrimaryButton(
        label: _complete ? 'View my plan' : 'Building…',
        onTap: _complete ? widget.args.next : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Spinning halo + sparkle hero.
          Padding(
            padding: const EdgeInsets.only(
              top: ZveltTokens.s3,
              bottom: ZveltTokens.s8,
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              ZveltTokens.brandGlow,
                              ZveltTokens.brandGlow.withValues(alpha: 0),
                            ],
                            stops: const [0.0, 0.7],
                          ),
                        ),
                      ),
                      RotationTransition(
                        turns: _spin,
                        child: const CustomPaint(
                          size: Size(96, 96),
                          painter: _ArcPainter(),
                        ),
                      ),
                      const Icon(
                        AppIcons.sparkles,
                        size: 34,
                        color: ZveltTokens.brand,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZveltTokens.s5),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _complete ? 'Your plan is ready' : 'Building your plan',
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: ZveltTokens.text,
                    ),
                  ),
                ),
                const SizedBox(height: ZveltTokens.s2),
                Text(
                  'Tailored to everything you told us',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 13,
                    color: ZveltTokens.text3,
                  ),
                ),
              ],
            ),
          ),
          // Checklist card.
          Container(
            decoration: BoxDecoration(
              color: ZveltTokens.surface,
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              boxShadow: ZveltTokens.shadowCard,
            ),
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4),
            child: Column(
              children: [
                for (var i = 0; i < _steps.length; i++)
                  _BuildStepRow(
                    label: _steps[i],
                    done: i < _done,
                    active: i == _done && !_complete,
                    showDivider: i < _steps.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the build checklist: status dot + label + active pulse.
class _BuildStepRow extends StatelessWidget {
  const _BuildStepRow({
    required this.label,
    required this.done,
    required this.active,
    required this.showDivider,
  });
  final String label;
  final bool done;
  final bool active;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: (done || active) ? 1 : 0.4,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(
                  bottom: BorderSide(color: ZveltTokens.border),
                )
              : null,
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? ZveltTokens.brand : ZveltTokens.surface3,
              ),
              child: done
                  ? const Icon(AppIcons.check,
                      size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: ZveltTokens.s3),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: ZveltTokens.text,
                ),
              ),
            ),
            if (active)
              const Text(
                '···',
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ZveltTokens.brand,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The brand progress arc on the spinning building ring (JSX strokeDasharray
/// "70 210" over r=44 / strokeWidth 3, with a muted full track behind it).
class _ArcPainter extends CustomPainter {
  const _ArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 44.0;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = ZveltTokens.surface3;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = ZveltTokens.brand;
    // 70 / (2π·44 ≈ 276.5) of the circumference → ~0.253 turns.
    const sweep = 70 / 276.46 * 2 * 3.1415926535;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.1415926535 / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) => false;
}
