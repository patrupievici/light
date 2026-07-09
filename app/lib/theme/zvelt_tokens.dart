import 'package:flutter/material.dart';

/// ZVELT design tokens — **light + dark**, "De ce ai nevoie?" periwinkle system.
///
/// Single accent = **periwinkle `#7C84EC`** (signal only). Inter everywhere,
/// soft shadows define cards (no heavy borders), off-white surfaces. Neutrals +
/// accent-soft resolve at runtime against [isDark]; the periwinkle brand +
/// status colors + shadows stay constant across modes. Because the neutrals +
/// [ZType] styles are runtime getters, they are NOT usable inside `const`
/// expressions — widgets that color/style from them must drop `const`.
///
/// Flip [isDark] from the app root (see main.dart) on theme-mode / platform
/// brightness change; the surrounding ValueListenableBuilder rebuilds the tree.
class ZveltTokens {
  ZveltTokens._();

  /// Global brightness flag — owned by the app root, read by every neutral.
  static bool isDark = false;

  /// Pick the light or dark value for the active brightness.
  static Color _d(Color light, Color dark) => isDark ? dark : light;

  // ─── Neutral backgrounds (periwinkle "De ce ai nevoie?" system) ────────────
  /// Page background  (--bg)
  static Color get bg => _d(const Color(0xFFF4F5F9), const Color(0xFF131419));

  /// Inset block bg / secondary card  (--card2)
  static Color get bg2 => _d(const Color(0xFFF2F3F8), const Color(0xFF25262F));

  /// Card surface  (--card)
  static Color get surface =>
      _d(const Color(0xFFFFFFFF), const Color(0xFF1D1E25));

  /// Subtle inset inside cards  (--card2)
  static Color get surface2 =>
      _d(const Color(0xFFF2F3F8), const Color(0xFF25262F));

  /// Track behind progress / muted thumb  (--card3)
  static Color get surface3 =>
      _d(const Color(0xFFE9EAF1), const Color(0xFF2F313B));

  /// Accent-soft hero surface  (--acsoft)
  static Color get surfaceTinted =>
      _d(const Color(0xFFEEEFFD), const Color(0xFF262838));

  // ─── Text (3 levels in the design; text3/text4 are tertiary/decorative) ─────
  static Color get text => _d(const Color(0xFF2A2B3A), const Color(0xFFF1F2F7));
  static Color get text2 =>
      _d(const Color(0xFF82849A), const Color(0xFF9698A8));
  static Color get text3 =>
      _d(const Color(0xFF9A9CAE), const Color(0xFF7E8090));
  static Color get text4 =>
      _d(const Color(0xFFB7B8C6), const Color(0xFF5E606C));

  // ─── Borders — used very sparingly (shadows define cards) ───────────────────
  static Color get border =>
      _d(const Color(0xFFEDEEF4), const Color(0xFF292B34));
  static Color get borderStrong =>
      _d(const Color(0xFFDEDFEA), const Color(0xFF3A3C46));

  /// Hairline divider
  static Color get hairline =>
      _d(const Color(0x0F2D2D50), const Color(0x14FFFFFF));

  // ─── Accent — Periwinkle (signal only; constant across modes) ──────────────
  /// accent-primary  (--ac)
  static const Color brand = Color(0xFF7C84EC);

  /// --ac2
  static const Color brand2 = Color(0xFF9DA3F1);

  /// light variant — halo, gradient top
  static const Color brand3 = Color(0xFFB6BAF5);

  /// accent-hover — press / gradient anchor  (--ac-dark)
  static const Color brandDeep = Color(0xFF5D66D9);

  /// accent-soft — chip bg, hero halo  (--acsoft, theme-aware)
  static Color get brandTint =>
      _d(const Color(0xFFEEEFFD), const Color(0x297C84EC));

  /// accent-glow — rgba(124,132,236,0.38) for CTA glow
  static const Color brandGlow = Color(0x617C84EC);
  static const Color onBrand = Color(0xFFFFFFFF);

  // ─── Status / category palette (periwinkle design) ─────────────────────────
  static const Color recovery = Color(0xFF5B8DEF); // blue
  static const Color recovery2 = Color(0xFFDCE7FB);
  static const Color sleep = Color(0xFFA78BFA); // purple
  static const Color sleep2 = Color(0xFFEAE3FE);
  static const Color stress = Color(0xFFF2C94C); // amber
  static const Color stress2 = Color(0xFFFCEFC9);
  static const Color strain = Color(0xFFF2C94C); // alias to stress
  static const Color strain2 = Color(0xFFFCEFC9);
  static const Color strength = Color(0xFF5FC97D); // green
  static const Color strength2 = Color(0xFFD7F2DF);
  static const Color cardio = Color(0xFFF05252); // red
  static const Color cardio2 = Color(0xFFFBD7D7);

  /// challenge / "ready" accent — orange
  static const Color challenge = Color(0xFFF2994A);

  // ─── Semantic ───────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF5FC97D);
  static const Color successSoft = Color(0xFFD7F2DF);
  static const Color info = Color(0xFF5B8DEF);
  static const Color warn = Color(0xFFF2C94C);
  static const Color error = Color(0xFFF05252);

  // ─── Typography families — Inter everywhere (periwinkle design) ────────────
  /// Inter — UI, body, buttons, labels.
  static const String fontPrimary = 'Inter';

  /// Inter — headings/display (the design is type-driven on a single family).
  static const String fontDisplay = 'Inter';

  /// Inter — metrics/labels too (the "De ce ai nevoie?" design is Inter-only).
  static const String fontMono = 'Inter';

  // ─── Radii (periwinkle design: sm8 · md12 · lg18-26 · pill) ────────────────
  static const double rSm = 8; // small chips / inputs / badges
  static const double rMd = 12; // icon tiles, mid rows
  static const double rLg = 20; // default card radius
  static const double rXl = 26; // large feature cards / sheets
  static const double rPill = 999;

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

  /// Screen edge padding L/R per design system §3
  static const double screenPaddingH = 18;

  /// Default card-to-card gap per design system §3
  static const double cardGap = 12;

  // ─── Shadows — soft, periwinkle-tinted (--sh / --sh2 / --sh-float) ─────────
  // Cards separate by shadow + spacing (the design forbids heavy borders). On
  // dark the surface sits lighter than the page, so cards still read clearly.
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x122D2D50), offset: Offset(0, 6), blurRadius: 20),
  ];

  static const List<BoxShadow> shadowHero = [
    BoxShadow(color: Color(0x182D2D50), offset: Offset(0, 12), blurRadius: 34),
  ];

  static const List<BoxShadow> shadowFloat = [
    BoxShadow(color: Color(0x142D2D50), offset: Offset(0, 12), blurRadius: 36),
  ];

  // ─── Gradients — periwinkle accent (135° ac2 → ac) ─────────────────────────
  static const LinearGradient gradBrand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand2, brand],
  );

  static const LinearGradient gradBtn = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand2, brand],
  );

  /// Accent feature card wash (135° ac2 → ac), e.g. active-challenge card.
  static const LinearGradient gradHero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand2, brand],
  );

  /// Periwinkle glow for primary CTAs / FAB — rgba(124,132,236,0.38).
  static const List<BoxShadow> glowBrand = [
    BoxShadow(color: Color(0x617C84EC), blurRadius: 26, offset: Offset(0, 10)),
  ];
}

/// Shared motion tokens. Keep these subtle: Zvelt is a product UI used while
/// training, so feedback should feel crisp without slowing the user down.
class ZMotion {
  ZMotion._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve settle = Curves.easeOutQuart;
}

/// V2 text-style utility roles. Mirror the `.z-display .z-clean .z-stat .z-num
/// .z-eyebrow` CSS classes. Now runtime getters (they color from the theme-aware
/// neutrals) so they can't sit inside `const` widgets.
class ZType {
  ZType._();

  /// Display heading — Inter 600, tight tracking. For large hero text.
  static TextStyle get display => TextStyle(
        fontFamily: ZveltTokens.fontDisplay,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.022 * 16,
        height: 1.2,
        color: ZveltTokens.text,
      );

  /// Clean sans heading — Inter 600. Card titles, section headers.
  static TextStyle get clean => TextStyle(
        fontFamily: ZveltTokens.fontDisplay,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.02 * 16,
        height: 1.2,
        color: ZveltTokens.text,
      );

  /// KPI stat number — Inter 600 tabular. Welcome total, big counts.
  static TextStyle get stat => const TextStyle(
        fontFamily: ZveltTokens.fontDisplay,
        fontWeight: FontWeight.w600,
        fontFeatures: [FontFeature.tabularFigures()],
        letterSpacing: -0.02 * 16,
        height: 1,
      ).copyWith(color: ZveltTokens.text);

  /// Metric readout — IBM Plex Mono 500 tabular. BPM, pace, distance, weights.
  static TextStyle get num_ => const TextStyle(
        fontFamily: ZveltTokens.fontMono,
        fontWeight: FontWeight.w500,
        fontFeatures: [FontFeature.tabularFigures()],
        letterSpacing: 0,
        height: 1,
      ).copyWith(color: ZveltTokens.text);

  /// Eyebrow / technical label — IBM Plex Mono 500, 10px, uppercase.
  static TextStyle get eyebrow => TextStyle(
        fontFamily: ZveltTokens.fontMono,
        fontWeight: FontWeight.w500,
        fontSize: 10,
        letterSpacing: 0.08 * 10,
        height: 1.2,
        color: ZveltTokens.text3,
      );

  // ── Inter scale (matches design-system.md §1) ───────────────────────────────
  static TextStyle get displayXL => TextStyle(
        fontFamily: ZveltTokens.fontDisplay,
        fontWeight: FontWeight.w600,
        fontSize: 52,
        height: 1.2,
        color: ZveltTokens.text,
      );
  static TextStyle get displayL => TextStyle(
        fontFamily: ZveltTokens.fontDisplay,
        fontWeight: FontWeight.w600,
        fontSize: 42,
        height: 1.2,
        color: ZveltTokens.text,
      );
  static TextStyle get displayM => TextStyle(
        fontFamily: ZveltTokens.fontDisplay,
        fontWeight: FontWeight.w600,
        fontSize: 34,
        height: 1.2,
        color: ZveltTokens.text,
      );
  static TextStyle get h1 => TextStyle(
        fontFamily: ZveltTokens.fontDisplay,
        fontWeight: FontWeight.w600,
        fontSize: 28,
        height: 1.2,
        color: ZveltTokens.text,
      );
  static TextStyle get h2 => TextStyle(
        fontFamily: ZveltTokens.fontDisplay,
        fontWeight: FontWeight.w600,
        fontSize: 24,
        height: 1.2,
        color: ZveltTokens.text,
      );
  static TextStyle get h3 => TextStyle(
        fontFamily: ZveltTokens.fontDisplay,
        fontWeight: FontWeight.w600,
        fontSize: 20,
        height: 1.4,
        color: ZveltTokens.text,
      );
  static TextStyle get h4 => TextStyle(
        fontFamily: ZveltTokens.fontDisplay,
        fontWeight: FontWeight.w600,
        fontSize: 18,
        height: 1.4,
        color: ZveltTokens.text,
      );
  static TextStyle get bodyL => TextStyle(
        fontFamily: ZveltTokens.fontPrimary,
        fontWeight: FontWeight.w400,
        fontSize: 17,
        height: 1.6,
        color: ZveltTokens.text,
      );
  static TextStyle get bodyM => TextStyle(
        fontFamily: ZveltTokens.fontPrimary,
        fontWeight: FontWeight.w400,
        fontSize: 15,
        height: 1.6,
        color: ZveltTokens.text,
      );
  static TextStyle get bodyS => TextStyle(
        fontFamily: ZveltTokens.fontPrimary,
        fontWeight: FontWeight.w400,
        fontSize: 13,
        height: 1.6,
        color: ZveltTokens.text2,
      );
  static TextStyle get monoS => TextStyle(
        fontFamily: ZveltTokens.fontMono,
        fontWeight: FontWeight.w400,
        fontSize: 12,
        height: 1.6,
        color: ZveltTokens.text2,
      );
  static TextStyle get monoXS => TextStyle(
        fontFamily: ZveltTokens.fontMono,
        fontWeight: FontWeight.w400,
        fontSize: 11,
        height: 1.6,
        color: ZveltTokens.text3,
      );
}
