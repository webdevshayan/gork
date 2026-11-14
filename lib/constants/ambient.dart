import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Ambient phase — the UI subtly adapts to the time of day and weather.
enum AmbientPhase { dawn, morning, afternoon, evening, night }

AmbientPhase phaseFor(DateTime time) {
  final hour = time.hour;
  if (hour >= 5 && hour < 8) return AmbientPhase.dawn;
  if (hour >= 8 && hour < 12) return AmbientPhase.morning;
  if (hour >= 12 && hour < 17) return AmbientPhase.afternoon;
  if (hour >= 17 && hour < 21) return AmbientPhase.evening;
  return AmbientPhase.night;
}

/// Ambient controller: notified version counter drives theme rebuilds.
class AmbientController {
  final ValueNotifier<int> version = ValueNotifier<int>(0);
  bool wetWeather = false;

  void refresh() => version.value = version.value + 1;
}

/// Blend a color toward [target] by [t] (0..1).
Color blend(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// Phase-tinted palette. Only background tint and primary shift; text tokens
/// stay untouched so all contrast guarantees still hold.
Palette ambientPalette(Palette base, AmbientPhase phase, {bool wet = false}) {
  final dark = identical(base, Palette.dark);

  final Color phasePrimary = switch (phase) {
    AmbientPhase.dawn => dark ? const Color(0xFFFFB490) : const Color(0xFFB2541A),
    AmbientPhase.morning => dark ? const Color(0xFF6EA8FE) : const Color(0xFF2563EB),
    AmbientPhase.afternoon => dark ? const Color(0xFF6EE7B7) : const Color(0xFF0A7D56),
    AmbientPhase.evening => dark ? const Color(0xFFC4A6FE) : const Color(0xFF7C5CE0),
    AmbientPhase.night => dark ? const Color(0xFF8FA6FE) : const Color(0xFF4756C4),
  };

  // Subtle background tint: stronger for evening/night, mild otherwise.
  final tintStrength = switch (phase) {
    AmbientPhase.evening => 0.08,
    AmbientPhase.night => 0.10,
    AmbientPhase.dawn => 0.06,
    _ => 0.04,
  };
  final Color tint = dark
      ? const Color(0xFF101828)
      : (wet ? const Color(0xFFE7EDF5) : const Color(0xFFF2EFEA));
  final tintedBackground = blend(base.background, tint, tintStrength);

  return Palette(
    background: tintedBackground,
    surface: base.surface,
    surfaceElevated: base.surfaceElevated,
    textPrimary: base.textPrimary,
    textSecondary: base.textSecondary,
    textTertiary: base.textTertiary,
    primary: phasePrimary,
    onPrimary: _onFor(phasePrimary),
    success: base.success,
    warning: base.warning,
    error: base.error,
    border: base.border,
  );
}

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

Color _onFor(Color primary) {
  // WCAG-style gamma-expanded luminance: dark text on light-ish accents,
  // white text on deep accents.
  final lum = 0.2126 * _channel(primary.r) +
      0.7152 * _channel(primary.g) +
      0.0722 * _channel(primary.b);
  return lum > 0.35 ? const Color(0xFF111418) : const Color(0xFFFFFFFF);
}

/// Movement 39 — the mode table. One pure function decides what "the theme
/// is right now" means, so the app shell, the glass colors and the ambient
/// backdrop can never disagree:
///
///   Light  → always light, no matter what the OS or the clock says.
///   Dark   → always dark.
///   System → whatever the OS reports.
///   Auto   → the LOCAL CLOCK (dawn/morning/afternoon = light,
///            evening/night = dark) — deliberately NOT the OS.
///   anything else / null → Auto.
Brightness resolveBrightness(String? mode, Brightness platform, DateTime now) {
  switch (mode) {
    case 'Light':
      return Brightness.light;
    case 'Dark':
      return Brightness.dark;
    case 'System':
      return platform;
    default:
      final phase = phaseFor(now);
      final darkPhase =
          phase == AmbientPhase.evening || phase == AmbientPhase.night;
      return darkPhase ? Brightness.dark : Brightness.light;
  }
}
