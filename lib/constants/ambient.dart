import 'package:flutter/material.dart';

import 'design_tokens.dart';
import '../services/weather_service.dart';

/// Ambient phase — the UI adapts to the time of day (Movement 59: the phase
/// now decides ONLY light vs dark; the palette itself is pure gray/black).
enum AmbientPhase { dawn, morning, afternoon, evening, night }

/// Clock-hour phases. The fallback when the device has no usable location;
/// the shell prefers the solar phases below.
AmbientPhase phaseFor(DateTime time) => _clockPhase(time.hour);

AmbientPhase _clockPhase(int hour) {
  if (hour >= 5 && hour < 8) return AmbientPhase.dawn;
  if (hour >= 8 && hour < 12) return AmbientPhase.morning;
  if (hour >= 12 && hour < 17) return AmbientPhase.afternoon;
  if (hour >= 17 && hour < 21) return AmbientPhase.evening;
  return AmbientPhase.night;
}

/// The phase from the USER'S SUN, not the wall clock. Sunrise/sunset come
/// from the NOAA math in weather_service.dart for the user's stored
/// location, so dark mode starts ~90 minutes before their real sunset and
/// light mode returns ~60 minutes after their real sunrise (polar nights
/// clamp).
///
///   night    < sunrise-60m            or >= sunset+150m
///   dawn     [sunrise-60m, sunrise+90m)
///   morning  [sunrise+90m, solar noon)
///   afternoon[solar noon,  sunset-90m)
///   evening  [sunset-90m,  sunset+150m)
AmbientPhase phaseForAt(DateTime time, {required double lat, required double lon}) {
  // Pure epoch comparisons: sunrise/sunset come back as UTC instants and
  // [time] normalizes to UTC — correct in EVERY device timezone.
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

/// Ambient controller: notified version counter drives theme rebuilds —
/// the periodic nudge is what flips light ⇄ dark "after some time" without
/// the user touching anything (Movement 59: the ONLY theme mode is auto).
class AmbientController {
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  void refresh() => version.value = version.value + 1;
}

// ---------------------------------------------------------------------------
// Movement 59 — the palette is GRAY and BLACK, nothing else.
//
// The user's call: no weather washes, no warm gruvbox phases, no theme
// picker. Light mode wears light grays and white, dark mode wears deep
// grays down to near-black. The only remaining hue is the semantic status
// trio (success / warning / error) used by status dots and errors — the
// THEME surfaces (background, cards, borders, buttons, chips) are strictly
// achromatic.
// ---------------------------------------------------------------------------

/// The backdrop gradient — a barely-there vertical gray fade. Dark mode
/// sinks to near-black; light mode stays a soft neutral gray.
List<Color> ambientGradient(bool dark) {
  return dark
      ? const [Color(0xFF101011), Color(0xFF060607)]
      : const [Color(0xFFF0F0F0), Color(0xFFE6E6E6)];
}

/// Movement 39/59 — the ONE theme mode is auto: the sun decides. Light from
/// ~60 minutes after sunrise until ~90 minutes before sunset; dark from
/// ~90 minutes before sunset until ~60 minutes after sunrise (with [lat]/
/// [lon]); otherwise the clock decides (dawn/morning/afternoon = light,
/// evening/night = dark). There is no manual override anymore — 'ui.theme'
/// from older installs is deliberately ignored.
Brightness resolveBrightness(
  Brightness platform,
  DateTime now, {
  double? lat,
  double? lon,
}) {
  if (lat != null && lon != null) {
    final phase = phaseForAt(now, lat: lat, lon: lon);
    final darkPhase =
        phase == AmbientPhase.evening || phase == AmbientPhase.night;
    return darkPhase ? Brightness.dark : Brightness.light;
  }
  // No location: dawn/morning/afternoon are light, evening/night dark.
  final phase = phaseFor(now);
  final darkPhase =
      phase == AmbientPhase.evening || phase == AmbientPhase.night;
  return darkPhase ? Brightness.dark : Brightness.light;
}

/// Ambient controller singleton: main() refreshes it on a timer; the app
/// shell reads the latest inputs from it and re-resolves light/dark.
final AmbientController ambient = AmbientController();
