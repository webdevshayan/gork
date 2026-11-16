import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gork/constants/ambient.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/services/weather_service.dart';

void main() {
  test('phase boundaries (clock fallback)', () {
    DateTime at(int h) => DateTime(2026, 1, 1, h, 0);
    expect(phaseFor(at(4)), AmbientPhase.night);
    expect(phaseFor(at(5)), AmbientPhase.dawn);
    expect(phaseFor(at(7)), AmbientPhase.dawn);
    expect(phaseFor(at(8)), AmbientPhase.morning);
    expect(phaseFor(at(11)), AmbientPhase.morning);
    expect(phaseFor(at(12)), AmbientPhase.afternoon);
    expect(phaseFor(at(16)), AmbientPhase.afternoon);
    expect(phaseFor(at(17)), AmbientPhase.evening);
    expect(phaseFor(at(20)), AmbientPhase.evening);
    expect(phaseFor(at(21)), AmbientPhase.night);
    expect(phaseFor(at(23)), AmbientPhase.night);
  });

  test('solar phases track the real sun (Movement 57)', () {
    double lat = 26.4195, lon = 67.8622;
    final DateTime day = DateTime.utc(2026, 11, 16);
    final DateTime sunrise = sunriseFor(lat, lon, day);
    final DateTime sunset = sunsetFor(lat, lon, day);
    // Sane sun: sunset follows sunrise and the day is 8-16 hours long.
    expect(sunset.isAfter(sunrise), isTrue);
    final int dayMinutes = sunset.difference(sunrise).inMinutes;
    expect(dayMinutes, inInclusiveRange(8 * 60, 16 * 60));

    // Everything is asserted RELATIVE to the computed sun, never to a wall
    // hour — the test runs in whatever timezone the box has.
    DateTime at(Duration d) => sunrise.add(d);
    expect(phaseForAt(at(const Duration(minutes: -90)), lat: lat, lon: lon),
        AmbientPhase.night, reason: '90 min before sunrise is night');
    expect(phaseForAt(at(const Duration(minutes: 30)), lat: lat, lon: lon),
        AmbientPhase.dawn, reason: 'just after sunrise is dawn');
    final DateTime noon = sunrise.add(Duration(minutes: dayMinutes ~/ 2));
    expect(
        phaseForAt(noon.subtract(const Duration(minutes: 1)),
            lat: lat, lon: lon),
        AmbientPhase.morning);
    expect(
        phaseForAt(noon.add(const Duration(minutes: 1)), lat: lat, lon: lon),
        AmbientPhase.afternoon);
    expect(
        phaseForAt(sunset.subtract(const Duration(minutes: 30)),
            lat: lat, lon: lon),
        AmbientPhase.evening,
        reason: '30 min before sunset opens the sunset window');
    expect(
        phaseForAt(sunset.add(const Duration(hours: 3)), lat: lat, lon: lon),
        AmbientPhase.night,
        reason: '3 hours after sunset is night again');
  });

  test('Auto follows the sun, not the wall clock', () {
    const double lat = 26.4195, lon = 67.8622;
    final DateTime sunrise = sunriseFor(lat, lon, DateTime.utc(2026, 11, 16));
    final DateTime sunset = sunsetFor(lat, lon, DateTime.utc(2026, 11, 16));

    expect(
        resolveBrightness(null, Brightness.light,
            sunrise.subtract(const Duration(hours: 2)),
            lat: lat, lon: lon),
        Brightness.dark,
        reason: 'deep night is dark');
    expect(
        resolveBrightness(null, Brightness.dark,
            sunrise.add(const Duration(minutes: 30)),
            lat: lat, lon: lon),
        Brightness.light,
        reason: 'dawn is light');
    expect(
        resolveBrightness(null, Brightness.light,
            sunset.subtract(const Duration(minutes: 30)),
            lat: lat, lon: lon),
        Brightness.dark,
        reason: 'the sunset window is dark');
    expect(
        resolveBrightness(null, Brightness.light,
            sunset.add(const Duration(hours: 3)),
            lat: lat, lon: lon),
        Brightness.dark,
        reason: 'night after sunset is dark');

    // Without location, the clock table applies (pure .hour — TZ-proof).
    expect(resolveBrightness(null, Brightness.light, DateTime(2026, 1, 1, 17)),
        Brightness.dark);
    expect(resolveBrightness(null, Brightness.dark, DateTime(2026, 1, 1, 12)),
        Brightness.light);
    // Explicit modes always win.
    expect(
        resolveBrightness('Light', Brightness.dark, DateTime(2026, 1, 1, 22),
            lat: lat, lon: lon),
        Brightness.light);
  });

  test('every WMO code maps to a weather family', () {
    expect(weatherKindFor(0), AmbientWeather.clear);
    expect(weatherKindFor(2), AmbientWeather.cloudy);
    expect(weatherKindFor(45), AmbientWeather.fog);
    expect(weatherKindFor(63), AmbientWeather.rain);
    expect(weatherKindFor(75), AmbientWeather.snow);
    expect(weatherKindFor(81), AmbientWeather.rain);
    expect(weatherKindFor(95), AmbientWeather.storm);
    expect(weatherKindFor(99), AmbientWeather.storm);
    expect(weatherKindFor(200), AmbientWeather.cloudy); // unknown → cloudy
  });

  test('every phase owns a distinct gruvbox neutral set', () {
    final phases = AmbientPhase.values;
    final backgrounds = <Color>{};
    for (final phase in phases) {
      final p = ambientPalette(Palette.dark, phase);
      backgrounds.add(p.background);
      // Text and primary tokens are NEVER themed (contrast + ink rule).
      expect(p.textPrimary, Palette.dark.textPrimary, reason: '$phase');
      expect(p.primary, Palette.dark.primary, reason: '$phase');
      // Borders differ from the background — cards must read as cards.
      expect(p.border, isNot(equals(p.background)), reason: '$phase');
    }
    expect(backgrounds.length, phases.length,
        reason: 'each phase paints its own background');
  });

  test('sunset wears the warm gruvbox set; night the cool one', () {
    final sunset = ambientPalette(Palette.dark, AmbientPhase.evening);
    final night = ambientPalette(Palette.dark, AmbientPhase.night);
    // Warm: red channel leads in every sunset neutral.
    expect(sunset.background.r, greaterThan(sunset.background.b));
    expect(sunset.surface.r, greaterThan(sunset.surface.b));
    // Night is the cool gruvbox dark (bg0_h).
    expect(night.background, const Color(0xFF1D2021));
    expect(night.surface, const Color(0xFF282828));
  });

  test('day phases wear the gruvbox cream set', () {
    final morning = ambientPalette(Palette.light, AmbientPhase.morning);
    expect(morning.background, const Color(0xFFFBF1C7));
    expect(morning.surface, const Color(0xFFF9F5D7));
    final dawn = ambientPalette(Palette.light, AmbientPhase.dawn);
    expect(dawn.background, const Color(0xFFF2E5BC));
  });

  test('wet weather still shifts the light background (compat)', () {
    final dry = ambientPalette(Palette.light, AmbientPhase.afternoon);
    final wet = ambientPalette(Palette.light, AmbientPhase.afternoon,
        wet: true);
    expect(wet.background, isNot(equals(dry.background)));
  });

  test('weather washes shift the neutrals, never the text or buttons', () {
    for (final dark in [false, true]) {
      for (final weather in AmbientWeather.values) {
        final p = ambientPalette(
            dark ? Palette.dark : Palette.light,
            dark ? AmbientPhase.night : AmbientPhase.afternoon,
            weather: weather);
        final base =
            dark ? Palette.dark : Palette.light;
        expect(p.textPrimary, base.textPrimary, reason: '$weather');
        expect(p.primary, base.primary, reason: '$weather');
      }
    }
    // Rain cools the sunset background (red-blue gap narrows vs clear).
    final clearSunset =
        ambientPalette(Palette.dark, AmbientPhase.evening);
    final rainSunset = ambientPalette(Palette.dark, AmbientPhase.evening,
        weather: AmbientWeather.rain);
    final double clearGap =
        clearSunset.background.r - clearSunset.background.b;
    final double rainGap =
        rainSunset.background.r - rainSunset.background.b;
    expect(rainGap, lessThan(clearGap));
  });

  test('text contrast holds on EVERY themed surface (phase × weather)', () {
    double chan(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    double lum(Color c) => 0.2126 * chan(c.r) +
        0.7152 * chan(c.g) +
        0.0722 * chan(c.b);
    double contrast(Color a, Color b) {
      final la = lum(a), lb = lum(b);
      final hi = math.max(la, lb), lo = math.min(la, lb);
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final base in [Palette.light, Palette.dark]) {
      final dark = identical(base, Palette.dark);
      for (final phase in AmbientPhase.values) {
        for (final weather in AmbientWeather.values) {
          final p = ambientPalette(base, phase, weather: weather);
          // Real combinations only: light phases ride the light base,
          // dark phases the dark base.
          final bool reachable =
              (phase == AmbientPhase.evening || phase == AmbientPhase.night) ==
                  dark;
          if (!reachable) continue;
          for (final (Color surfaceColor, String what) in [
            (p.background, 'background'),
            (p.surface, 'surface'),
            (p.surfaceElevated, 'surfaceElevated'),
          ]) {
            expect(
                contrast(p.textPrimary, surfaceColor),
                greaterThanOrEqualTo(4.5),
                reason: '$phase/$weather text on $what');
          }
        }
      }
    }
  });

  test('onPrimary keeps at least 4.5:1 contrast on every primary', () {
    double chan(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    double lum(Color c) => 0.2126 * chan(c.r) +
        0.7152 * chan(c.g) +
        0.0722 * chan(c.b);
    double contrast(Color a, Color b) {
      final la = lum(a), lb = lum(b);
      final hi = math.max(la, lb), lo = math.min(la, lb);
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final base in [Palette.light, Palette.dark]) {
      for (final phase in AmbientPhase.values) {
        final p = ambientPalette(base, phase);
        expect(contrast(p.onPrimary, p.primary), greaterThanOrEqualTo(4.5),
            reason:
                '$phase ${identical(base, Palette.light) ? 'light' : 'dark'}');
      }
    }
  });

  test('the sunset gradient glows ember over the gruvbox dark floor', () {
    final sunset = ambientGradient(AmbientPhase.evening, true);
    expect(sunset.length, 3);
    expect(sunset.last, const Color(0xFF1D2021));
    expect(sunset.first.r, greaterThan(sunset.first.b));
  });
}
