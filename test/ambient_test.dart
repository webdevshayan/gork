import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gork/constants/ambient.dart';
import 'package:gork/constants/design_tokens.dart';

void main() {
  test('phase boundaries', () {
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

  test('ambient palette shifts primary and keeps text tokens', () {
    for (final base in [Palette.light, Palette.dark]) {
      for (final phase in AmbientPhase.values) {
        final p = ambientPalette(base, phase);
        expect(p.textPrimary, base.textPrimary);
        expect(p.textSecondary, base.textSecondary);
        expect(p.background, isNot(equals(base.background)),
            reason: '$phase should tint background');
      }
    }
    // Morning intentionally keeps the base blue; all other phases shift it.
    for (final phase in [
      AmbientPhase.dawn,
      AmbientPhase.afternoon,
      AmbientPhase.evening,
      AmbientPhase.night
    ]) {
      expect(ambientPalette(Palette.light, phase).primary,
          isNot(equals(Palette.light.primary)),
          reason: '$phase should shift primary');
    }
  });

  test('wet weather changes light background tint direction', () {
    final dry = ambientPalette(Palette.light, AmbientPhase.afternoon);
    final wet = ambientPalette(Palette.light, AmbientPhase.afternoon, wet: true);
    expect(wet.background, isNot(equals(dry.background)));
  });

  test('onPrimary keeps at least 4.5:1 contrast on every accent', () {
    double chan(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
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
            reason: '$phase ${identical(base, Palette.light) ? 'light' : 'dark'}');
      }
    }
  });
}
