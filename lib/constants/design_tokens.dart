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

/// Corner radius tokens. Movement 50: corners are NEVER edgy — the smallest
/// radius in the app is 10. Buttons are capsules (use RadiusTokens.full).
/// Concentric rule: inner radius = outer radius - padding.
class RadiusTokens {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 24;
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
    // Movement 50: black & white only — the "primary" accent is ink in light
    // mode (black buttons, white labels), never blue or any other hue.
    primary: Color(0xFF111418),
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
    // Dark mode mirrors it: white buttons, black labels.
    primary: Color(0xFFF2F4F7),
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

/// The ambient palette published by the app shell on every resolution —
/// the phase + weather neutrals (Movement 57). `paletteOf` and the glass
/// colors read THIS, so cards, borders and fills follow the time of day
/// and the weather together with the app background.
final ValueNotifier<Palette> resolvedPalette =
    ValueNotifier<Palette>(Palette.dark);

/// Resolve the semantic palette for the current brightness.
///
/// Movement 34 locked this to dark glass. Movement 39 unlocks it: the app
/// shell resolves the theme mode (Light / Dark / System / Auto-by-clock)
/// and publishes the result to [GlassColors.brightness] — every consumer
/// of this function follows that resolution, so pages can never disagree
/// with the shell. Movement 57: the palette itself is now the ambient
/// phase+weather palette published by the shell, not the flat base.
Palette paletteOf(BuildContext context) => resolvedPalette.value;

/// Palette paletteOf reads — defined before [GlassColors] so its notifier
/// initializer can reference the coherence function below.
///
/// Coherence: whenever the resolved brightness flips WITHOUT the shell
/// around (tests, early frames), the palette follows to the flat base —
/// the app shell immediately refines it with the ambient phase+weather
/// palette right after publishing the brightness (Movement 57).
void _onBrightnessChanged() {
  resolvedPalette.value = GlassColors.brightness.value == Brightness.dark
      ? Palette.dark
      : Palette.light;
}

/// Colors for the glass shell. Named after their role, not their look —
/// pages must stay consistent. Both looks are full citizens: dark glass
/// (Movement 34) and light glass (Movement 39, light fills, light borders,
/// dark text). The app shell sets [brightness] whenever the theme mode
/// resolves; everything reads the getters, so call sites never change.
class GlassColors {
  GlassColors._();

  /// What the app resolved right now. Defaults to dark — the Movement 34
  /// glass — so tests and early frames see exactly the shipped look.
  /// The listener keeps [resolvedPalette] coherent whenever brightness
  /// flips without the shell around (tests, early frames); the shell
  /// refines it with the phase+weather palette right after.
  static final ValueNotifier<Brightness> brightness =
      ValueNotifier<Brightness>(Brightness.dark)
        ..addListener(_onBrightnessChanged);

  static bool get _dark => brightness.value == Brightness.dark;

  /// The current ambient palette (phase + weather neutrals).
  static Palette get _p => resolvedPalette.value;

  /// Translucent glass fill (sits over the ambient gradient). Derived from
  /// the phase surface so the glass warms and cools with the day.
  static Color get fill =>
      _p.surface.withValues(alpha: _dark ? 0.70 : 0.90);

  /// Same fill, more opaque for primary chrome (input bar, nav pills).
  static Color get fillStrong =>
      _p.surface.withValues(alpha: _dark ? 0.80 : 0.95);

  /// Hairline border — the ambient border color (themed per phase).
  /// Never the old white 0.5 edge.
  static Color get border =>
      _p.border.withValues(alpha: _dark ? 0.60 : 0.85);

  /// Primary text on glass.
  static Color get text => _p.textPrimary;

  /// Secondary text on glass.
  static Color get textDim => _p.textSecondary;

  /// Tertiary/faint text on glass.
  static Color get textFaint => _p.textTertiary;

  /// Hairline divider on glass.
  static Color get divider =>
      _p.border.withValues(alpha: _dark ? 0.50 : 0.70);

  /// The active nav-tab chip: ink (black) in light mode with a white label —
  /// Movement 54 — and near-white in dark mode with a black label. The active
  /// tab always inverts against the glass around it so it reads instantly.
  static Color get chip => _p.primary.withValues(alpha: 0.93);

  /// Label on the active chip — black on the near-white chip in dark mode,
  /// white on the ink chip in light mode.
  static Color get textOnChip => _p.onPrimary;
}
