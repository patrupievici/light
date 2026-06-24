// Zvelt — Onboarding 2 · ACT 5 (Launch). Screens 24–28.
//
// FLESHED. Faithful 1:1 port of `_onb/onboarding-screens-3.jsx` (ScrConnect …
// ScrEnter) onto ZveltTokens / ZType.
//
//   - ScrConnect  → FUNCTIONAL. The primary CTA runs the REAL
//                   HealthService.instance.requestPermissions() +
//                   backfillRecentOnFirstGrant() and advances on grant OR deny;
//                   the ghost CTA skips. Renders the device-list card from JSX.
//   - ScrCommit   → reads the collected goal + diet for the commitment card.
//   - ScrSummary  → recap of everything collected (name, goal, level, diet).
//   - ScrMotivation → full-screen hero, NO back by design.
//   - ScrEnter    → final welcome, NO back. Its CTA calls args.next(), which the
//                   router routes into _finish() (await in-flight sync → fallback
//                   → flip completion flag → onComplete). [busy] = true while
//                   finishing, so the CTA shows its spinner.
//
// part of onboarding2.dart — shares its imports (ZveltTokens, HealthService,
// reportError, the kit widgets + label maps). No imports may be added here.
// All visual primitives below are `_Launch*`-prefixed and fully self-contained
// so this part never collides with (or depends on) the private helpers other
// agents define in the sibling part files.

part of 'onboarding2.dart';

// ═════════════════════════════════════════════════════════════════════════════
// LOCAL KIT — launch-act-only primitives. `_Launch*`-prefixed to stay collision-
// free with the other parts. Built straight on ZveltTokens / the foundation kit.
// ═════════════════════════════════════════════════════════════════════════════

/// Circular brand-gradient initials avatar. JSX `Avatar` (accent variant) with
/// an optional surface [ring] halo + brand glow.
class _LaunchAvatar extends StatelessWidget {
  const _LaunchAvatar({
    required this.initials,
    this.size = 56,
    this.ring = false,
  });

  final String initials;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: ZveltTokens.gradBrand,
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontFamily: ZveltTokens.fontPrimary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
          height: 1,
          color: Colors.white,
        ),
      ),
    );
    if (!ring) return bubble;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ZveltTokens.surface,
        boxShadow: [
          BoxShadow(
            color: ZveltTokens.brand.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: bubble,
    );
  }
}

/// Pill chip. JSX `.z-chip` (+ `.brand` modifier when [brand]).
class _LaunchChip extends StatelessWidget {
  const _LaunchChip(this.label, {this.brand = false});
  final String label;
  final bool brand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: brand ? ZveltTokens.brandTint : ZveltTokens.surface3,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: ZveltTokens.fontPrimary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: brand ? ZveltTokens.brandDeep : ZveltTokens.text2,
        ),
      ),
    );
  }
}

/// Soft-shadow white card. JSX `.z-card` (V2 uses shadow, no border).
class _LaunchCard extends StatelessWidget {
  const _LaunchCard({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(ZveltTokens.s4),
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: child,
    );
  }
}

/// One row in the ScrConnect device list: status dot + label/sub + status chip.
/// JSX `devices.map`.
class _LaunchDeviceRow extends StatelessWidget {
  const _LaunchDeviceRow({
    required this.dot,
    required this.label,
    required this.sub,
    required this.chip,
    required this.connected,
    this.showDivider = true,
  });

  final Color dot;
  final String label;
  final String sub;
  final String chip;
  final bool connected;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label, $sub, $chip',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: ZveltTokens.border))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
            ),
            const SizedBox(width: ZveltTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ZveltTokens.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontPrimary,
                      fontSize: 11,
                      color: ZveltTokens.text3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: ZveltTokens.s3),
            _LaunchChip(chip, brand: connected),
          ],
        ),
      ),
    );
  }
}

/// One row in the ScrSummary plan recap: tinted icon tile → label/sub → check.
/// JSX summary `rows.map`.
class _LaunchSummaryRow extends StatelessWidget {
  const _LaunchSummaryRow({
    required this.icon,
    required this.color,
    required this.bg,
    required this.label,
    required this.sub,
    this.showDivider = true,
  });

  final IconData icon;
  final Color color;
  final Color bg;
  final String label;
  final String sub;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label, $sub, ready',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: ZveltTokens.border))
              : null,
        ),
        child: Row(
          children: [
            OnbTileIcon(icon: icon, color: color, bg: bg, size: 42, iconSize: 21),
            const SizedBox(width: ZveltTokens.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: ZveltTokens.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontPrimary,
                      fontSize: 12,
                      color: ZveltTokens.text3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: ZveltTokens.s3),
            const Icon(AppIcons.check,
                size: 18, color: ZveltTokens.success),
          ],
        ),
      ),
    );
  }
}

/// First non-space character of [name] upper-cased, else 'Z'. JSX initials.
String _launchInitial(String name) {
  final t = name.trim();
  if (t.isEmpty) return 'Z';
  return t[0].toUpperCase();
}

// ─────────────────────────────────────────────────────────────────────────────
// 24 · ScrConnect — connect your data. Requests REAL Health permissions.
//
// FUNCTIONAL: the primary CTA runs HealthService.instance.requestPermissions()
// and, on first grant, backfillRecentOnFirstGrant() — then advances whether the
// user granted OR denied. The ghost CTA skips the request entirely. Mirrors the
// JSX device-list card (Apple Health / Whoop / Garmin).
// ─────────────────────────────────────────────────────────────────────────────
class ScrConnect extends StatefulWidget {
  const ScrConnect({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  State<ScrConnect> createState() => _ScrConnectState();
}

class _ScrConnectState extends State<ScrConnect> {
  bool _busy = false;
  bool _loading = true;
  HealthRouteRecommendation? _route;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  /// Detect the RIGHT health hub for THIS device (Apple Health on iOS, Health
  /// Connect on Android — incl. install/update state) + the real grant state.
  /// We never copy the mock's static Apple Health/Whoop/Garmin list; we request
  /// exactly what the user's phone supports.
  Future<void> _resolve() async {
    HealthRouteRecommendation? route;
    var connected = false;
    try {
      route = await HealthCapabilityService().resolvePrimaryRoute();
      connected = await HealthService.instance.hasPermissions();
    } catch (e, st) {
      reportError(e, st, reason: 'onb2:connect-resolve');
    }
    if (!mounted) return;
    setState(() {
      _route = route;
      _connected = connected;
      _loading = false;
    });
  }

  bool get _needsInstall =>
      _route?.kind == HealthRouteKind.healthConnectInstall ||
      _route?.kind == HealthRouteKind.healthConnectUpdate;

  /// (hub name, one-line sub) for the resolved device route.
  (String, String) get _hub {
    switch (_route?.kind) {
      case HealthRouteKind.appleHealth:
        return ('Apple Health', 'Steps, sleep, heart rate & workouts');
      case HealthRouteKind.healthConnectReady:
      case HealthRouteKind.healthConnectInstall:
      case HealthRouteKind.healthConnectUpdate:
        return ('Health Connect', 'Steps, sleep, heart rate & workouts');
      case HealthRouteKind.cloudAggregatorRecommended:
        return ('Wearable cloud', 'Link your wearable account');
      default:
        return ('Health data', 'Steps, sleep, heart rate & workouts');
    }
  }

  String get _primaryLabel {
    if (_connected) return 'Continue';
    if (_route?.kind == HealthRouteKind.healthConnectUpdate) {
      return 'Update Health Connect';
    }
    if (_route?.kind == HealthRouteKind.healthConnectInstall) {
      return 'Install Health Connect';
    }
    return 'Connect ${_hub.$1}';
  }

  Future<void> _primary() async {
    if (_busy) return;
    if (_connected) {
      widget.args.next();
      return;
    }
    setState(() => _busy = true);
    try {
      if (_needsInstall) {
        // Send to the store / update flow, then re-probe — DON'T advance, so
        // the user can grant right after installing.
        await HealthService.instance.openHealthConnectInStore();
        await _resolve();
        if (mounted) setState(() => _busy = false);
        return;
      }
      final granted = await HealthService.instance.requestPermissions();
      if (granted) {
        try {
          await HealthService.instance.backfillRecentOnFirstGrant();
        } catch (e, st) {
          // Backfill is best-effort — must not block onboarding.
          reportError(e, st, reason: 'onb2:connect-backfill');
        }
      }
      if (mounted) _connected = granted;
    } catch (e, st) {
      reportError(e, st, reason: 'onb2:connect-permissions');
    } finally {
      // Advance on grant OR deny — connecting is always skippable.
      if (mounted) {
        setState(() => _busy = false);
        widget.args.next();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (hubName, hubSub) = _hub;
    return OnbShell(
      onBack: widget.args.back,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OnbPrimaryButton(
            label: _primaryLabel,
            busy: _busy,
            onTap: _loading ? null : _primary,
          ),
          const SizedBox(height: ZveltTokens.s2),
          OnbGhostButton(label: 'Skip for now', onTap: widget.args.next),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'Integrations',
            title: 'Connect your data.',
            sub: 'The more Zvelt sees, the smarter your AI coach gets.',
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: ZveltTokens.s8),
              child: Center(
                child: CircularProgressIndicator(
                    color: ZveltTokens.brand, strokeWidth: 2),
              ),
            )
          else ...[
            // The ONE health hub this phone actually supports — real state.
            _LaunchCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: ZveltTokens.s4, vertical: ZveltTokens.s1),
              child: _LaunchDeviceRow(
                dot: _connected ? ZveltTokens.success : ZveltTokens.text4,
                label: hubName,
                sub: hubSub,
                chip: _connected
                    ? 'Connected'
                    : (_needsInstall ? 'Install' : 'Connect'),
                connected: _connected,
                showDivider: false,
              ),
            ),
            const SizedBox(height: ZveltTokens.s3),
            // The wearable point: wearables flow through the hub for free.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(AppIcons.clock,
                      size: 18, color: ZveltTokens.text3),
                  const SizedBox(width: ZveltTokens.s2),
                  Expanded(
                    child: Text(
                      'Got a wearable? Garmin, Whoop, Samsung Watch, Coros & '
                      'Apple Watch sync automatically once $hubName is connected.',
                      style: ZType.bodyS.copyWith(color: ZveltTokens.text2),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 25 · ScrCommit — make it a promise. Reads the collected goal + diet.
// ─────────────────────────────────────────────────────────────────────────────
class ScrCommit extends StatelessWidget {
  const ScrCommit({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  Widget build(BuildContext context) {
    final goalLabel = kGoalLabel[args.data.goal] ?? 'Build muscle';
    final dietLabel = kDietLabel[args.data.diet] ?? 'Balanced';
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(
        label: 'I commit',
        showArrow: false,
        onTap: args.next,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'Your commitment',
            title: 'Make it a promise.',
            sub: 'Commitment beats motivation. Lock in your first target.',
          ),
          _LaunchCard(
            padding: const EdgeInsets.all(ZveltTokens.s5),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ZveltTokens.brandTint,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(AppIcons.location_alt,
                      size: 30, color: ZveltTokens.brand),
                ),
                const SizedBox(height: ZveltTokens.s4),
                const OnbEyebrow('My 12-week goal'),
                const SizedBox(height: ZveltTokens.s2),
                Text(
                  goalLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 26,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: ZveltTokens.text,
                  ),
                ),
                const SizedBox(height: ZveltTokens.s4),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: ZveltTokens.s2,
                  runSpacing: ZveltTokens.s2,
                  children: [
                    const _LaunchChip('4 sessions / week', brand: true),
                    _LaunchChip(dietLabel),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 26 · ScrSummary — personalized plan recap of everything collected.
// ─────────────────────────────────────────────────────────────────────────────
class ScrSummary extends StatelessWidget {
  const ScrSummary({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  Widget build(BuildContext context) {
    final data = args.data;
    final name = data.name.trim().isEmpty ? 'Athlete' : data.name.trim();
    final goalLabel = kGoalLabel[data.goal] ?? 'Build muscle';
    final levelLabel = kLevelLabel[data.level] ?? 'Intermediate';
    final dietLabel = kDietLabel[data.diet] ?? 'Balanced';
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'Looks great', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile header card.
          _LaunchCard(
            padding: const EdgeInsets.all(ZveltTokens.s5),
            child: Row(
              children: [
                _LaunchAvatar(
                  initials: _launchInitial(data.name),
                  size: 56,
                  ring: true,
                ),
                const SizedBox(width: ZveltTokens.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const OnbEyebrow('Plan ready for'),
                      const SizedBox(height: ZveltTokens.s1),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: ZveltTokens.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Goal · $goalLabel',
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontSize: 12,
                          color: ZveltTokens.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZveltTokens.cardGap),
          // Pillar recap list.
          _LaunchCard(
            padding: const EdgeInsets.symmetric(
                horizontal: ZveltTokens.s4, vertical: ZveltTokens.s1),
            child: Column(
              children: [
                _LaunchSummaryRow(
                  icon: AppIcons.gym,
                  color: ZveltTokens.brand,
                  bg: ZveltTokens.brandTint,
                  label: 'Training',
                  sub: '$levelLabel · 4×/week',
                ),
                _LaunchSummaryRow(
                  icon: AppIcons.restaurant,
                  color: ZveltTokens.strength,
                  bg: ZveltTokens.strength2,
                  label: 'Nutrition',
                  sub: '$dietLabel · 2,400 kcal',
                ),
                const _LaunchSummaryRow(
                  icon: AppIcons.sparkles,
                  color: ZveltTokens.recovery,
                  bg: ZveltTokens.recovery2,
                  label: 'AI Coach',
                  sub: 'Briefed · guiding you daily',
                ),
                const _LaunchSummaryRow(
                  icon: AppIcons.globe,
                  color: ZveltTokens.sleep,
                  bg: ZveltTokens.sleep2,
                  label: 'Community',
                  sub: 'Matched to 3 active groups',
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 27 · ScrMotivation — full-screen hero. No back, by design.
// ─────────────────────────────────────────────────────────────────────────────
class ScrMotivation extends StatelessWidget {
  const ScrMotivation({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      scroll: false,
      footer: OnbPrimaryButton(label: "Let's go", onTap: args.next),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Soft brand halo behind the hero text.
            Container(
              width: 360,
              height: 360,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [ZveltTokens.brandGlow, Color(0x00FF7A2F)],
                  stops: [0.0, 0.65],
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const OnbEyebrow('No more someday',
                    color: ZveltTokens.brandDeep),
                const SizedBox(height: ZveltTokens.s4),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontPrimary,
                      fontSize: 52,
                      height: 1.02,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.56,
                      color: ZveltTokens.text,
                    ),
                    children: const [
                      TextSpan(text: 'Day 1\nstarts '),
                      TextSpan(
                        text: 'now.',
                        style: TextStyle(color: ZveltTokens.brand),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ZveltTokens.s5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    "Everything's set. The only thing left is to show up — and you already have.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontPrimary,
                      fontSize: 15,
                      height: 1.55,
                      color: ZveltTokens.text2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 28 · ScrEnter — final welcome. No back. CTA → _finish() in the router.
// ─────────────────────────────────────────────────────────────────────────────
class ScrEnter extends StatelessWidget {
  const ScrEnter({super.key, required this.args, this.busy = false});
  final OnbScreenArgs args;

  /// True while the router awaits the in-flight sync + finishes. Shows the
  /// CTA spinner so the user knows completion is in progress.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final name = args.data.name.trim();
    final greeting = name.isEmpty ? 'athlete' : name;
    return OnbShell(
      scroll: false,
      footer: OnbPrimaryButton(
        label: 'Enter Zvelt',
        busy: busy,
        onTap: args.next,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LaunchAvatar(
              initials: _launchInitial(name),
              size: 96,
              ring: true,
            ),
            const SizedBox(height: ZveltTokens.s6),
            Text(
              'Welcome, $greeting.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 30,
                height: 1.12,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.66,
                color: ZveltTokens.text,
              ),
            ),
            const SizedBox(height: ZveltTokens.s3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                "Your crew, your plan and your coach are ready. Let's build something.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 14.5,
                  height: 1.55,
                  color: ZveltTokens.text2,
                ),
              ),
            ),
            const SizedBox(height: ZveltTokens.s5),
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: ZveltTokens.s2,
              runSpacing: ZveltTokens.s2,
              children: [
                _LaunchChip('Tier I · First Step', brand: true),
                _LaunchChip('12-week plan'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
