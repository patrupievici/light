import 'package:flutter/material.dart';

/// ZVELT design tokens — **light + dark** (brief: "bun in light si dark mode").
///
/// Neutrals (backgrounds, surfaces, text, borders, accent-soft) resolve at
/// runtime against [isDark]; the brand orange + semantic colors + shadows stay
/// constant across modes (the brief keeps orange as the single signal in both).
/// Because the neutrals + [ZType] styles are now runtime getters, they are NO
/// longer usable inside `const` expressions — widgets that color/style from them
/// must drop `const`.
///
/// Flip [isDark] from the app root (see main.dart) on theme-mode / platform
/// brightness change; the surrounding ValueListenableBuilder rebuilds the tree.
class ZveltTokens {
  ZveltTokens._();

  /// Global brightness flag — owned by the app root, read by every neutral.
  static bool isDark = false;

  /// Pick the light or dark value for the active brightness.
  static Color _d(Color light, Color dark) => isDark ? dark : light;

  // ─── Neutral backgrounds ───────────────────────────────────────────────────
  // Dark = the "ZVELT Premium" palette (deep black surfaces, layered s1–s4).
  /// Page background
  static Color get bg => _d(const Color(0xFFF6F7F5), const Color(0xFF050505));
  /// Inset block bg / secondary card
  static Color get bg2 => _d(const Color(0xFFEEF1ED), const Color(0xFF0D0D0F));
  /// Card surface
  static Color get surface => _d(const Color(0xFFFFFFFF), const Color(0xFF18181B));
  /// Subtle inset inside cards
  static Color get surface2 => _d(const Color(0xFFFCFCFA), const Color(0xFF222226));
  /// Track behind progress / muted thumb
  static Color get surface3 => _d(const Color(0xFFE6E8E4), const Color(0xFF2A2A2E));
  /// Peach hero surface — accent-soft (deep brand wash in dark)
  static Color get surfaceTinted => _d(const Color(0xFFFFE4D2), const Color(0xFF2A1408));

  // ─── Text ───────────────────────────────────────────────────────────────────
  static Color get text => _d(const Color(0xFF111111), const Color(0xFFFFFFFF));
  static Color get text2 => _d(const Color(0xFF5F6360), const Color(0xFFC0C0C2));
  static Color get text3 => _d(const Color(0xFF6E726C), const Color(0xFF97979F));
  static Color get text4 => _d(const Color(0xFF8A8E88), const Color(0xFF6E6E78));

  // ─── Borders — used very sparingly ─────────────────────────────────────────
  static Color get border => _d(const Color(0xFFECEEEA), const Color(0x14FFFFFF));
  static Color get borderStrong => _d(const Color(0xFFDADCD7), const Color(0x24FFFFFF));
  /// Hairline divider
  static Color get hairline => _d(const Color(0x0D111111), const Color(0x0FFFFFFF));

  // ─── Accent (orange = signal only; constant across modes) ──────────────────
  /// accent-primary
  static const Color brand = Color(0xFFFF7A2F);
  static const Color brand2 = Color(0xFFFF8A45);
  /// light variant — halo, XP, gradient top
  static const Color brand3 = Color(0xFFFFB088);
  /// accent-hover — press / gradient anchor
  static const Color brandDeep = Color(0xFFE86B24);
  /// accent-soft — chip bg, hero halo (warm tint, theme-aware)
  static Color get brandTint => _d(const Color(0xFFFFE4D2), const Color(0xFF3A2A1E));
  /// accent-glow — rgba(255,122,47,0.18)
  static const Color brandGlow = Color(0x2EFF7A2F);
  static const Color onBrand = Color(0xFFFFFFFF);

  // ─── Biometric / category palette ──────────────────────────────────────────
  static const Color recovery = Color(0xFF7BC6FF);
  static const Color recovery2 = Color(0xFFDCEFFF);
  static const Color sleep = Color(0xFFA58BFF);
  static const Color sleep2 = Color(0xFFE6DEFF);
  static const Color stress = Color(0xFFFFB86B);
  static const Color stress2 = Color(0xFFFFE9D1);
  static const Color strain = Color(0xFFFFB86B); // alias to stress
  static const Color strain2 = Color(0xFFFFE9D1);
  static const Color strength = Color(0xFF2EC27E);
  static const Color strength2 = Color(0xFFD2F2E2);
  static const Color cardio = Color(0xFFFF6B6B);
  static const Color cardio2 = Color(0xFFFFDADA);

  // ─── Semantic ───────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF2EC27E);
  static const Color successSoft = Color(0xFFE2F6EC);
  static const Color info = Color(0xFF7BC6FF);
  static const Color warn = Color(0xFFFFB86B);
  static const Color error = Color(0xFFE5484D);

  // ─── Typography families ────────────────────────────────────────────────────
  /// Inter — UI, body, buttons, labels. (Kept for body: visually near-identical
  /// to the prototype's DM Sans but without the wider metrics that overflowed
  /// tight layouts at large text scales.)
  static const String fontPrimary = 'Inter';
  /// Barlow Condensed — display headings + big metrics (the condensed, sporty
  /// face that gives ZVELT its premium character). It's narrower than Inter, so
  /// it carries the design signature with no overflow risk.
  static const String fontDisplay = 'BarlowCondensed';
  /// IBM Plex Mono — BPM · pace · calories · distance · technical readouts
  static const String fontMono = 'IBMPlexMono';

  // ─── Radii ─────────────────────────────────────────────────────────────────
  static const double rSm = 10; // tiles, inputs, small buttons
  static const double rMd = 16; // mid chips & rows
  static const double rLg = 24; // ALL cards
  static const double rXl = 32; // modal sheets
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

  // ─── Shadows (subtle; constant across modes for v1) ────────────────────────
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x05111111), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x08111111), offset: Offset(0, 4), blurRadius: 12),
  ];

  static const List<BoxShadow> shadowHero = [
    BoxShadow(color: Color(0x0A111111), offset: Offset(0, 8), blurRadius: 24),
    BoxShadow(color: Color(0x05111111), offset: Offset(0, 2), blurRadius: 6),
  ];

  static const List<BoxShadow> shadowFloat = [
    BoxShadow(color: Color(0x14111111), offset: Offset(0, 12), blurRadius: 36),
  ];

  // ─── Gradients (brand signal only — constant across modes) ─────────────────
  static const LinearGradient gradBrand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand3, brand],
  );

  static const LinearGradient gradBtn = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [brand, brandDeep],
  );

  /// Premium dark hero wash (ZVELT prototype: 175° red→orange→near-black).
  static const LinearGradient gradHero = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.30, 0.55, 1.0],
    colors: [Color(0xFFC93010), Color(0xFFE8480E), Color(0xFFFF5A1F), Color(0xFF1A0A04)],
  );

  /// Orange glow for primary actions / FAB on the dark theme.
  static const List<BoxShadow> glowBrand = [
    BoxShadow(color: Color(0x66FF5A1F), blurRadius: 28, spreadRadius: -2, offset: Offset(0, 6)),
  ];
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
