import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants/ambient.dart';
import 'constants/design_tokens.dart';
import 'screens/onboarding_screen.dart';
import 'services/locator.dart';
import 'widgets/ambient_backdrop.dart';

class GorkApp extends StatelessWidget {
  const GorkApp({super.key});

  ThemeData _theme(Palette p, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: p.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.primary,
        onPrimary: p.onPrimary,
        secondary: p.primary,
        onSecondary: p.onPrimary,
        surface: p.surface,
        onSurface: p.textPrimary,
        error: p.error,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.textPrimary,
        elevation: 0,
        surfaceTintColor: p.background,
      ),
      dividerColor: p.border,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Outermost listener: the raw mode chosen on the Theme page. Any tap
    // there resolves instantly; the ambient version keeps the resolution
    // fresh for Auto (its timer ticks every 5 minutes) and for the weather.
    return ValueListenableBuilder<String>(
      valueListenable: themeModeSetting,
      builder: (context, mode, __) {
        return ValueListenableBuilder<int>(
          valueListenable: ambient.version,
          builder: (context, _, ___) {
            // Movement 57: the phase follows the user's SUN when the
            // locator is bound (real sunrise/sunset at their stored
            // location) and the wall clock when it is not (tests).
            final bool located = Locator.bound;
            final DateTime now = AmbientBackdrop.clock();
            final AmbientPhase phase = located
                ? phaseForAt(now,
                    lat: Locator.ambientLat, lon: Locator.ambientLon)
                : phaseFor(now);
            final AmbientWeather weather = ambient.weather;
            final wet = ambient.wetWeather;
            final platform = WidgetsBinding
                .instance.platformDispatcher.platformBrightness;
            // Movement 39: one resolution for everything — MaterialApp
            // themeMode, glass colors and the ambient backdrop all follow
            // this single answer.
            final Brightness resolved = resolveBrightness(
                mode, platform, now,
                lat: located ? Locator.ambientLat : null,
                lon: located ? Locator.ambientLon : null);
            GlassColors.brightness.value = resolved;
            // Movement 55: the ANDROID system chrome follows the theme too —
            // a dark app must not sit on a white system navigation bar (the
            // v1.12.0 screenshot complaint). Movement 57: the nav bar takes
            // the AMBIENT background, so the three-button bar glows warm at
            // sunset and cream at noon with everything else.
            final palette = resolved == Brightness.dark
                ? ambientPalette(Palette.dark, phase,
                    wet: wet, weather: weather)
                : ambientPalette(Palette.light, phase,
                    wet: wet, weather: weather);
            resolvedPalette.value = palette;
            SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: resolved == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarColor: palette.background,
              systemNavigationBarIconBrightness: resolved == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarDividerColor: Colors.transparent,
            ));
            themeSetting.value =
                resolved == Brightness.dark ? 'Dark' : 'Light';
            return AmbientScope(
                phase: phase,
                wet: wet,
                weather: weather,
                child: Builder(builder: (context) {
              return MaterialApp(
                title: 'gork',
                theme: _theme(palette, Brightness.light),
                darkTheme: _theme(palette, Brightness.dark),
                themeMode: resolved == Brightness.dark
                    ? ThemeMode.dark
                    : ThemeMode.light,
                // NOT const: a const home is an identical widget instance
                // across rebuilds, so Flutter skips the whole shell subtree
                // on a theme change — glass colors stay stale (the v1.7.0
                // screenshot bug: dark cards over the day sky).
                home: OnboardingGate(),
              );
            }));
          },
        );
      },
    );
  }
}
