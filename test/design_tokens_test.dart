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
    test('values', () {
      expect(RadiusTokens.sm, 4);
      expect(RadiusTokens.md, 8);
      expect(RadiusTokens.lg, 12);
      expect(RadiusTokens.xl, 16);
      expect(RadiusTokens.full, 9999);
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
      expect(TypeScale.body().fontSize, 16);
      expect(TypeScale.bodySmall().fontSize, 14);
      expect(TypeScale.caption().fontSize, 12);
      expect(TypeScale.code().fontSize, 13);
      expect(TypeScale.code().fontWeight, FontWeight.w500);
      expect(TypeScale.code().fontFamily, 'monospace');
    });
  });
}
