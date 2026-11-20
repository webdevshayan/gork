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
    // Movement 59: grays and white only — no warm or colored tint anywhere.
    // Movement 68: the faint tiers were lifted to hold WCAG AA (>= 4.5:1)
    // against EVERY surface they sit on — small faint text must stay
    // readable for tired and older eyes, not just in the design file.
    background: Color(0xFFF1F2F3),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF5F6F7),
    textPrimary: Color(0xFF131313),
    textSecondary: Color(0xFF424242),
    textTertiary: Color(0xFF5D5D5D),
    // Movement 50: black & white only — the "primary" accent is ink in light
    // mode (black buttons, white labels), never blue or any other hue.
    primary: Color(0xFF131313),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF15803D),
    warning: Color(0xFFB45309),
    error: Color(0xFFB91C1C),
    border: Color(0xFFDCDCDC),
  );

  static const Palette dark = Palette(
    // Movement 59: deep grays sinking to near-black — pure neutral, no blue.
    // Movement 68: textTertiary lifted (828282 sat right at the AA edge on
    // the elevated surface) so stamps, meta lines and step text keep a
    // comfortable margin above 4.5:1.
    background: Color(0xFF060607),
    surface: Color(0xFF151516),
    surfaceElevated: Color(0xFF1F1F20),
    textPrimary: Color(0xFFF2F2F2),
    textSecondary: Color(0xFFB4B4B4),
    textTertiary: Color(0xFF939393),
    // Dark mode mirrors it: white buttons, black labels.
    primary: Color(0xFFF2F2F2),
    onPrimary: Color(0xFF060607),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    error: Color(0xFFF87171),
    border: Color(0xFF2B2B2C),
  );
}

/// Typography scale: size / weight. Monospace only for code.
/// Never more than three weights on one screen.
///
/// Movement 68 — the scale is tuned to be SCANNED, not admired: body text
/// starts at 17, the small sizes never drop below 13, and line heights
/// breathe (1.45 on body). Every screen inherits this, so nothing else
/// needed touching to make the whole app easier on the eye — the dense
/// gray walls of small text (the Google setup card, empty states, stamps)
/// read one size larger and one shade brighter everywhere.
class TypeScale {
  static const double displaySize = 40;
  static const double titleSize = 28;
  static const double headingSize = 22;
  static const double bodySize = 17;
  static const double bodySmallSize = 15;
  static const double captionSize = 13;
  static const double codeSize = 14;

  static TextStyle display({Color? color}) => TextStyle(
      fontSize: displaySize, fontWeight: FontWeight.w700, height: 1.15, color: color);
  static TextStyle title({Color? color}) => TextStyle(
      fontSize: titleSize, fontWeight: FontWeight.w700, height: 1.2, color: color);
  static TextStyle heading({Color? color}) => TextStyle(
      fontSize: headingSize, fontWeight: FontWeight.w600, height: 1.25, color: color);
  static TextStyle body({Color? color}) => TextStyle(
      fontSize: bodySize, fontWeight: FontWeight.w400, height: 1.45, color: color);
  static TextStyle bodySmall({Color? color}) => TextStyle(
      fontSize: bodySmallSize, fontWeight: FontWeight.w400, height: 1.45, color: color);
  static TextStyle caption({Color? color}) => TextStyle(
      fontSize: captionSize, fontWeight: FontWeight.w400, height: 1.35, color: color);
  static TextStyle code({Color? color}) => TextStyle(
      fontSize: codeSize,
      fontWeight: FontWeight.w500,
      height: 1.35,
      fontFamily: 'monospace',
      color: color);
}

/// The ambient palette published by the app shell on every resolution —
/// Movement 59: the flat neutral palette (gray/black only); the shell
/// publishes it right after resolving brightness so `paletteOf` and the
/// glass colors can never disagree with the shell.
final ValueNotifier<Palette> resolvedPalette =
    ValueNotifier<Palette>(Palette.dark);

/// Resolve the semantic palette for the current brightness.
///
/// Movement 34 locked this to dark glass. Movement 39 unlocks it: the app
/// shell resolves the auto mode (light by day, dark by night — Movement 59
/// removed the manual modes) and publishes the result to
/// [GlassColors.brightness] — every consumer of this function follows that
/// resolution, so pages can never disagree with the shell.
Palette paletteOf(BuildContext context) => resolvedPalette.value;

/// Palette paletteOf reads — defined before [GlassColors] so its notifier
/// initializer can reference the coherence function below.
///
/// Coherence: whenever the resolved brightness flips WITHOUT the shell
/// around (tests, early frames), the palette follows to the flat base —
/// the app shell immediately refines it right after publishing the
/// brightness.
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

  /// Movement 60 — SOLID fill, everywhere. The user asked for solid
  /// background colors on every surface (buttons, drawers, dropdowns,
  /// modals, alerts, cards): no translucency, no blur dependence. The
  /// surface tone still follows the resolved palette.
  static Color get fill => _p.surface;

  /// Solid fill for primary chrome (input bar, nav pills) — one step
  /// elevated so the chrome still reads as chrome.
  static Color get fillStrong => _p.surfaceElevated;

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
  /// tab always inverts against the surface around it so it reads instantly.
  /// Movement 60: solid, no alpha.
  static Color get chip => _p.primary;

  /// Label on the active chip — black on the near-white chip in dark mode,
  /// white on the ink chip in light mode.
  static Color get textOnChip => _p.onPrimary;

  /// Error/danger text on glass (sunset dialog, form refusals) — dark red
  /// in light mode, light red in dark mode.
  static Color get danger => _p.error;
}
