// Zvelt — Onboarding 2 · ACT 4 (Community). Screens 19–23.
//
// Faithful 1:1 Flutter port of `_onb/onboarding-screens-3.jsx`
// (ScrMosaic / ScrTestimonials / ScrChallenge / ScrBadge / ScrNotifications).
// Built on ZveltTokens / ZType + the shared kit from onboarding2.dart — no
// hardcoded hex. Act-scoped presentation helpers (_CmAvatar, _CmChip, _CmCard,
// _CmHalo) mirror the JSX Avatar / z-chip / z-card / z-pulse primitives.
//
// FUNCTIONAL: ScrNotifications fires a REAL FirebaseMessaging permission
// request on "Enable notifications". Both Enable and Not-now advance — denial
// is the OS's affair, the flow never blocks on it. See the contract notes in
// onboarding2_intro.dart / onboarding2.dart.

part of 'onboarding2.dart';

// ═════════════════════════════════════════════════════════════════════════════
// LOCAL PRESENTATION HELPERS — mirror the JSX Avatar / chip / card primitives.
// Names are act-scoped (`_Cm…`) so they never collide with the private helpers
// defined in the other onboarding2 part-files (all share one library).
// ═════════════════════════════════════════════════════════════════════════════

/// Circular initials avatar. `accent` → brand gradient fill; otherwise a neutral
/// surface bubble with a hairline border. Optional `online` green dot. JSX
/// `Avatar`.
class _CmAvatar extends StatelessWidget {
  const _CmAvatar({
    required this.initials,
    required this.size,
    this.accent = false,
    this.online = false,
  });

  final String initials;
  final double size;
  final bool accent;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final Widget bubble = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: accent ? ZveltTokens.gradBrand : null,
        color: accent ? null : ZveltTokens.surface2,
        border: accent ? null : Border.all(color: ZveltTokens.borderStrong),
        boxShadow: accent ? ZveltTokens.shadowCard : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          fontFamily: ZveltTokens.fontPrimary,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: accent ? Colors.white : ZveltTokens.text2,
        ),
      ),
    );

    if (!online) return bubble;
    final dot = (size * 0.27).clamp(8.0, 16.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        bubble,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ZveltTokens.success,
              border: Border.all(color: ZveltTokens.bg, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small pill label. `tone` picks the fill/ink pair. JSX `.z-chip` / `.z-chip
/// brand` / the translucent-white chip used on colored heroes.
class _CmChip extends StatelessWidget {
  const _CmChip(this.text, {this.tone = _CmChipTone.neutral});
  final String text;
  final _CmChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      _CmChipTone.brand => (ZveltTokens.brandTint, ZveltTokens.brandDeep),
      _CmChipTone.onColor =>
        (Colors.white.withValues(alpha: 0.20), Colors.white),
      _CmChipTone.neutral => (ZveltTokens.surface3, ZveltTokens.text2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: ZveltTokens.fontPrimary,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

enum _CmChipTone { neutral, brand, onColor }

/// Soft-shadow white card — JSX `.z-card`. No border (V2 uses shadow only).
class _CmCard extends StatelessWidget {
  const _CmCard({required this.child, this.padding});
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

/// Pulsing radial halo behind hero badges. JSX `.z-pulse` glow.
class _CmHalo extends StatefulWidget {
  const _CmHalo({required this.diameter, required this.color});
  final double diameter;
  final Color color;

  @override
  State<_CmHalo> createState() => _CmHaloState();
}

class _CmHaloState extends State<_CmHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.55, end: 1.0).animate(
          CurvedAnimation(parent: _c, curve: Curves.easeInOut),
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.06).animate(
            CurvedAnimation(parent: _c, curve: Curves.easeInOut),
          ),
          child: Container(
            width: widget.diameter,
            height: widget.diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [widget.color, widget.color.withValues(alpha: 0)],
                stops: const [0.0, 0.65],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 19 · ScrMosaic — real humans, real grind. 4×3 avatar grid + stat strip.
// ─────────────────────────────────────────────────────────────────────────────
class ScrMosaic extends StatelessWidget {
  const ScrMosaic({super.key, required this.args});
  final OnbScreenArgs args;

  // (initials, accent) — matches the JSX `people` array exactly.
  static const List<(String, bool)> _people = [
    ('L', true), ('A', false), ('Y', true), ('M', false),
    ('R', true), ('K', false), ('T', true), ('N', false),
    ('S', true), ('B', false), ('J', true), ('E', false),
  ];

  static const List<(String, String)> _stats = [
    ('248k', 'Members'),
    ('63', 'Countries'),
    ('4.7', 'Sessions/wk'),
  ];

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'Meet them', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'The people',
            title: 'Real humans. Real grind.',
            sub: 'Lifters, runners and first-timers — all evolving together '
                'on Zvelt.',
          ),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            children: [
              for (final (i, p) in _people.indexed)
                Center(
                  child: _CmAvatar(
                    initials: p.$1,
                    size: 58,
                    accent: p.$2,
                    online: i % 3 == 0,
                  ),
                ),
            ],
          ),
          const SizedBox(height: ZveltTokens.s5),
          _CmCard(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                for (final s in _stats)
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          s.$1,
                          style: ZType.stat.copyWith(fontSize: 22),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          s.$2.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: ZveltTokens.fontMono,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.0,
                            color: ZveltTokens.text3,
                          ),
                        ),
                      ],
                    ),
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
// 20 · ScrTestimonials — results that speak. Three quote cards.
// ─────────────────────────────────────────────────────────────────────────────
class ScrTestimonials extends StatelessWidget {
  const ScrTestimonials({super.key, required this.args});
  final OnbScreenArgs args;

  // (name, subtitle, quote, accent) — JSX `quotes` array.
  static const List<(String, String, String, bool)> _quotes = [
    (
      'Yusuf K',
      'Lost 9kg · 6 months',
      'My AI coach told me when to push and when to rest. Game changer.',
      true,
    ),
    (
      'Anna B',
      'First marathon',
      'My group kept me accountable when motivation dropped. I finished.',
      false,
    ),
    (
      'Marco D',
      '+14kg squat',
      'Nutrition and training in one place finally made it click for me.',
      true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'Next', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'In their words',
            title: 'Results that speak.',
          ),
          for (final (i, q) in _quotes.indexed) ...[
            if (i > 0) const SizedBox(height: ZveltTokens.s3),
            _CmCard(
              padding: const EdgeInsets.all(ZveltTokens.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(AppIcons.quote_right,
                      size: 22, color: ZveltTokens.brand3),
                  const SizedBox(height: ZveltTokens.s2),
                  Text(
                    q.$3,
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontPrimary,
                      fontSize: 14,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: ZveltTokens.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _CmAvatar(
                        initials: q.$1.substring(0, 1),
                        size: 34,
                        accent: q.$4,
                      ),
                      const SizedBox(width: ZveltTokens.s3),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            q.$1,
                            style: TextStyle(
                              fontFamily: ZveltTokens.fontPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: ZveltTokens.text,
                            ),
                          ),
                          Text(
                            q.$2,
                            style: TextStyle(
                              fontFamily: ZveltTokens.fontPrimary,
                              fontSize: 11,
                              color: ZveltTokens.text3,
                            ),
                          ),
                        ],
                      ),
                    ],
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
// 21 · ScrChallenge — start with a win. Gradient hero + "joined" social proof.
// Join / Maybe-later BOTH advance.
// ─────────────────────────────────────────────────────────────────────────────
class ScrChallenge extends StatelessWidget {
  const ScrChallenge({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OnbPrimaryButton(
            label: 'Join the challenge',
            onTap: args.next,
            showArrow: false,
          ),
          const SizedBox(height: ZveltTokens.s2),
          OnbGhostButton(label: 'Maybe later', onTap: args.next),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'Your first challenge',
            title: 'Start with a win.',
          ),
          // Gradient hero card
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ZveltTokens.rLg),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ZveltTokens.brandDeep,
                  ZveltTokens.brand,
                  ZveltTokens.brand2,
                ],
                stops: [0.0, 0.6, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: ZveltTokens.brand.withValues(alpha: 0.32),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(AppIcons.trophy,
                        size: 28, color: Colors.white),
                    _CmChip('7 days left', tone: _CmChipTone.onColor),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  '7-Day Movement Streak',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 26,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: ZveltTokens.s2),
                Text(
                  'Move for 30 minutes a day. Beginner-friendly. '
                  '12,480 people in.',
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 13,
                    height: 1.5,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Social proof row
          _CmCard(
            padding: const EdgeInsets.all(ZveltTokens.s4),
            child: Row(
              children: [
                SizedBox(
                  width: 30 + 20 * 2.0, // 3 overlapping 30px avatars (-10 each)
                  height: 34,
                  child: Stack(
                    children: [
                      for (final (i, n) in const ['L', 'A', 'Y'].indexed)
                        Positioned(
                          left: i * 20.0,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ZveltTokens.surface,
                            ),
                            padding: const EdgeInsets.all(2),
                            child: _CmAvatar(
                              initials: n,
                              size: 30,
                              accent: i % 2 == 0,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: ZveltTokens.s3),
                Expanded(
                  child: Text(
                    'Lucas, Anna & 12k others joined',
                    style: TextStyle(
                      fontFamily: ZveltTokens.fontPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: ZveltTokens.text2,
                    ),
                  ),
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
// 22 · ScrBadge — gamification reveal. Centered hero medallion + halo.
// ─────────────────────────────────────────────────────────────────────────────
class ScrBadge extends StatelessWidget {
  const ScrBadge({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      scroll: false,
      footer: OnbPrimaryButton(label: 'Claim & continue', onTap: args.next),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _CmHalo(
                    diameter: 240,
                    color: ZveltTokens.brand.withValues(alpha: 0.20),
                  ),
                  Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(-0.36, -0.44),
                        radius: 0.9,
                        colors: [
                          ZveltTokens.brand3,
                          ZveltTokens.brand,
                          ZveltTokens.brandDeep,
                        ],
                        stops: [0.0, 0.56, 1.0],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: ZveltTokens.brand.withValues(alpha: 0.5),
                          blurRadius: 44,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: const Icon(AppIcons.trophy,
                        size: 56, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const OnbEyebrow('Badge unlocked', color: ZveltTokens.brandDeep),
            const SizedBox(height: ZveltTokens.s3),
            Text('First Step', style: ZType.displayM.copyWith(fontSize: 30)),
            const SizedBox(height: ZveltTokens.s3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                "You've set up your profile and plan. Tier I of your journey "
                'begins.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: ZveltTokens.fontPrimary,
                  fontSize: 14,
                  height: 1.5,
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
// 23 · ScrNotifications — stay in rhythm. FUNCTIONAL: REAL FCM permission.
//
// "Enable notifications" calls FirebaseMessaging.instance.requestPermission()
// then advances regardless of grant/deny. "Not now" advances without asking.
// kIsWeb-guarded; never throws (errors are reported, then we still advance).
// ─────────────────────────────────────────────────────────────────────────────
class ScrNotifications extends StatefulWidget {
  const ScrNotifications({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  State<ScrNotifications> createState() => _ScrNotificationsState();
}

class _ScrNotificationsState extends State<ScrNotifications> {
  bool _requesting = false;

  // (icon, label, sub) — JSX `rows`.
  static const List<(IconData, String, String)> _rows = [
    (
      AppIcons.flame,
      'Streak reminders',
      "Don't break the chain",
    ),
    (
      AppIcons.globe,
      'Crew activity',
      'When friends train & cheer',
    ),
    (
      AppIcons.sparkles,
      'Coach nudges',
      'Smart, timely guidance',
    ),
  ];

  Future<void> _enable() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      if (!kIsWeb) {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
      }
    } catch (e, st) {
      reportError(e, st, reason: 'onb2:notif-permission');
    } finally {
      // Continue either way — a denial is the OS's UI to surface, not ours.
      if (mounted) {
        setState(() => _requesting = false);
        widget.args.next();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: widget.args.back,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OnbPrimaryButton(
            label: 'Enable notifications',
            onTap: _requesting ? null : _enable,
            busy: _requesting,
            showArrow: false,
          ),
          const SizedBox(height: ZveltTokens.s2),
          OnbGhostButton(label: 'Not now', onTap: widget.args.next),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.only(top: ZveltTokens.s2, bottom: ZveltTokens.s5),
              child: OnbTileIcon(
                icon: AppIcons.bell,
                size: 64,
                iconSize: 30,
              ),
            ),
          ),
          const OnbHead(
            title: 'Stay in rhythm.',
            sub: 'Gentle nudges keep your streak alive — never spam.',
            center: true,
          ),
          _CmCard(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4),
            child: Column(
              children: [
                for (final (i, r) in _rows.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      border: i < _rows.length - 1
                          ? Border(
                              bottom: BorderSide(color: ZveltTokens.border))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(r.$1, size: 18, color: ZveltTokens.brand),
                        const SizedBox(width: ZveltTokens.s3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.$2,
                                style: TextStyle(
                                  fontFamily: ZveltTokens.fontPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: ZveltTokens.text,
                                ),
                              ),
                              Text(
                                r.$3,
                                style: TextStyle(
                                  fontFamily: ZveltTokens.fontPrimary,
                                  fontSize: 11,
                                  color: ZveltTokens.text3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
