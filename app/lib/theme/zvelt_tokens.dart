import 'package:flutter/material.dart';

/// ZVELT design tokens — **dark-first, warm-lit orange system** (Claude Design
/// handoff v1.0). Near-black warm base with orange radial glows, a single warm
/// orange signal (`#F5820A`), liquid glass on floating layers, Manrope type.
///
/// This class keeps the historical getter/const **API shape** (so the ~5.5k
/// existing call sites compile) while repointing every value to the new
/// palette, and adds the new members the handoff needs (accent gradients,
/// orange-glow shadows, glass radii, appBg glow colors).
///
/// Neutrals resolve at runtime against [isDark] (dark is the default); the
/// orange brand + status colors are theme-independent. Because the neutral
/// getters + [ZType] styles are runtime getters they are NOT usable inside
/// `const` expressions — widgets that color/style from them drop `const`.
///
/// Flip [isDark] from the app root (see main.dart) on theme-mode / platform
/// brightness change; the surrounding ValueListenableBuilder rebuilds the tree.
class ZveltTokens {
  ZveltTokens._();

  /// Global brightness flag — owned by the app root, read by every neutral.
  /// **Dark by default** (the handoff is dark-first).
  static bool isDark = true;

  /// Pick the light or dark value for the active brightness.
  static Color _d(Color light, Color dark) => isDark ? dark : light;

  // ─── Neutral backgrounds (warm, never flat gray / pure black-or-white) ─────
  /// Page background base color (the two warm radial glows are painted on top
  /// by ZveltScaffold; this is the solid under them).
  static Color get bg => _d(const Color(0xFFF6F1E9), const Color(0xFF0E0A07));

  /// Slightly lifted page / inset block.
  static Color get bg2 => _d(const Color(0xFFF1EBE0), const Color(0xFF15100B));

  /// Card surface (glass-over-dark composited to an opaque warm tone; the true
  /// translucent glass is available via [surfaceGrad] + [glassBlur]).
  static Color get surface =>
      _d(const Color(0xFFFFFFFF), const Color(0xFF241A12));

  /// Subtle inset inside cards / dense rows.
  static Color get surface2 =>
      _d(const Color(0xFFFBF6EE), const Color(0xFF2A2018));

  /// Track behind progress / muted thumb.
  static Color get surface3 =>
      _d(const Color(0xFFEFE7DA), const Color(0xFF342820));

  /// Accent-soft warm hero surface.
  static Color get surfaceTinted =>
      _d(const Color(0xFFFFE9D2), const Color(0xFF3A2614));

  // ─── Text (primary / secondary / tertiary + decorative 4th) ────────────────
  static Color get text => _d(const Color(0xFF231C14), const Color(0xFFFFFFFF));
  static Color get text2 =>
      _d(const Color(0xFF8A7F6F), const Color(0xFF9B8F81));
  static Color get text3 =>
      _d(const Color(0xFFA89C8B), const Color(0xFF8A7E70));
  static Color get text4 =>
      _d(const Color(0xFFB9AE9C), const Color(0xFF6E6458));

  // ─── Borders — 1px hairline on every surface (top-lit) ─────────────────────
  static Color get border =>
      _d(const Color(0x99FFFFFF), const Color(0x24FFFFFF));
  static Color get borderStrong =>
      _d(const Color(0x2E281C10), const Color(0x33FFFFFF));

  /// Hairline divider.
  static Color get hairline =>
      _d(const Color(0x14281C10), const Color(0x14FFFFFF));

  // ─── Structural neutrals (chip / track / iconBg / scrim) ───────────────────
  static Color get chip => _d(const Color(0x0D281C10), const Color(0x0DFFFFFF));
  static Color get track =>
      _d(const Color(0x1A281C10), const Color(0x1AFFFFFF));
  static Color get iconBg =>
      _d(const Color(0x0D281C10), const Color(0x12FFFFFF));
  static Color get scrim => const Color(0x80000000);

  // ─── Accent — warm orange (signal only; constant across modes) ─────────────
  /// accent-primary — CTAs, active tab, selected state, ring.
  static const Color brand = Color(0xFFF5820A);

  /// accent-light — gradient start stop on icon squares & AI button.
  static const Color brand2 = Color(0xFFFFA430);

  /// ring-start — top of progress-ring gradient / halo.
  static const Color brand3 = Color(0xFFFFB24D);

  /// accent-deep — gradient end stop, pressed CTA.
  static const Color brandDeep = Color(0xFFEE6E08);

  /// accent-soft — warm orange tint (chip bg, streak badge fill).
  static Color get brandTint =>
      _d(const Color(0x24F5820A), const Color(0x26F5820A));

  /// warm orange glow color — rgba(240,120,12,.5).
  static const Color brandGlow = Color(0x80F0780C);
  static const Color onBrand = Color(0xFFFFFFFF);

  // Named accent aliases (handoff token names) — same values, clearer intent.
  static const Color accent = brand;
  static const Color accentDeep = brandDeep;
  static const Color accentLight = brand2;
  static const Color accentHover = Color(0xFFFF9A33);
  static const Color ringStart = brand3;
  static const Color ringEnd = brandDeep;

  /// Cycling / ride gold accent (the one sanctioned accent variant).
  static const Color cardioGold = Color(0xFFF3CE7E);
  static const Color cardioGoldDeep = Color(0xFFD79A3A);

  // ─── Status / category palette (harmonized to the warm system) ─────────────
  // Category accents kept under their historical names so existing call sites
  // compile; remapped to the warm-system status/gold values.
  static const Color recovery = Color(0xFF4DA3FF); // info blue (rare)
  static const Color recovery2 = Color(0xFFDCE7FB);
  static const Color sleep = Color(0xFFA78BFA);
  static const Color sleep2 = Color(0xFFEAE3FE);
  static const Color stress = Color(0xFFF5A524); // warning amber
  static const Color stress2 = Color(0xFFFCEBC9);
  static const Color strain = Color(0xFFF5A524);
  static const Color strain2 = Color(0xFFFCEBC9);
  static const Color strength = Color(0xFF32C27C); // success green
  static const Color strength2 = Color(0xFFCDEFDD);
  static const Color cardio = brand; // run = orange accent
  static const Color cardio2 = Color(0xFFFBDFC2);

  /// challenge / gold accent.
  static const Color challenge = cardioGold;

  // ─── Semantic (system-defined, warm-harmonized) ────────────────────────────
  static const Color success = Color(0xFF32C27C);
  static const Color successSoft = Color(0xFFCDEFDD);
  static const Color info = Color(0xFF4DA3FF);
  static const Color warn = Color(0xFFF5A524);
  static const Color error = Color(0xFFFF483C);

  // ─── Typography family — Manrope everywhere ────────────────────────────────
  // google_fonts registers the family under this exact name (ZType + the app
  // TextTheme funnel through GoogleFonts.manrope), so raw `fontFamily` refs in
  // const contexts resolve to the loaded Manrope. Kept const for those sites.
  static const String fontPrimary = 'Manrope';
  static const String fontDisplay = 'Manrope';
  static const String fontMono = 'Manrope';

  // ─── Radii — rounded everything; scale with element size ───────────────────
  // Historical names remapped UP into the rounder handoff scale so existing
  // cards/controls adopt the new corner language automatically.
  static const double rSm = 14; // chips / small tiles / icon squares
  static const double rMd = 16; // controls, inputs, list rows, toast
  static const double rLg = 24; // standard cards
  static const double rXl = 28; // hero / large feature cards
  static const double rPill = 999;
  // New explicit handoff radii (use directly when rebuilding screens).
  static const double rChip = 14;
  static const double rControl = 16;
  static const double rBox = 20;
  static const double rCardSm = 22;
  static const double rCard = 24;
  static const double rCardLg = 26;
  static const double rHero = 28;
  static const double rSheet = 30;
  static const double rNav = 34;

  // ─── Spacing rhythm (4pt) ──────────────────────────────────────────────────
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;

  /// Screen edge padding L/R.
  static const double screenPaddingH = 20;

  /// Default card-to-card gap.
  static const double cardGap = 12;

  /// Bottom scroll inset so content clears the floating nav.
  static const double navSafeBottom = 116;

  // ─── Blur (liquid glass) ───────────────────────────────────────────────────
  static const double glassBlur = 24; // nav + sheets
  static const double chipBlur = 8;

  // ─── Shadows — warm orange glow (brand) + neutral depth (structure) ────────
  // Historical card/hero/float names kept. Card depth stays deliberately short
  // so repeated surfaces remain crisp and cheap to render while scrolling.
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x38000000), offset: Offset(0, 4), blurRadius: 10),
  ];
  static const List<BoxShadow> shadowHero = [
    BoxShadow(color: Color(0x40000000), offset: Offset(0, 10), blurRadius: 28),
  ];
  static const List<BoxShadow> shadowFloat = [
    BoxShadow(color: Color(0x59000000), offset: Offset(0, 12), blurRadius: 30),
  ];

  /// Orange glow — small gradient icon squares.
  static const List<BoxShadow> glowSm = [
    BoxShadow(color: Color(0x73F0780C), offset: Offset(0, 5), blurRadius: 12),
  ];

  /// Orange glow — primary CTA, streak circle, logo mark.
  static const List<BoxShadow> glowMd = [
    BoxShadow(color: Color(0x80F0780C), offset: Offset(0, 6), blurRadius: 16),
  ];

  /// Orange glow — large CTA, premium banner.
  static const List<BoxShadow> glowLg = [
    BoxShadow(color: Color(0x66F0780C), offset: Offset(0, 10), blurRadius: 24),
  ];

  /// Center AI nav button glow.
  static const List<BoxShadow> glowAi = [
    BoxShadow(color: Color(0x99EE6E08), offset: Offset(0, 10), blurRadius: 24),
    BoxShadow(
        color: Color(0x66FFFFFF),
        offset: Offset(0, 1),
        blurRadius: 1,
        spreadRadius: -0.5),
  ];

  /// Alias kept for older call sites.
  static const List<BoxShadow> glowBrand = glowMd;

  // ─── Gradients — accent runs light→deep (top-left → bottom-right) ──────────
  /// Icon squares, logo mark (150°, #FFA430 → #F0720A).
  static const LinearGradient gradAccent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFA430), Color(0xFFF0720A)],
  );

  /// AI button, hero mini-icons (155°, #FFA630 → #EE6E08).
  static const LinearGradient gradAccentDeep = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.6, 1),
    colors: [Color(0xFFFFA630), brandDeep],
  );

  /// Active banners / live pills (100°, #F5820A → #EE6E08).
  static const LinearGradient gradAccentFlat = LinearGradient(
    begin: Alignment(-1, -0.2),
    end: Alignment(1, 0.2),
    colors: [brand, brandDeep],
  );

  /// Progress-ring gradient (#FFB24D → #EE6E08).
  static const LinearGradient gradRing = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [ringStart, ringEnd],
  );

  /// Cycling / ride gold (#F3CE7E → #D79A3A).
  static const LinearGradient gradCardio = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cardioGold, cardioGoldDeep],
  );
  // Historical gradient names → accent gradients.
  static const LinearGradient gradBrand = gradAccent;
  static const LinearGradient gradBtn = gradAccentFlat;
  static const LinearGradient gradHero = gradAccentDeep;

  // ─── Matte-glass surfaces ─────────────────────────────────────────────────
  // These are nearly opaque on purpose. Very transparent warm gradients were
  // exposing background colour bands on some Android GPUs. A quiet neutral
  // highlight keeps the material depth without a BackdropFilter per list row.
  static LinearGradient get surfaceGrad => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [Color(0xF2252423), Color(0xED181818)]
            : const [Color(0xF7FFFFFF), Color(0xF0F5F5F5)],
      );
  static LinearGradient get surface2Grad => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [Color(0xF52B2927), Color(0xF01E1D1C)]
            : const [Color(0xFAFFFFFF), Color(0xF2F7F7F7)],
      );
  static LinearGradient get heroGrad => LinearGradient(
        begin: const Alignment(-0.7, -1),
        end: const Alignment(0.7, 1),
        colors: isDark
            ? const [Color(0xB85A3414), Color(0x9E1A120C)]
            : const [Color(0xEBFFCE96), Color(0xB3FFB270)],
      );
  static Color get heroBorder =>
      _d(const Color(0x66F58214), const Color(0x38F58214));
  static LinearGradient get sheetGrad => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [Color(0xFF241A12), Color(0xFF130D09)]
            : const [Color(0xFFFFFFFF), Color(0xFFF3ECE1)],
      );
  static Color get navBg =>
      _d(const Color(0xB8FFFFFF), const Color(0x9E1A140F));

  // ─── App background (base gradient + two warm radial glows) ────────────────
  static LinearGradient get appBg => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [Color(0xFF100B08), Color(0xFF070504)]
            : const [Color(0xFFF8F5F0), Color(0xFFEBE4D9)],
      );

  /// Large amber glow, top-right, behind content.
  static Color get glowTopRight =>
      _d(const Color(0x8CFCC48A), const Color(0x94965A1A));

  /// Orange glow, bottom-center, behind content + nav.
  static Color get glowBottom =>
      _d(const Color(0x33F5963C), const Color(0x47F58214));
}

/// V2 text-style utility roles — now **Manrope** (google_fonts). Runtime
/// getters (they color from the theme-aware neutrals) so they can't sit inside
/// `const` widgets.
class ZType {
  ZType._();

  static TextStyle _m({
    required double size,
    required FontWeight weight,
    double? tracking,
    double? height,
    Color? color,
    bool tabular = false,
  }) =>
      TextStyle(
        fontFamily: ZveltTokens.fontPrimary, // bundled Manrope
        fontSize: size,
        fontWeight: weight,
        letterSpacing: tracking,
        height: height,
        color: color ?? ZveltTokens.text,
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
      );

  /// Display / big stat — 32/800 tight. Bodyweight, hero metrics.
  static TextStyle get display => _m(
      size: 32,
      weight: FontWeight.w800,
      tracking: -0.6,
      height: 1.0,
      tabular: true);

  /// Clean sans heading — section headers.
  static TextStyle get clean =>
      _m(size: 21, weight: FontWeight.w800, tracking: -0.2, height: 1.15);

  /// KPI stat number — 800 tabular.
  static TextStyle get stat => _m(
      size: 30,
      weight: FontWeight.w800,
      tracking: -0.4,
      height: 1.0,
      tabular: true);

  /// Metric readout — tabular value (pace, distance, weights).
  static TextStyle get num_ =>
      _m(size: 15, weight: FontWeight.w700, height: 1.0, tabular: true);

  /// Eyebrow / overline — 11/800 uppercase, wide tracking (apply .toUpperCase()).
  static TextStyle get eyebrow => _m(
      size: 11,
      weight: FontWeight.w800,
      tracking: 0.8,
      height: 1.2,
      color: ZveltTokens.text2);

  // ── Manrope scale (typography.md) ──────────────────────────────────────────
  static TextStyle get displayXL =>
      _m(size: 48, weight: FontWeight.w800, tracking: -1.0, height: 1.05);
  static TextStyle get displayL =>
      _m(size: 42, weight: FontWeight.w800, tracking: -0.8, height: 1.05);
  static TextStyle get displayM =>
      _m(size: 34, weight: FontWeight.w800, tracking: -0.5, height: 1.08);

  /// Screen greeting ("Today").
  static TextStyle get h1 =>
      _m(size: 26, weight: FontWeight.w800, tracking: -0.3, height: 1.1);

  /// Screen title ("Nutrition").
  static TextStyle get h2 =>
      _m(size: 24, weight: FontWeight.w800, tracking: -0.2, height: 1.12);

  /// Section title ("Consistency", "Muscles").
  static TextStyle get h3 =>
      _m(size: 21, weight: FontWeight.w800, tracking: -0.2, height: 1.2);

  /// Sheet / card title.
  static TextStyle get h4 =>
      _m(size: 18, weight: FontWeight.w800, tracking: -0.1, height: 1.25);
  static TextStyle get bodyL =>
      _m(size: 15, weight: FontWeight.w600, height: 1.5);
  static TextStyle get bodyM =>
      _m(size: 14, weight: FontWeight.w500, height: 1.5);
  static TextStyle get bodyS => _m(
      size: 13, weight: FontWeight.w500, height: 1.5, color: ZveltTokens.text2);
  static TextStyle get monoS => _m(
      size: 12, weight: FontWeight.w600, height: 1.4, color: ZveltTokens.text2);
  static TextStyle get monoXS => _m(
      size: 11, weight: FontWeight.w700, height: 1.3, color: ZveltTokens.text3);
}

/// Motion tokens (handoff `motion.md`): fast in, gentle out. Durations map to
/// durTap (180) / durEnter (280) / durSheet (300); curve is easeOutCubic.
class ZMotion {
  ZMotion._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration quick = Duration(milliseconds: 180); // durTap
  static const Duration standard = Duration(milliseconds: 280); // durEnter
  static const Duration slow = Duration(milliseconds: 300); // durSheet

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve settle = Curves.easeOutCubic;
}
