import 'package:flutter/material.dart';

/// Spacing tokens — 4-point grid only.
/// Screen horizontal padding is md. Card padding is md. Gap between cards is md.
class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Corner radius tokens. Default for buttons and inputs is md.
/// Concentric rule: inner radius = outer radius - padding.
class RadiusTokens {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double full = 9999;
}

/// Elevation levels (shadow opacity). In dark mode we never rely on shadows —
/// we use a lighter surfaceElevated instead.
class Elevation {
  static const double level0 = 0.0;
  static const double level1 = 0.05;
  static const double level2 = 0.10;
  static const double level3 = 0.15;
}

/// Semantic palette. Every token has a light and a dark value.
/// Body text contrast is >= 4.5:1 against background/surface in both modes.
class Palette {
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary;
  final Color onPrimary;
  final Color success;
  final Color warning;
  final Color error;
  final Color border;

  const Palette({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.onPrimary,
    required this.success,
    required this.warning,
    required this.error,
    required this.border,
  });

  static const Palette light = Palette(
    background: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF111418),
    textSecondary: Color(0xFF4A5158),
    textTertiary: Color(0xFF6B7280),
    primary: Color(0xFF2563EB),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF15803D),
    warning: Color(0xFFB45309),
    error: Color(0xFFB91C1C),
    border: Color(0xFFD6DAE0),
  );

  static const Palette dark = Palette(
    background: Color(0xFF0F1115),
    surface: Color(0xFF171A21),
    surfaceElevated: Color(0xFF20242E),
    textPrimary: Color(0xFFF2F4F7),
    textSecondary: Color(0xFFA8B0BA),
    textTertiary: Color(0xFF8A93A0),
    primary: Color(0xFF6EA8FE),
    onPrimary: Color(0xFF0F1115),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    error: Color(0xFFF87171),
    border: Color(0xFF2A2F3A),
  );
}

/// Typography scale: size / weight. Monospace only for code.
/// Never more than three weights on one screen.
class TypeScale {
  static const double displaySize = 40;
  static const double titleSize = 28;
  static const double headingSize = 22;
  static const double bodySize = 16;
  static const double bodySmallSize = 14;
  static const double captionSize = 12;
  static const double codeSize = 13;

  static TextStyle display({Color? color}) => TextStyle(
      fontSize: displaySize, fontWeight: FontWeight.w700, height: 1.15, color: color);
  static TextStyle title({Color? color}) => TextStyle(
      fontSize: titleSize, fontWeight: FontWeight.w700, height: 1.2, color: color);
  static TextStyle heading({Color? color}) => TextStyle(
      fontSize: headingSize, fontWeight: FontWeight.w600, height: 1.25, color: color);
  static TextStyle body({Color? color}) => TextStyle(
      fontSize: bodySize, fontWeight: FontWeight.w400, height: 1.4, color: color);
  static TextStyle bodySmall({Color? color}) => TextStyle(
      fontSize: bodySmallSize, fontWeight: FontWeight.w400, height: 1.4, color: color);
  static TextStyle caption({Color? color}) => TextStyle(
      fontSize: captionSize, fontWeight: FontWeight.w400, height: 1.3, color: color);
  static TextStyle code({Color? color}) => TextStyle(
      fontSize: codeSize,
      fontWeight: FontWeight.w500,
      height: 1.3,
      fontFamily: 'monospace',
      color: color);
}

/// Resolve the semantic palette for the current brightness.
///
/// Movement 34: the whole app is dark glass — token screens resolve dark no
/// matter the platform brightness, so every page matches the shell.
Palette paletteOf(BuildContext context) => Palette.dark;

/// Colors for the glass shell: dark fills, subtle light borders, light text.
/// Named after their role, not their look — pages must stay consistent.
class GlassColors {
  GlassColors._();

  /// Dark translucent glass fill (sits over the ambient backdrop).
  static const Color fill = Color(0xB312141A);

  /// Same fill, more opaque for primary chrome (input bar, nav pills).
  static const Color fillStrong = Color(0xCC12141A);

  /// Subtle light border — hairline, never the old white 0.5 edge.
  static const Color border = Color(0x1FF2F4F7);

  /// Primary text on glass.
  static const Color text = Color(0xFFF2F4F7);

  /// Secondary text on glass.
  static const Color textDim = Color(0xFFA8B0BA);

  /// Tertiary/faint text on glass.
  static const Color textFaint = Color(0xFF8A93A0);

  /// Hairline divider on glass.
  static const Color divider = Color(0x2EF2F4F7);
}
