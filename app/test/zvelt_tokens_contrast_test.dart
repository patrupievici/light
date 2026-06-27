// Guards the a11y contrast fix on the muted text tokens.
//
// `ZveltTokens.text3` carries real caption/subtitle copy, so it must clear the
// WCAG 2.1 AA bar for normal text (4.5:1). `text4` is reserved for large /
// non-essential text and must clear the large-text / UI bar (3:1). These
// margins are TIGHT (text3 ≈ 4.56:1 on the page bg), so a future token tweak
// that darkens the page or lightens the grey would silently re-break AA — this
// test makes that fail loudly instead.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/theme/zvelt_tokens.dart';

/// sRGB 8-bit channel → linearised component, per WCAG relative-luminance def.
double _linearize(int channel8bit) {
  final c = channel8bit / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG relative luminance of a color (0.2126 R + 0.7152 G + 0.0722 B linear).
double _luminance(Color color) {
  final argb = color.toARGB32();
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 0.2126 * _linearize(r) + 0.7152 * _linearize(g) + 0.0722 * _linearize(b);
}

/// WCAG contrast ratio: (L_lighter + 0.05) / (L_darker + 0.05).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('ZveltTokens muted-text contrast (WCAG AA)', () {
    // Both themes are first-class now (light + premium dark), so check each.
    tearDown(() => ZveltTokens.isDark = false);

    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      test('[$mode] text3 meets 4.5:1 against both bg and surface (normal-text AA)', () {
        ZveltTokens.isDark = dark;
        expect(
          _contrast(ZveltTokens.text3, ZveltTokens.bg),
          greaterThanOrEqualTo(4.5),
          reason: '[$mode] text3 carries caption copy on the page background',
        );
        expect(
          _contrast(ZveltTokens.text3, ZveltTokens.surface),
          greaterThanOrEqualTo(4.5),
          reason: '[$mode] text3 carries caption copy on card surfaces',
        );
      });

      test('[$mode] text4 meets 3:1 against both bg and surface (large/UI AA)', () {
        ZveltTokens.isDark = dark;
        expect(
          _contrast(ZveltTokens.text4, ZveltTokens.bg),
          greaterThanOrEqualTo(3.0),
          reason: '[$mode] text4 is the most-muted text token on the page background',
        );
        expect(
          _contrast(ZveltTokens.text4, ZveltTokens.surface),
          greaterThanOrEqualTo(3.0),
          reason: '[$mode] text4 is the most-muted text token on card surfaces',
        );
      });
    }

    test('contrast helper matches a hand-computed reference (black on white)', () {
      // Pure black on pure white is exactly 21:1 — sanity-checks the formula so
      // a bug in _luminance/_contrast can't make the guards pass vacuously.
      expect(
        _contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 0.01),
      );
    });
  });
}
