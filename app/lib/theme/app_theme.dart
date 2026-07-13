import 'package:flutter/material.dart';

import 'zvelt_tokens.dart';

/// ZVELT theme — **V2 light** (post 2026-05-29 migration).
///
/// Legacy code throughout the app references `AppTheme.bgPrimary`,
/// `AppTheme.accentAmber`, `AppTheme.textPrimary`, etc. Rather than
/// rewriting every widget individually, this class now re-exports the V2
/// tokens from [ZveltTokens] under the legacy names. Result: the whole
/// app instantly switches to light mode, Inter typography, single orange
/// signal — without touching widget files.
///
/// Per-widget refactors continue (replacing `AppTheme.foo` with
/// `ZveltTokens.foo` + `ZType.bar` directly) for crisper, on-spec layouts.
/// In the meantime the global look is V2.
class AppTheme {
  AppTheme._();

  // ── Fonts ──────────────────────────────────────────────────────────────────
  /// Inter — primary UI font (was already Inter pre-migration, kept).
  static const String fontSans = ZveltTokens.fontPrimary;
  /// Inter — was SpaceGrotesk; V2 collapses both into Inter for consistency.
  static const String fontDisplay = ZveltTokens.fontPrimary;
  /// IBM Plex Mono — was SpaceMono; V2 uses Plex Mono for metrics / eyebrows.
  static const String fontMono = ZveltTokens.fontMono;

  // ── Backgrounds (V2) ───────────────────────────────────────────────────────
  /// Was #0B0D10 (dark). Now V2 page bg (cream-white).
  static Color get bgPrimary => ZveltTokens.bg;
  /// Was #121621 (dark elevated). Now V2 card surface (white).
  static Color get bgElevated => ZveltTokens.surface;
  /// Was #1A1E28. Now V2 subtle inset.
  static Color get bgSurface2 => ZveltTokens.surface2;
  static Color get surfaceContainerHigh => ZveltTokens.surface2;
  static Color get surfaceVariant => ZveltTokens.surface3;

  // ── Borders ────────────────────────────────────────────────────────────────
  /// Was #232B3A (dark gray). Now V2 hairline-ish light border.
  static Color get border => ZveltTokens.border;

  // ── Text (V2) ──────────────────────────────────────────────────────────────
  /// Was white. Now V2 near-black (#111).
  static Color get textPrimary => ZveltTokens.text;
  /// Was light gray. Now V2 mid-gray (#5F6360).
  static Color get textSecondary => ZveltTokens.text2;
  /// Was #6B7380. Now V2 disabled/divider.
  static Color get onSurfaceVariant => ZveltTokens.text4;

  // ── Accents — orange brand (V2: single signal) ────────────────────────────
  /// Was #FF5A1F. Now V2 brand #FF7A2F.
  static const Color primary = ZveltTokens.brand;
  static Color get primaryContainer => ZveltTokens.brandTint;
  static const Color onPrimary = ZveltTokens.onBrand;
  static const Color accentAmber = ZveltTokens.brand;
  static const Color accentAmberDim = ZveltTokens.brand3;
  static const Color accentAmberGlow = ZveltTokens.brandGlow;
  /// V2 has no separate blue accent — collapses to brand signal.
  /// Kept as alias so legacy widgets compile; visually they now read as brand.
  static const Color accentBlue = ZveltTokens.brand;

  // ── Semantic ───────────────────────────────────────────────────────────────
  static const Color success = ZveltTokens.success;
  static const Color warning = ZveltTokens.warn;
  static const Color error = ZveltTokens.error;

  // ── Nav / chrome ───────────────────────────────────────────────────────────
  /// V2: nav stays white with subtle separation (was opaque dark).
  static Color get navBarBg => ZveltTokens.surface;

  // ── Radii ──────────────────────────────────────────────────────────────────
  /// V2 default card radius (was 12).
  static const double radiusCard = ZveltTokens.rLg;
  static const double radiusModal = ZveltTokens.rXl;
  static const double radiusChip = ZveltTokens.rPill;
  static const double grid = 8;

  // ── Razvan-naming aliases — keep his widgets compiling after merge ───────
  // His pre-merge app_theme used short-form names (bg0/s1/t1/brand/warn/etc.)
  // for the dark+light dual palette. We keep MY V2 light theme as the source
  // of truth and map his names to the equivalent ZveltTokens values so all
  // his widgets render in V2 colors without per-file edits.
  static Color get bg0 => ZveltTokens.bg;
  static Color get bg1 => ZveltTokens.bg;
  static Color get bg2 => ZveltTokens.bg2;
  static Color get s1 => ZveltTokens.surface;
  static Color get s2 => ZveltTokens.surface2;
  static Color get s3 => ZveltTokens.surface3;
  static Color get s4 => ZveltTokens.surface3;
  static Color get bgSurface3 => ZveltTokens.surface3;
  static const Color brand  = ZveltTokens.brand;
  static const Color brand2 = ZveltTokens.brand2;
  static const Color brand3 = ZveltTokens.brand3;
  static const Color deep   = ZveltTokens.brandDeep;
  static const Color glow   = ZveltTokens.brandGlow;
  static Color get t1 => ZveltTokens.text;
  static Color get t2 => ZveltTokens.text2;
  static Color get t3 => ZveltTokens.text3;
  static Color get t4 => ZveltTokens.text4;
  static const Color info   = ZveltTokens.info;
  static const Color warn   = ZveltTokens.warn;

  /// Theme alias for Razvan's main.dart selector — V2 is light-only,
  /// both pointers resolve to the same theme data.
  static ThemeData get lightThemeData => themeData;
  static ThemeData get darkThemeData => themeData;

  /// Brand gradient — used by Razvan's hero buttons and stat tiles.
  /// V2 keeps gradients minimal; brand-to-brand-deep at 135deg matches
  /// the AI suggestion icon halo in design-system.md.
  static const LinearGradient gradBrand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ZveltTokens.brand3, ZveltTokens.brand],
  );

  /// Button gradient — slightly more saturated than gradBrand for CTAs.
  static const LinearGradient gradBtn = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [ZveltTokens.brand, ZveltTokens.brandDeep],
  );

  /// Razvan used `AppTheme.barlowCondensed(...)` for headline text. V2
  /// design-system.md collapses all UI typography to Inter, so this
  /// returns an Inter TextStyle instead. Visual difference: tighter
  /// tracking but loses the condensed proportions — acceptable since
  /// V2 has its own display scale (ZType.displayM/L/XL).
  static TextStyle barlowCondensed({
    double? fontSize,
    FontWeight? fontWeight,
    // Alias for fontWeight — Razvan's call sites use the shorter `weight:`.
    FontWeight? weight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: ZveltTokens.fontPrimary,
      fontSize: fontSize,
      fontWeight: fontWeight ?? weight ?? FontWeight.w600,
      color: color ?? textPrimary,
      letterSpacing: letterSpacing ?? -0.01 * (fontSize ?? 16),
      height: height,
      fontStyle: fontStyle,
    );
  }

  static TextTheme _buildTextTheme() {
    // Manrope everywhere (handoff typeface) — bundled variable font.
    final base = ThemeData(
      brightness: ZveltTokens.isDark ? Brightness.dark : Brightness.light,
    ).textTheme.apply(
          fontFamily: ZveltTokens.fontPrimary,
          bodyColor: textPrimary,
          displayColor: textPrimary,
        );
    return base.copyWith(
      displayLarge: ZType.displayL.copyWith(fontSize: 48),
      headlineMedium: ZType.displayM,
      headlineSmall: ZType.h2,
      titleLarge: ZType.h3,
      titleMedium: ZType.h4,
      titleSmall: ZType.eyebrow.copyWith(fontSize: 11, color: textSecondary, letterSpacing: 1.2),
      labelLarge: ZType.eyebrow.copyWith(fontSize: 11, color: primary, letterSpacing: 1.1),
      labelSmall: ZType.eyebrow.copyWith(fontSize: 11, color: textSecondary, letterSpacing: 1.2),
      bodyLarge: ZType.bodyL.copyWith(color: textPrimary),
      bodyMedium: ZType.bodyM.copyWith(color: textPrimary),
      bodySmall: ZType.bodyS.copyWith(color: textSecondary),
    );
  }

  static ThemeData get themeData {
    final textTheme = _buildTextTheme();
    final dark = ZveltTokens.isDark;
    return ThemeData(
      useMaterial3: true,
      fontFamily: ZveltTokens.fontPrimary,
      // Brightness + neutrals resolve live from ZveltTokens.isDark (set in
      // main.dart BEFORE this theme is evaluated). lightThemeData and
      // darkThemeData both return this getter; MaterialApp picks whichever
      // matches the active brightness — both already reflect the active mode.
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: bgPrimary,
      colorScheme: ColorScheme(
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: ZveltTokens.brandDeep,
        secondary: primary,
        onSecondary: onPrimary,
        tertiary: primary,
        surface: bgPrimary,
        surfaceContainerHighest: surfaceContainerHigh,
        error: error,
        onError: const Color(0xFFFFFFFF),
        onSurface: textPrimary,
        onSurfaceVariant: onSurfaceVariant,
        outline: border,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgPrimary.withValues(alpha: 0.94),
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        titleTextStyle: ZType.h4.copyWith(color: textPrimary),
        iconTheme: IconThemeData(color: ZveltTokens.text2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          ),
          textStyle: const TextStyle(
            fontFamily: fontSans,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: bgElevated,
          foregroundColor: primary,
          minimumSize: const Size(0, 48),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZveltTokens.rPill),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(
            fontFamily: fontSans,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rMd),
          borderSide: const BorderSide(color: error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: onSurfaceVariant, fontFamily: fontSans, fontSize: 14),
        labelStyle: TextStyle(color: textSecondary, fontFamily: fontSans, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: primary, fontFamily: fontSans, fontSize: 12),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: navBarBg,
        selectedItemColor: primary,
        unselectedItemColor: ZveltTokens.text3,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontFamily: fontMono, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.0),
        unselectedLabelStyle: const TextStyle(fontFamily: fontMono, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.0),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ZveltTokens.text,
        contentTextStyle: TextStyle(color: ZveltTokens.surface, fontFamily: fontSans, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ZveltTokens.rMd)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rXl),
        ),
        titleTextStyle: ZType.h4.copyWith(color: textPrimary),
        contentTextStyle: ZType.bodyM.copyWith(color: textSecondary, height: 1.5),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bgElevated,
        modalBackgroundColor: bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(ZveltTokens.rXl)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      textTheme: textTheme,
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: ZveltTokens.surface3,
        thumbColor: primary,
        overlayColor: ZveltTokens.brandGlow,
        trackHeight: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: ZveltTokens.surface3,
      ),
      cardTheme: CardThemeData(
        color: bgElevated,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rLg),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ZveltTokens.surface2,
        labelStyle: TextStyle(color: textPrimary, fontFamily: fontSans, fontSize: 13),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZveltTokens.rPill),
        ),
        selectedColor: ZveltTokens.brandTint,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minLeadingWidth: 20,
        horizontalTitleGap: 12,
        minVerticalPadding: 6,
        iconColor: ZveltTokens.text2,
        textColor: ZveltTokens.text,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return onPrimary;
          return ZveltTokens.text3;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return ZveltTokens.surface3;
        }),
      ),
    );
  }
}
