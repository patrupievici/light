// Zvelt — Onboarding 2 · ACT 3 (Feature Discovery). Screens 11–18.
//
// Product previews: the names, numbers and charts on these screens are demo
// illustrations of features, not user data. They mirror the live app surfaces
// 1:1 so the tour feels like the real thing.
//
// Faithful Flutter port of the design bundle's `onboarding-screens-2.jsx`
// (FeatCaption / FeedPostMini / MacroRing / MacroBar / MiniRing + the 8
// screens), rebuilt on the onboarding2 kit (OnbShell / OnbHead /
// OnbPrimaryButton / OnbTileIcon / OnbEyebrow) and ZveltTokens / ZType.
//
// These screens are purely informational (faithful content + Next); they
// keep the [OnbScreenArgs] interface but wire no backend.
//
// STUB layer notes → onboarding2_intro.dart.

part of 'onboarding2.dart';

// ═════════════════════════════════════════════════════════════════════════════
// LOCAL PREVIEW PRIMITIVES — ports of the JSX helpers used across these screens.
// Private to this part file so they don't collide with the rest of the flow.
// ═════════════════════════════════════════════════════════════════════════════

/// JSX `FeatCaption` — eyebrow (mono, brand-deep) → 26px display title → sub.
/// Tighter than [OnbHead]; used as the per-pillar feature heading.
class _FeatCaptionBlock extends StatelessWidget {
  const _FeatCaptionBlock({required this.eyebrow, required this.title, this.sub});
  final String eyebrow;
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ZveltTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnbEyebrow(eyebrow, color: ZveltTokens.brandDeep),
          const SizedBox(height: ZveltTokens.s2),
          Text(
            title,
            style: ZType.display.copyWith(fontSize: 26, height: 1.15),
          ),
          if (sub != null) ...[
            const SizedBox(height: ZveltTokens.s2),
            Text(
              sub!,
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 13.5,
                height: 1.5,
                color: ZveltTokens.text2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Eyebrow with a leading glyph — JSX `<Eyebrow icon="flame">`.
class _OnbEyebrowIcon extends StatelessWidget {
  const _OnbEyebrowIcon({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: ZveltTokens.text3),
        const SizedBox(width: 6),
        OnbEyebrow(text),
      ],
    );
  }
}

/// JSX `Avatar` (gradient initial chip). Local lightweight port — the
/// onboarding2 library doesn't import ZveltAvatar, so this keeps the part
/// file self-contained.
class _OnbAvatar extends StatelessWidget {
  const _OnbAvatar({
    required this.initials,
    this.size = 40,
    this.accent = true,
    this.online = false,
  });

  final String initials;
  final double size;
  final bool accent;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: accent ? ZveltTokens.gradBrand : null,
              color: accent ? null : ZveltTokens.surface3,
            ),
            child: Text(
              initials,
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.4,
                color: accent ? Colors.white : ZveltTokens.text,
              ),
            ),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.26,
                height: size * 0.26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZveltTokens.success,
                  border: Border.all(color: ZveltTokens.bg, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// JSX `.z-chip` — pill, soft tint, no border. `brand` variant uses the peach
/// tint + brand-deep text; plain variant uses the elevated surface.
class _OnbChip extends StatelessWidget {
  const _OnbChip(this.label, {this.brand = false});
  final String label;
  final bool brand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: brand ? ZveltTokens.brandTint : ZveltTokens.surface2,
        borderRadius: BorderRadius.circular(ZveltTokens.rPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: ZveltTokens.fontPrimary,
          fontWeight: FontWeight.w500,
          fontSize: 11,
          letterSpacing: 0.11,
          color: brand ? ZveltTokens.brandDeep : ZveltTokens.text2,
        ),
      ),
    );
  }
}

/// White card surface matching the JSX `.z-card` (rounded, soft shadow, no
/// border). Mirrors the onboarding2 select-card treatment without the picker
/// interactivity.
class _OnbCard extends StatelessWidget {
  const _OnbCard({
    required this.child,
    this.padding = const EdgeInsets.all(ZveltTokens.s4),
    this.radius = ZveltTokens.rLg,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: ZveltTokens.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: ZveltTokens.shadowCard,
      ),
      child: child,
    );
  }
}

/// JSX `FeedPostMini` — the social feed card language, miniaturized.
class _FeedPostMini extends StatelessWidget {
  const _FeedPostMini({
    required this.name,
    required this.sub,
    required this.initials,
    required this.text,
    required this.likes,
    required this.comments,
    this.accent = true,
    this.chip,
    this.pr,
  });

  final String name;
  final String sub;
  final String initials;
  final String text;
  final String likes;
  final String comments;
  final bool accent;
  final String? chip;
  final String? pr;

  @override
  Widget build(BuildContext context) {
    return _OnbCard(
      padding: const EdgeInsets.all(ZveltTokens.s4),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _OnbAvatar(initials: initials, size: 40, accent: accent, online: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: ZveltTokens.text,
                      ),
                    ),
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
              if (chip != null) _OnbChip(chip!, brand: true),
            ],
          ),
          const SizedBox(height: ZveltTokens.s3),
          Text(
            text,
            style: TextStyle(
              fontFamily: ZveltTokens.fontPrimary,
              fontSize: 13.5,
              height: 1.5,
              color: ZveltTokens.text,
            ),
          ),
          if (pr != null) ...[
            const SizedBox(height: ZveltTokens.s3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: ZveltTokens.bg2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(AppIcons.trophy,
                      size: 18, color: ZveltTokens.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      pr!,
                      style: TextStyle(
                        fontFamily: ZveltTokens.fontPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: ZveltTokens.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(AppIcons.heart, size: 15, color: ZveltTokens.cardio),
              const SizedBox(width: 6),
              Text(likes,
                  style: ZType.monoS.copyWith(fontSize: 12, color: ZveltTokens.text3)),
              const SizedBox(width: 18),
              Icon(AppIcons.comment_alt,
                  size: 15, color: ZveltTokens.text3),
              const SizedBox(width: 6),
              Text(comments,
                  style: ZType.monoS.copyWith(fontSize: 12, color: ZveltTokens.text3)),
              const Spacer(),
              Icon(AppIcons.share, size: 15, color: ZveltTokens.text3),
            ],
          ),
        ],
      ),
    );
  }
}

/// JSX `MacroBar` — label + value/goal mono readout over a thin progress track.
class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.label,
    required this.value,
    required this.goal,
    required this.color,
  });

  final String label;
  final int value;
  final int goal;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: ZveltTokens.fontPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ZveltTokens.text2,
              ),
            ),
            Text('$value/${goal}g',
                style: ZType.monoXS.copyWith(color: ZveltTokens.text3)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          child: LinearProgressIndicator(
            value: (value / goal).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: ZveltTokens.surface3,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

/// JSX `MiniRing` — a labeled readiness ring. Used on the AI-coach white card
/// (light variant: dark-readable centered number, muted track).
class _MiniRing extends StatelessWidget {
  const _MiniRing({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 58,
                height: 58,
                child: CircularProgressIndicator(
                  value: value / 100,
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                  color: color,
                  backgroundColor: ZveltTokens.surface3,
                ),
              ),
              Text('$value',
                  style: ZType.stat.copyWith(fontSize: 16, color: ZveltTokens.text)),
            ],
          ),
        ),
        const SizedBox(height: ZveltTokens.s2),
        Text(
          label,
          style: TextStyle(
            fontFamily: ZveltTokens.fontPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: ZveltTokens.text3,
          ),
        ),
      ],
    );
  }
}

/// JSX `Sparkline` — smooth stroke + soft area fill + end dot. Demo data only.
class _Sparkline extends StatelessWidget {
  const _Sparkline({
    required this.values,
    required this.color,
    this.height = 56,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(values: values, color: color),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final mn = values.reduce((a, b) => a < b ? a : b);
    final mx = values.reduce((a, b) => a > b ? a : b);
    final rng = mx == mn ? 1.0 : mx - mn;
    const pad = 2.0;

    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * (size.width - pad * 2) + pad;
      final y = size.height - pad - ((values[i] - mn) / rng) * (size.height - pad * 2);
      pts.add(Offset(x, y));
    }

    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      line.lineTo(pts[i].dx, pts[i].dy);
    }

    // Soft area fill under the line.
    final area = Path.from(line)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    final grad = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.25),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(area, grad);

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // End dot with white halo.
    canvas.drawCircle(pts.last, 3, Paint()..color = color);
    canvas.drawCircle(
      pts.last,
      3,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color;
}

/// A simple list row used by the feature-overview / nutrition / coach lists.
/// Tinted icon tile + title/sub + an optional trailing widget; hairline
/// divider between rows (JSX `borderBottom: 1px solid var(--z-border)`).
class _PreviewRow extends StatelessWidget {
  _PreviewRow({
    required this.icon,
    required this.title,
    required this.sub,
    required this.showDivider,
    this.iconColor = ZveltTokens.brand,
    Color? iconBg,
    this.tileSize = 44,
    this.iconSize = 22,
    this.trailing,
    this.crossStart = false,
  }) : iconBg = iconBg ?? ZveltTokens.brandTint;

  final IconData icon;
  final String title;
  final String sub;
  final bool showDivider;
  final Color iconColor;
  final Color iconBg;
  final double tileSize;
  final double iconSize;
  final Widget? trailing;
  final bool crossStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: ZveltTokens.border))
            : null,
      ),
      child: Row(
        crossAxisAlignment:
            crossStart ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          OnbTileIcon(
            icon: icon,
            color: iconColor,
            bg: iconBg,
            size: tileSize,
            iconSize: iconSize,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ZveltTokens.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  sub,
                  style: TextStyle(
                    fontFamily: ZveltTokens.fontPrimary,
                    fontSize: 12,
                    height: 1.45,
                    color: ZveltTokens.text3,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: ZveltTokens.s3),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 11 · ScrFeatureOverview — everything, working together (feature list).
// ─────────────────────────────────────────────────────────────────────────────
class ScrFeatureOverview extends StatelessWidget {
  const ScrFeatureOverview({super.key, required this.args});
  final OnbScreenArgs args;

  static final List<(IconData, String, String, Color, Color)> _items = [
    (AppIcons.globe, 'Social', 'Feed, groups, challenges & leaderboards',
        ZveltTokens.brand, ZveltTokens.brandTint),
    (AppIcons.restaurant, 'Nutrition', 'AI meal plans, macros & grocery lists',
        ZveltTokens.strength, ZveltTokens.strength2),
    (AppIcons.sparkles, 'AI Coach', 'Daily guidance to hit your goal',
        ZveltTokens.recovery, ZveltTokens.recovery2),
    (AppIcons.chart_line_up, 'Tracking', 'Streaks, volume & body progress',
        ZveltTokens.sleep, ZveltTokens.sleep2),
  ];

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'Take the tour', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: "What's inside",
            title: 'Everything, working together.',
          ),
          _OnbCard(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4),
            radius: 20,
            child: Column(
              children: [
                for (final (i, it) in _items.indexed)
                  _PreviewRow(
                    icon: it.$1,
                    title: it.$2,
                    sub: it.$3,
                    iconColor: it.$4,
                    iconBg: it.$5,
                    showDivider: i < _items.length - 1,
                    trailing: Icon(AppIcons.angle_small_right,
                        size: 16, color: ZveltTokens.text3),
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
// 12 · ScrSocialFeed — pillar 1 · Social. A feed that pushes you.
// ─────────────────────────────────────────────────────────────────────────────
class ScrSocialFeed extends StatelessWidget {
  const ScrSocialFeed({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'Next', onTap: args.next),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FeatCaptionBlock(
            eyebrow: 'Pillar 1 · Social',
            title: 'A feed that pushes you.',
            sub: 'See your crew train in real time. Celebrate PRs. '
                'Never miss a session.',
          ),
          _FeedPostMini(
            name: 'Lucas V',
            sub: 'Push · Day 12 · 18m ago',
            initials: 'L',
            text: 'New bench PR today 💪 the grind is paying off.',
            chip: 'PR',
            pr: 'Bench Press · 100 kg',
            likes: '124',
            comments: '18',
          ),
          SizedBox(height: 12),
          _FeedPostMini(
            name: 'Anna B',
            sub: '5K run · 1h ago',
            initials: 'A',
            accent: false,
            text: 'Sub-25 finally! Thanks for the pacing tips everyone.',
            likes: '86',
            comments: '9',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 13 · ScrSocialDetail — compete, belong, climb (tiles + leaderboard).
// ─────────────────────────────────────────────────────────────────────────────
class ScrSocialDetail extends StatelessWidget {
  const ScrSocialDetail({super.key, required this.args});
  final OnbScreenArgs args;

  static const List<(IconData, String, String)> _tiles = [
    (AppIcons.globe, 'Groups', '12 joined'),
    (AppIcons.trophy, 'Challenges', '3 active'),
    (AppIcons.chart_histogram, 'Leaderboards', 'Top 5%'),
  ];

  static const List<(int, String, String, bool)> _board = [
    (1, 'Lucas V', '24.4k', false),
    (2, 'Yusuf K', '18.2k', false),
    (3, 'You', '11.4k', true),
  ];

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'Next', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FeatCaptionBlock(
            eyebrow: 'Social · deeper',
            title: 'Compete. Belong. Climb.',
          ),
          Row(
            children: [
              for (final (i, t) in _tiles.indexed) ...[
                if (i > 0) const SizedBox(width: ZveltTokens.s2),
                Expanded(
                  child: _OnbCard(
                    padding: const EdgeInsets.all(14),
                    radius: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(t.$1, size: 18, color: ZveltTokens.brand),
                        const SizedBox(height: ZveltTokens.s3),
                        Text(
                          t.$2,
                          style: TextStyle(
                            fontFamily: ZveltTokens.fontPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: ZveltTokens.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          t.$3,
                          style: TextStyle(
                            fontFamily: ZveltTokens.fontPrimary,
                            fontSize: 10.5,
                            color: ZveltTokens.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _OnbCard(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            radius: 18,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: ZveltTokens.s3, bottom: ZveltTokens.s1),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OnbEyebrow('May Bench Bash · leaderboard'),
                  ),
                ),
                for (final (i, b) in _board.indexed)
                  Container(
                    padding: EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: b.$4 ? ZveltTokens.s2 : 0,
                    ),
                    decoration: BoxDecoration(
                      color: b.$4 ? ZveltTokens.brand.withValues(alpha: 0.06) : null,
                      borderRadius:
                          BorderRadius.circular(b.$4 ? ZveltTokens.rSm : 0),
                      border: i < _board.length - 1
                          ? Border(
                              bottom: BorderSide(color: ZveltTokens.border))
                          : null,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            '#${b.$1}',
                            style: TextStyle(
                              fontFamily: ZveltTokens.fontMono,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: ZveltTokens.text3,
                            ),
                          ),
                        ),
                        _OnbAvatar(
                          initials: b.$2[0],
                          size: 28,
                          accent: !b.$4,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            b.$2,
                            style: TextStyle(
                              fontFamily: ZveltTokens.fontPrimary,
                              fontSize: 13,
                              fontWeight:
                                  b.$4 ? FontWeight.w700 : FontWeight.w500,
                              color: ZveltTokens.text,
                            ),
                          ),
                        ),
                        Text(
                          b.$3,
                          style: ZType.stat.copyWith(
                            fontSize: 14,
                            color: b.$4 ? ZveltTokens.brand : ZveltTokens.text,
                          ),
                        ),
                        const SizedBox(width: ZveltTokens.s1),
                        Text(
                          'LP',
                          style: TextStyle(
                            fontFamily: ZveltTokens.fontPrimary,
                            fontSize: 10,
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
// 14 · ScrNutrition — pillar 2 · Nutrition. Your day, already planned.
// ─────────────────────────────────────────────────────────────────────────────
class ScrNutrition extends StatelessWidget {
  const ScrNutrition({super.key, required this.args});
  final OnbScreenArgs args;

  static const List<(IconData, String, String, String)> _meals = [
    (AppIcons.restaurant, 'Breakfast', 'Greek yogurt & berries', '420'),
    (AppIcons.flame, 'Lunch', 'Chicken, rice & greens', '640'),
    (AppIcons.sparkles, 'Dinner', 'Salmon & sweet potato', '580'),
  ];

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'Next', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FeatCaptionBlock(
            eyebrow: 'Pillar 2 · Nutrition',
            title: 'Your day, already planned.',
            sub: 'A meal plan built around your goal, macros tracked '
                'automatically.',
          ),
          _OnbCard(
            padding: const EdgeInsets.all(18),
            radius: 20,
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 76,
                        height: 76,
                        child: CircularProgressIndicator(
                          value: 0.62,
                          strokeWidth: 7,
                          strokeCap: StrokeCap.round,
                          color: ZveltTokens.brand,
                          backgroundColor: ZveltTokens.surface3,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('1,480',
                              style: ZType.stat.copyWith(
                                  fontSize: 20, color: ZveltTokens.text)),
                          const SizedBox(height: 2),
                          Text(
                            'of 2,400',
                            style: TextStyle(
                              fontFamily: ZveltTokens.fontPrimary,
                              fontSize: 9,
                              color: ZveltTokens.text3,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: ZveltTokens.s4),
                const Expanded(
                  child: Column(
                    children: [
                      _MacroBar(
                          label: 'Protein',
                          value: 112,
                          goal: 180,
                          color: ZveltTokens.brand),
                      SizedBox(height: 10),
                      _MacroBar(
                          label: 'Carbs',
                          value: 156,
                          goal: 240,
                          color: ZveltTokens.strain),
                      SizedBox(height: 10),
                      _MacroBar(
                          label: 'Fats',
                          value: 42,
                          goal: 70,
                          color: ZveltTokens.sleep),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _OnbCard(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4),
            radius: 20,
            child: Column(
              children: [
                for (final (i, m) in _meals.indexed)
                  _PreviewRow(
                    icon: m.$1,
                    title: m.$2,
                    sub: m.$3,
                    tileSize: 40,
                    iconSize: 20,
                    iconColor: ZveltTokens.text2,
                    iconBg: ZveltTokens.bg2,
                    showDivider: i < _meals.length - 1,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(m.$4,
                            style: ZType.monoS.copyWith(
                                fontSize: 13, color: ZveltTokens.text2)),
                        const SizedBox(width: 4),
                        Text(
                          'kcal',
                          style: TextStyle(
                            fontFamily: ZveltTokens.fontPrimary,
                            fontSize: 10,
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
// 15 · ScrNutritionDetail — an AI that fills the gaps (suggestion + grocery).
// ─────────────────────────────────────────────────────────────────────────────
class ScrNutritionDetail extends StatelessWidget {
  const ScrNutritionDetail({super.key, required this.args});
  final OnbScreenArgs args;

  static const List<String> _grocery = [
    'Chicken breast',
    'Greek yogurt',
    'Oats',
    'Berries',
    'Salmon',
    'Sweet potato',
    'Eggs',
    'Spinach',
  ];

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'Next', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FeatCaptionBlock(
            eyebrow: 'Nutrition · deeper',
            title: 'An AI that fills the gaps.',
          ),
          _OnbCard(
            padding: const EdgeInsets.all(ZveltTokens.s4),
            radius: 20,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ZveltTokens.brandTint,
                    borderRadius: BorderRadius.circular(ZveltTokens.rSm),
                  ),
                  child: const Icon(AppIcons.sparkles,
                      size: 17, color: ZveltTokens.brandDeep),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const OnbEyebrow('Coach suggestion'),
                      const SizedBox(height: 6),
                      Text(
                        "You're 68g protein short today. Add a whey shake or "
                        '150g chicken to hit your target.',
                        style: TextStyle(
                          fontFamily: ZveltTokens.fontPrimary,
                          fontSize: 13,
                          height: 1.55,
                          color: ZveltTokens.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _OnbCard(
            padding: const EdgeInsets.all(ZveltTokens.s4),
            radius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OnbEyebrow('Auto grocery list'),
                    _OnbChip('12 items', brand: true),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final g in _grocery) _OnbChip(g)],
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
// 16 · ScrBiology2 — pillar 3 · AI Coach. A coach in your pocket.
// ─────────────────────────────────────────────────────────────────────────────
class ScrBiology2 extends StatelessWidget {
  const ScrBiology2({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'Next', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const OnbHead(
            eyebrow: 'Pillar 3 · AI Coach',
            title: 'A coach in your pocket.',
            sub: "Zvelt's AI reads your training, recovery and sleep — then "
                'tells you exactly what to do today to reach your goal.',
          ),

          // Coach message — the "talking to you" moment.
          _OnbCard(
            padding: const EdgeInsets.all(ZveltTokens.s4),
            radius: 22,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(-0.36, -0.44),
                      colors: [
                        ZveltTokens.brand3,
                        ZveltTokens.brand,
                        ZveltTokens.brandDeep,
                      ],
                      stops: [0, 0.56, 1],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ZveltTokens.brandGlow,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(AppIcons.sparkles,
                      size: 20, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            'Zvelt Coach',
                            style: TextStyle(
                              fontFamily: ZveltTokens.fontPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ZveltTokens.text,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· just now',
                            style: TextStyle(
                              fontFamily: ZveltTokens.fontPrimary,
                              fontSize: 10.5,
                              color: ZveltTokens.text3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontFamily: ZveltTokens.fontPrimary,
                            fontSize: 13.5,
                            height: 1.5,
                            color: ZveltTokens.text,
                          ),
                          children: const [
                            TextSpan(
                                text: 'You recovered well and slept 8h — '
                                    "today's a green light. I bumped your "
                                    'squat to '),
                            TextSpan(
                              text: '102.5 kg',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                                text: ". Hit it and you're on pace for your "
                                    '12-week goal. 💪'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Readiness summary — white card, dark-readable rings + soft halo.
          ClipRRect(
            borderRadius: BorderRadius.circular(ZveltTokens.rLg),
            child: _OnbCard(
              padding: EdgeInsets.zero,
              radius: ZveltTokens.rLg,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.6, -1),
                          radius: 0.9,
                          colors: [
                            ZveltTokens.brand.withValues(alpha: 0.12),
                            ZveltTokens.brand.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WHAT YOUR COACH SEES TODAY',
                          style: TextStyle(
                            fontFamily: ZveltTokens.fontPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.88,
                            color: ZveltTokens.text3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('Primed to train',
                            style: ZType.display.copyWith(fontSize: 22)),
                        const SizedBox(height: 18),
                        const Row(
                          children: [
                            Expanded(
                              child: _MiniRing(
                                  label: 'Strain',
                                  value: 62,
                                  color: ZveltTokens.strain),
                            ),
                            Expanded(
                              child: _MiniRing(
                                  label: 'Recovery',
                                  value: 68,
                                  color: ZveltTokens.recovery),
                            ),
                            Expanded(
                              child: _MiniRing(
                                  label: 'Sleep',
                                  value: 84,
                                  color: ZveltTokens.sleep),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 17 · ScrBiologyDetail — it adapts to you, daily (what the coach does).
// ─────────────────────────────────────────────────────────────────────────────
class ScrBiologyDetail extends StatelessWidget {
  const ScrBiologyDetail({super.key, required this.args});
  final OnbScreenArgs args;

  static final List<(IconData, String, String, Color, Color)> _actions = [
    (AppIcons.gym, 'Tunes every workout',
        'Sets your weights & volume to match how recovered you are',
        ZveltTokens.brand, ZveltTokens.brandTint),
    (AppIcons.heart, 'Knows when to rest',
        'Spots fatigue early and protects you from injury',
        ZveltTokens.cardio, ZveltTokens.cardio2),
    (AppIcons.restaurant, 'Closes your nutrition gaps',
        'Tells you exactly what to eat to hit your macros',
        ZveltTokens.strength, ZveltTokens.strength2),
    (AppIcons.location_alt, 'Keeps you on your goal',
        'Nudges the next right move so you stay on pace',
        ZveltTokens.sleep, ZveltTokens.sleep2),
  ];

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: 'Next', onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FeatCaptionBlock(
            eyebrow: 'AI Coach · how it helps',
            title: 'It adapts to you, daily.',
            sub: 'Not just data — real decisions made for you, every '
                'single day.',
          ),
          _OnbCard(
            padding: const EdgeInsets.symmetric(horizontal: ZveltTokens.s4),
            radius: 20,
            child: Column(
              children: [
                for (final (i, a) in _actions.indexed)
                  _PreviewRow(
                    icon: a.$1,
                    title: a.$2,
                    sub: a.$3,
                    iconColor: a.$4,
                    iconBg: a.$5,
                    tileSize: 42,
                    iconSize: 21,
                    crossStart: true,
                    showDivider: i < _actions.length - 1,
                    trailing: const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(AppIcons.check,
                          size: 16, color: ZveltTokens.success),
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
// 18 · ScrTracking — pillar 4 · Tracking. Watch yourself evolve.
// ─────────────────────────────────────────────────────────────────────────────
class ScrTracking extends StatelessWidget {
  const ScrTracking({super.key, required this.args});
  final OnbScreenArgs args;

  @override
  Widget build(BuildContext context) {
    return OnbShell(
      onBack: args.back,
      footer: OnbPrimaryButton(label: "I'm in", onTap: args.next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FeatCaptionBlock(
            eyebrow: 'Pillar 4 · Tracking',
            title: 'Watch yourself evolve.',
            sub: 'Streaks, volume and body change — visible every single day.',
          ),
          _OnbCard(
            padding: const EdgeInsets.all(ZveltTokens.s4),
            radius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _OnbEyebrowIcon(
                            icon: AppIcons.flame,
                            text: 'Current streak'),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('12',
                                style: ZType.stat.copyWith(
                                    fontSize: 32, color: ZveltTokens.text)),
                            const SizedBox(width: 6),
                            Text(
                              'days',
                              style: TextStyle(
                                fontFamily: ZveltTokens.fontPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: ZveltTokens.text3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('+18%',
                            style: ZType.stat.copyWith(
                                fontSize: 22, color: ZveltTokens.brand)),
                        const SizedBox(height: 2),
                        Text(
                          'strength · 12 wks',
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
                const SizedBox(height: 14),
                const _Sparkline(
                  values: [100, 104, 108, 110, 116, 120, 125, 132],
                  color: ZveltTokens.brand,
                  height: 56,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _OnbCard(
            padding: const EdgeInsets.all(ZveltTokens.s4),
            radius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const OnbEyebrow('Consistency · 365 days'),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, c) {
                    const weeks = 52;
                    final cell =
                        ((c.maxWidth - (weeks - 1) * 2) / weeks).clamp(3.0, 6.0);
                    const pattern = [0, 0, 1, 0, 1, 2, 0, 1, 0, 1, 2, 3, 1, 0];
                    Color cellColor(int v) {
                      switch (v) {
                        case 0:
                          return ZveltTokens.surface2;
                        case 1:
                          return ZveltTokens.brand.withValues(alpha: 0.22);
                        case 2:
                          return ZveltTokens.brand.withValues(alpha: 0.55);
                        default:
                          return ZveltTokens.brand;
                      }
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var wi = 0; wi < weeks; wi++)
                          Column(
                            children: [
                              for (var di = 0; di < 7; di++)
                                Container(
                                  width: cell,
                                  height: cell,
                                  margin: const EdgeInsets.only(bottom: 2),
                                  decoration: BoxDecoration(
                                    color: cellColor(
                                        pattern[((wi + di) * 3) % 14]),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  '247 sessions · 198 hours',
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
    );
  }
}
