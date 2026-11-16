import 'package:flutter/material.dart';

import 'design_tokens.dart';
import '../services/weather_service.dart';

/// Ambient phase — the UI adapts to the time of day and the weather.
enum AmbientPhase { dawn, morning, afternoon, evening, night }

/// Clock-hour phases (Movement 39). Kept as the fallback when the device
/// has no usable location; the shell prefers the solar phases below.
AmbientPhase phaseFor(DateTime time) => _clockPhase(time.hour);

AmbientPhase _clockPhase(int hour) {
  if (hour >= 5 && hour < 8) return AmbientPhase.dawn;
  if (hour >= 8 && hour < 12) return AmbientPhase.morning;
  if (hour >= 12 && hour < 17) return AmbientPhase.afternoon;
  if (hour >= 17 && hour < 21) return AmbientPhase.evening;
  return AmbientPhase.night;
}

/// Movement 57 — the phase from the USER'S SUN, not the wall clock.
/// Sunrise/sunset come from the NOAA math in weather_service.dart for the
/// user's stored location, so "evening" starts ~90 minutes before their
/// real sunset and "dawn" tracks their real sunrise (polar nights clamp).
///
///   night    < sunrise-60m            or >= sunset+150m
///   dawn     [sunrise-60m, sunrise+90m)
///   morning  [sunrise+90m, solar noon)
///   afternoon[solar noon,  sunset-90m)
///   evening  [sunset-90m,  sunset+150m)   <- the gruvbox sunset window
AmbientPhase phaseForAt(DateTime time, {required double lat, required double lon}) {
  // Pure epoch comparisons: sunrise/sunset come back as UTC instants and
  // [time] normalizes to UTC — correct in EVERY device timezone (a 00:30
  // UTC instant is still "night" even when the local wall clock says
  // evening, because the day's sun for that instant's date is used).
  final DateTime now = time.toUtc();
  final DateTime sunrise = sunriseFor(lat, lon, now);
  final DateTime sunset = sunsetFor(lat, lon, now);

  if (now.isBefore(sunrise.subtract(const Duration(minutes: 60)))) {
    return AmbientPhase.night;
  }
  if (now.isBefore(sunrise.add(const Duration(minutes: 90)))) {
    return AmbientPhase.dawn;
  }
  final DateTime noon = sunrise.add(sunset.difference(sunrise) ~/ 2);
  if (now.isBefore(noon)) return AmbientPhase.morning;
  if (now.isBefore(sunset.subtract(const Duration(minutes: 90)))) {
    return AmbientPhase.afternoon;
  }
  if (now.isBefore(sunset.add(const Duration(minutes: 150)))) {
    return AmbientPhase.evening;
  }
  return AmbientPhase.night;
}

/// Weather family — drives the palette modifiers (Movement 57).
enum AmbientWeather { clear, cloudy, fog, rain, snow, storm }

/// Open-Meteo WMO weather code → the ambient weather family.
AmbientWeather weatherKindFor(int code) {
  if (code == 0) return AmbientWeather.clear;
  if (code >= 1 && code <= 3) return AmbientWeather.cloudy;
  if (code == 45 || code == 48) return AmbientWeather.fog;
  if (code >= 51 && code <= 67) return AmbientWeather.rain;
  if (code >= 71 && code <= 77) return AmbientWeather.snow;
  if (code >= 80 && code <= 82) return AmbientWeather.rain;
  if (code >= 95 && code <= 99) return AmbientWeather.storm;
  return AmbientWeather.cloudy;
}

/// Ambient controller: notified version counter drives theme rebuilds.
class AmbientController {
  final ValueNotifier<int> version = ValueNotifier<int>(0);
  bool wetWeather = false;

  /// Latest Open-Meteo report (defaults: benign clear day until fetched).
  int weatherCode = 0;
  double tempC = 24;

  AmbientWeather get weather => weatherKindFor(weatherCode);

  void refresh() => version.value = version.value + 1;
}

/// Blend a color toward [target] by [t] (0..1).
Color blend(Color a, Color b, double t) => Color.lerp(a, b, t)!;

// ---------------------------------------------------------------------------
// Movement 57 — the gruvbox-inspired ambient palettes.
//
// Every phase owns a FULL neutral set: app background, cards (surface),
// raised cards (surfaceElevated) and borders. Sunset/evening goes warm
// gruvbox dark (bg0 series with the orange glow), night goes the cool
// gruvbox dark, the day phases wear the gruvbox cream light series.
//
// Deliberately NOT themed: primary/onPrimary (buttons stay ink — Movement
// 50) and the text tokens (contrast guarantees hold unchanged). Weather
// washes shift the neutrals: rain cools, storm purples, fog grays,
// snow lightens, clouds neutralize.
// ---------------------------------------------------------------------------

const Map<AmbientWeather, (Color, double)> _weatherWashDark = {
  AmbientWeather.clear: (Color(0xFF000000), 0),
  AmbientWeather.cloudy: (Color(0xFF1A1D1F), 0.30),
  AmbientWeather.fog: (Color(0xFF1E2021), 0.34),
  AmbientWeather.rain: (Color(0xFF101B22), 0.38),
  AmbientWeather.snow: (Color(0xFF1D262C), 0.26),
  AmbientWeather.storm: (Color(0xFF150F1C), 0.42),
};

const Map<AmbientWeather, (Color, double)> _weatherWashLight = {
  AmbientWeather.clear: (Color(0xFFFFFFFF), 0),
  AmbientWeather.cloudy: (Color(0xFFEDE7D4), 0.30),
  AmbientWeather.fog: (Color(0xFFE9E5DA), 0.36),
  AmbientWeather.rain: (Color(0xFFDCE5E2), 0.34),
  AmbientWeather.snow: (Color(0xFFF7FAFB), 0.30),
  AmbientWeather.storm: (Color(0xFFE2DCE6), 0.34),
};

Color _wash(Color c, AmbientWeather weather, bool dark) {
  final (tint, strength) =
      dark ? _weatherWashDark[weather]! : _weatherWashLight[weather]!;
  return blend(c, tint, strength);
}

/// Gruvbox neutral sets per phase: (background, surface, surfaceElevated,
/// border). Warm sunset, cool night, cream day.
const Map<AmbientPhase, (Color, Color, Color, Color)> _gruvboxNeutrals = {
  // Sunset window: warm gruvbox dark — bg0 with an orange-warm lean.
  AmbientPhase.evening: (
    Color(0xFF26211B),
    Color(0xFF32302F), // bg1 warm
    Color(0xFF3C3836), // bg2
    Color(0xFF504945), // bg3
  ),
  // Night: the deep gruvbox dark series.
  AmbientPhase.night: (
    Color(0xFF1D2021), // bg0_h
    Color(0xFF282828), // bg0
    Color(0xFF32302F), // bg1
    Color(0xFF3C3836), // bg2
  ),
  // Dawn: peach-warmed cream.
  AmbientPhase.dawn: (
    Color(0xFFF2E5BC), // bg1 light (peach)
    Color(0xFFFBF1C7), // bg0
    Color(0xFFF9F5D7), // bg0_h
    Color(0xFFD5C4A1), // bg2
  ),
  // Morning: the classic gruvbox light cream.
  AmbientPhase.morning: (
    Color(0xFFFBF1C7),
    Color(0xFFF9F5D7),
    Color(0xFFF2E5BC),
    Color(0xFFD5C4A1),
  ),
  // Afternoon: brighter cream than morning — each phase paints its own bg.
  AmbientPhase.afternoon: (
    Color(0xFFFDF7E3),
    Color(0xFFF9F5D7),
    Color(0xFFF2E5BC),
    Color(0xFFD5C4A1),
  ),
};

/// Phase-tinted palette. Background, cards and borders follow the phase and
/// the weather (gruvbox-inspired); text and primary tokens stay untouched so
/// every contrast guarantee and the ink-button rule still hold.
Palette ambientPalette(
  Palette base,
  AmbientPhase phase, {
  bool wet = false,
  AmbientWeather? weather,
}) {
  final effectiveWeather =
      weather ?? (wet ? AmbientWeather.rain : AmbientWeather.clear);
  final dark = identical(base, Palette.dark);
  final (bg, surface, elevated, border) = _gruvboxNeutrals[phase]!;

  Color wash(Color c) => _wash(c, effectiveWeather, dark);

  return Palette(
    background: wash(bg),
    surface: wash(surface),
    surfaceElevated: wash(elevated),
    textPrimary: base.textPrimary,
    textSecondary: base.textSecondary,
    textTertiary: base.textTertiary,
    primary: base.primary,
    onPrimary: base.onPrimary,
    success: base.success,
    warning: base.warning,
    error: base.error,
    border: wash(border),
  );
}

/// The backdrop gradient per phase — the ambient glow behind the glass,
/// replacing the old photo assets (Movement 57).
List<Color> ambientGradient(AmbientPhase phase, bool dark,
    {AmbientWeather weather = AmbientWeather.clear}) {
  Color wash(Color c) => _wash(c, weather, dark);
  final List<Color> colors = switch (phase) {
    // Sunset: the warm glow — ember top, gruvbox dark floor.
    AmbientPhase.evening => dark
        ? const [Color(0xFF3C2F21), Color(0xFF2B2118), Color(0xFF1D2021)]
        : const [Color(0xFFF3D9A4), Color(0xFFF2E5BC), Color(0xFFFBF1C7)],
    AmbientPhase.night => dark
        ? const [Color(0xFF1D2021), Color(0xFF15181A), Color(0xFF1D2021)]
        : const [Color(0xFFFBF1C7), Color(0xFFF2E5BC)],
    AmbientPhase.dawn => dark
        ? const [Color(0xFF2B2320), Color(0xFF1D2021)]
        : const [Color(0xFFF3D9A4), Color(0xFFFBF1C7)],
    AmbientPhase.morning => dark
        ? const [Color(0xFF23272B), Color(0xFF1D2021)]
        : const [Color(0xFFFBF1C7), Color(0xFFF9F5D7)],
    AmbientPhase.afternoon => dark
        ? const [Color(0xFF23272B), Color(0xFF1D2021)]
        : const [Color(0xFFFDF7E3), Color(0xFFFBF1C7)],
  };
  return colors.map(wash).toList();
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
///
/// With [lat]/[lon] the Auto branch follows the user's real SUN instead of
/// the wall clock (Movement 57): dark from ~90 minutes before sunset until
/// ~60 minutes before sunrise.
Brightness resolveBrightness(
  String? mode,
  Brightness platform,
  DateTime now, {
  double? lat,
  double? lon,
}) {
  switch (mode) {
    case 'Light':
      return Brightness.light;
    case 'Dark':
      return Brightness.dark;
    case 'System':
      return platform;
    default:
      final phase = (lat != null && lon != null)
          ? phaseForAt(now, lat: lat, lon: lon)
          : phaseFor(now);
      final darkPhase =
          phase == AmbientPhase.evening || phase == AmbientPhase.night;
      return darkPhase ? Brightness.dark : Brightness.light;
  }
}

/// Ambient scope: exposes phase + weather down the tree. The app shell
/// publishes it; the backdrop reads the solar phase from it when present.
class AmbientScope extends InheritedWidget {
  final AmbientPhase phase;
  final bool wet;
  final AmbientWeather weather;

  const AmbientScope({
    super.key,
    required this.phase,
    required this.wet,
    this.weather = AmbientWeather.clear,
    required super.child,
  });

  static AmbientScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmbientScope>()!;

  @override
  bool updateShouldNotify(AmbientScope oldWidget) =>
      oldWidget.phase != phase ||
      oldWidget.wet != wet ||
      oldWidget.weather != weather;
}

/// Ambient controller singleton: main() refreshes it on a timer; the app
/// shell and the backdrop read the latest phase inputs from it.
final AmbientController ambient = AmbientController();
