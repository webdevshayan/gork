import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gork/constants/design_tokens.dart';

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('spacing tokens follow the 4-point grid', () {
    test('values', () {
      expect(Spacing.xs, 4);
      expect(Spacing.sm, 8);
      expect(Spacing.md, 16);
      expect(Spacing.lg, 24);
      expect(Spacing.xl, 32);
      expect(Spacing.xxl, 48);
    });
  });

  group('radius tokens', () {
    test('values — never edgy (Movement 50)', () {
      expect(RadiusTokens.sm, 10);
      expect(RadiusTokens.md, 14);
      expect(RadiusTokens.lg, 20);
      expect(RadiusTokens.xl, 24);
      expect(RadiusTokens.full, 9999);
    });
  });

  group('the palette is black & white (Movement 50)', () {
    test('primary is ink, never blue', () {
      expect(Palette.light.primary, const Color(0xFF131313));
      expect(Palette.dark.primary, const Color(0xFFF2F2F2));
      expect(Palette.light.primary, isNot(const Color(0xFF2563EB)));
      expect(Palette.dark.primary, isNot(const Color(0xFF6EA8FE)));
    });
  });

  group('WCAG contrast for body text is at least 4.5:1', () {
    test('light palette', () {
      expect(contrast(Palette.light.textPrimary, Palette.light.background),
          greaterThanOrEqualTo(4.5));
      expect(contrast(Palette.light.textSecondary, Palette.light.surface),
          greaterThanOrEqualTo(4.5));
      expect(contrast(Palette.light.textPrimary, Palette.light.surface),
          greaterThanOrEqualTo(4.5));
    });

    test('dark palette', () {
      expect(contrast(Palette.dark.textPrimary, Palette.dark.background),
          greaterThanOrEqualTo(4.5));
      expect(contrast(Palette.dark.textSecondary, Palette.dark.surface),
          greaterThanOrEqualTo(4.5));
      expect(contrast(Palette.dark.textPrimary, Palette.dark.surfaceElevated),
          greaterThanOrEqualTo(4.5));
    });

    test('button label contrast', () {
      expect(contrast(Palette.light.onPrimary, Palette.light.primary),
          greaterThanOrEqualTo(4.5));
      expect(contrast(Palette.dark.onPrimary, Palette.dark.primary),
          greaterThanOrEqualTo(4.5));
    });

    // Movement 68 — the EXHAUSTIVE gate: every text tier against every
    // surface it can sit on, in both palettes. The old spot checks let
    // textTertiary sit right at the AA edge on the elevated surface (the
    // dense gray walls in the screenshots); now nothing can regress.
    test('exhaustive matrix — all tiers × all surfaces × both palettes', () {
      final palettes = {'light': Palette.light, 'dark': Palette.dark};
      for (final p in palettes.entries) {
        final surfaces = {
          'background': p.value.background,
          'surface': p.value.surface,
          'surfaceElevated': p.value.surfaceElevated,
        };
        final tiers = {
          'textPrimary': p.value.textPrimary,
          'textSecondary': p.value.textSecondary,
          'textTertiary': p.value.textTertiary,
        };
        for (final tier in tiers.entries) {
          for (final surface in surfaces.entries) {
            expect(
                contrast(tier.value, surface.value),
                greaterThanOrEqualTo(4.5),
                reason: '${p.key} ${tier.key} on ${surface.key} is '
                    '${contrast(tier.value, surface.value).toStringAsFixed(2)}'
                    ':1 — below WCAG AA');
          }
        }
      }
    });
  });

  group('elevation levels', () {
    test('values', () {
      expect(Elevation.level0, 0.0);
      expect(Elevation.level1, 0.05);
      expect(Elevation.level2, 0.1);
      expect(Elevation.level3, 0.15);
    });
  });

  group('typography scale', () {
    test('sizes and weights', () {
      expect(TypeScale.display().fontSize, 40);
      expect(TypeScale.display().fontWeight, FontWeight.w700);
      expect(TypeScale.title().fontSize, 28);
      expect(TypeScale.heading().fontSize, 22);
      expect(TypeScale.heading().fontWeight, FontWeight.w600);
      // Movement 68 — the scan pass: body 17, small 15, caption 13,
      // code 14, and NOTHING in the scale below 13.
      expect(TypeScale.body().fontSize, 17);
      expect(TypeScale.bodySmall().fontSize, 15);
      expect(TypeScale.caption().fontSize, 13);
      expect(TypeScale.code().fontSize, 14);
      expect(TypeScale.code().fontWeight, FontWeight.w500);
      expect(TypeScale.code().fontFamily, 'monospace');
    });

    test('no text style below 13 — the readability floor', () {
      final sizes = [
        TypeScale.display().fontSize!,
        TypeScale.title().fontSize!,
        TypeScale.heading().fontSize!,
        TypeScale.body().fontSize!,
        TypeScale.bodySmall().fontSize!,
        TypeScale.caption().fontSize!,
        TypeScale.code().fontSize!,
      ];
      for (final s in sizes) {
        expect(s, greaterThanOrEqualTo(13),
            reason: 'text under 13 is unreadable at arm\u2019s length');
      }
    });
  });
}
