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
    // Movement 59 — there is ONE theme mode: auto. The sun (or, without a
    // location, the clock) decides; the ambient version nudge keeps the
    // resolution fresh so light flips to dark "after some time" by itself.
    // No theme picker, no ui.theme override — older installs' saved choice
    // is deliberately ignored.
    return ValueListenableBuilder<int>(
      valueListenable: ambient.version,
      builder: (context, _, ___) {
        final DateTime now = AmbientBackdrop.clock();
        final bool located = Locator.bound;
        final platform = WidgetsBinding
            .instance.platformDispatcher.platformBrightness;
        // One resolution for everything — MaterialApp themeMode, glass
        // colors and the ambient backdrop all follow this single answer.
        final Brightness resolved = resolveBrightness(platform, now,
            lat: located ? Locator.ambientLat : null,
            lon: located ? Locator.ambientLon : null);
        GlassColors.brightness.value = resolved;
        final palette =
            resolved == Brightness.dark ? Palette.dark : Palette.light;
        resolvedPalette.value = palette;
        // Movement 55: the ANDROID system chrome follows the theme too —
        // a dark app must not sit on a white system navigation bar.
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
      },
    );
  }
}
