// Guards a11y contrast on the text tokens, calibrated to the periwinkle
// "De ce ai nevoie?" design contract:
//   • `text`  carries primary copy → must clear WCAG AA normal-text (4.5:1).
//   • `text2` carries secondary copy → must clear the large/UI bar (3:1).
// `text3`/`text4` are intentionally airy tertiary/decorative greys (the design's
// premium look) and are not used for essential small copy, so they aren't gated.
// A future token tweak that darkens the page or lightens text/text2 below these
// bars fails loudly here instead of silently shipping unreadable copy.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvelt_app/theme/zvelt_tokens.dart';

/// sRGB 8-bit channel → linearised component, per WCAG relative-luminance def.
double _linearize(int channel8bit) {
  final c = channel8bit / 255.0;
  return c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG relative luminance of a color (0.2126 R + 0.7152 G + 0.0722 B linear).
double _luminance(Color color) {
  final argb = color.toARGB32();
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 0.2126 * _linearize(r) +
      0.7152 * _linearize(g) +
      0.0722 * _linearize(b);
}

/// WCAG contrast ratio: (L_lighter + 0.05) / (L_darker + 0.05).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

int _channelSpread(Color color) {
  final argb = color.toARGB32();
  final channels = <int>[
    (argb >> 16) & 0xFF,
    (argb >> 8) & 0xFF,
    argb & 0xFF,
  ];
  return channels.reduce(math.max) - channels.reduce(math.min);
}

void main() {
  group('ZveltTokens muted-text contrast (WCAG AA)', () {
    // Both themes are first-class now (light + premium dark), so check each.
    tearDown(() => ZveltTokens.isDark = false);

    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      test(
          '[$mode] text meets 4.5:1 against both bg and surface (normal-text AA)',
          () {
        ZveltTokens.isDark = dark;
        expect(
          _contrast(ZveltTokens.text, ZveltTokens.bg),
          greaterThanOrEqualTo(4.5),
          reason: '[$mode] primary text on the page background',
        );
        expect(
          _contrast(ZveltTokens.text, ZveltTokens.surface),
          greaterThanOrEqualTo(4.5),
          reason: '[$mode] primary text on card surfaces',
        );
      });

      test('[$mode] text2 meets 3:1 against both bg and surface (large/UI AA)',
          () {
        ZveltTokens.isDark = dark;
        expect(
          _contrast(ZveltTokens.text2, ZveltTokens.bg),
          greaterThanOrEqualTo(3.0),
          reason: '[$mode] secondary text on the page background',
        );
        expect(
          _contrast(ZveltTokens.text2, ZveltTokens.surface),
          greaterThanOrEqualTo(3.0),
          reason: '[$mode] secondary text on card surfaces',
        );
      });
    }

    test('contrast helper matches a hand-computed reference (black on white)',
        () {
      // Pure black on pure white is exactly 21:1 — sanity-checks the formula so
      // a bug in _luminance/_contrast can't make the guards pass vacuously.
      expect(
        _contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 0.01),
      );
    });
  });

  group('ZveltTokens matte-card surfaces', () {
    tearDown(() => ZveltTokens.isDark = false);

    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      test('[$mode] card gradients stay neutral and nearly opaque', () {
        ZveltTokens.isDark = dark;
        final colors = <Color>[
          ...ZveltTokens.surfaceGrad.colors,
          ...ZveltTokens.surface2Grad.colors,
        ];

        for (final color in colors) {
          expect(
            _channelSpread(color),
            lessThanOrEqualTo(4),
            reason: '[$mode] card tint must not introduce colour bands',
          );
          expect(
            (color.toARGB32() >> 24) & 0xFF,
            greaterThanOrEqualTo(0xED),
            reason: '[$mode] card material must hide GPU/background banding',
          );
        }
      });
    }
  });
}
