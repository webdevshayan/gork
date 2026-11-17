import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gork/constants/ambient.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/services/weather_service.dart';

/// WCAG relative luminance / contrast, shared by the assertions below.
double chan(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
double lum(Color c) =>
    0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
double contrast(Color a, Color b) {
  final la = lum(a), lb = lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

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

  test('solar phases track the real sun', () {
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
        reason: '30 min before sunset opens the dark window');
    expect(
        phaseForAt(sunset.add(const Duration(hours: 3)), lat: lat, lon: lon),
        AmbientPhase.night,
        reason: '3 hours after sunset is night again');
  });

  test('Movement 59 — the ONLY mode is auto: light by day, dark by night',
      () {
    const double lat = 26.4195, lon = 67.8622;
    final DateTime sunrise = sunriseFor(lat, lon, DateTime.utc(2026, 11, 16));
    final DateTime sunset = sunsetFor(lat, lon, DateTime.utc(2026, 11, 16));

    expect(
        resolveBrightness(Brightness.light,
            sunrise.subtract(const Duration(hours: 2)),
            lat: lat, lon: lon),
        Brightness.dark,
        reason: 'deep night is dark, whatever the OS says');
    expect(
        resolveBrightness(Brightness.dark,
            sunrise.add(const Duration(minutes: 30)),
            lat: lat, lon: lon),
        Brightness.light,
        reason: 'dawn is light, whatever the OS says');
    expect(
        resolveBrightness(Brightness.light,
            sunset.subtract(const Duration(minutes: 30)),
            lat: lat, lon: lon),
        Brightness.dark,
        reason: 'the sunset window is dark');
    expect(
        resolveBrightness(Brightness.light,
            sunset.add(const Duration(hours: 3)),
            lat: lat, lon: lon),
        Brightness.dark,
        reason: 'night after sunset is dark');

    // Without location, the clock table applies (pure .hour — TZ-proof).
    expect(resolveBrightness(Brightness.light, DateTime(2026, 1, 1, 17)),
        Brightness.dark);
    expect(resolveBrightness(Brightness.dark, DateTime(2026, 1, 1, 12)),
        Brightness.light);
  });

  test('the theme surfaces are strictly ACHROMATIC — gray and black, '
      'nothing else', () {
    void expectNeutral(Color c, String what, String mode) {
      expect(c.r, closeTo(c.g, 1 / 255),
          reason: '$mode $what must have r == g (no color tint)');
      expect(c.g, closeTo(c.b, 1 / 255),
          reason: '$mode $what must have g == b (no color tint)');
    }

    expectNeutral(Palette.light.background, 'background', 'light');
    expectNeutral(Palette.light.surface, 'surface', 'light');
    expectNeutral(Palette.light.surfaceElevated, 'surfaceElevated', 'light');
    expectNeutral(Palette.light.border, 'border', 'light');
    expectNeutral(Palette.light.primary, 'primary', 'light');

    expectNeutral(Palette.dark.background, 'background', 'dark');
    expectNeutral(Palette.dark.surface, 'surface', 'dark');
    expectNeutral(Palette.dark.surfaceElevated, 'surfaceElevated', 'dark');
    expectNeutral(Palette.dark.border, 'border', 'dark');
    expectNeutral(Palette.dark.primary, 'primary', 'dark');
  });

  test('dark mode sinks to near-black; light mode stays a soft gray', () {
    expect(Palette.dark.background.r, lessThan(0.05),
        reason: 'the user asked for black in the dark palette');
    expect(Palette.light.background.r, greaterThan(0.85),
        reason: 'the light palette is light gray, not dark');
    expect(Palette.dark.background.r,
        lessThan(Palette.dark.surfaceElevated.r),
        reason: 'elevated surfaces stay lighter than the background');
    expect(Palette.light.background.r,
        lessThan(Palette.light.surface.r),
        reason: 'cards stay brighter than the light background');
  });

  test('text contrast holds on EVERY themed surface (both modes)', () {
    for (final p in [Palette.light, Palette.dark]) {
      for (final (Color surfaceColor, String what) in [
        (p.background, 'background'),
        (p.surface, 'surface'),
        (p.surfaceElevated, 'surfaceElevated'),
      ]) {
        expect(contrast(p.textPrimary, surfaceColor),
            greaterThanOrEqualTo(4.5),
            reason: 'text on $what');
        expect(contrast(p.textSecondary, surfaceColor),
            greaterThanOrEqualTo(3.0),
            reason: 'secondary text on $what');
      }
    }
  });

  test('onPrimary keeps at least 4.5:1 contrast on primary', () {
    for (final p in [Palette.light, Palette.dark]) {
      expect(contrast(p.onPrimary, p.primary), greaterThanOrEqualTo(4.5));
    }
  });

  test('the backdrop gradient is a neutral gray fade, not a colored sky',
      () {
    final dark = ambientGradient(true);
    final light = ambientGradient(false);
    for (final c in dark) {
      expect(c.r, closeTo(c.g, 1 / 255), reason: 'dark gradient is gray');
      expect(c.b, closeTo(c.r, 1 / 255), reason: 'dark gradient is gray');
      expect(c.r, lessThan(0.1), reason: 'dark gradient sinks to black');
    }
    for (final c in light) {
      expect(c.r, closeTo(c.g, 1 / 255), reason: 'light gradient is gray');
      expect(c.b, closeTo(c.r, 1 / 255), reason: 'light gradient is gray');
    }
    expect(dark.length, 2);
    expect(light.length, 2);
  });
}
