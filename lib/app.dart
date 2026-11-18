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
      // Movement 60 — SOLID surfaces everywhere: snackbars, dialogs, modal
      // bottom sheets, popup menus and drawers all get the opaque palette
      // background; no translucency on any floating surface.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceElevated,
        contentTextStyle: TypeScale.bodySmall(color: p.textPrimary),
        actionTextColor: p.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusTokens.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusTokens.lg),
        ),
        titleTextStyle: TypeScale.heading(color: p.textPrimary),
        contentTextStyle: TypeScale.bodySmall(color: p.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusTokens.md),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Movement 60 — the theme is TOGGLEABLE again: 'ui.theme' persists the
    // user's choice ('light' / 'dark'); empty or 'auto' keeps Movement 59's
    // sun-driven resolution (light by day, dark by night). The Home screen
    // writes the pref and nudges [ambient.version] to rebuild everything.
    return ValueListenableBuilder<int>(
      valueListenable: ambient.version,
      builder: (context, _, ___) {
        final DateTime now = AmbientBackdrop.clock();
        final bool located = Locator.bound;
        final platform = WidgetsBinding
            .instance.platformDispatcher.platformBrightness;
        // One resolution for everything — MaterialApp themeMode, glass
        // colors and the ambient backdrop all follow this single answer.
        final String override = Locator.prefs.getString('ui.theme') ?? '';
        final Brightness resolved = override == 'light'
            ? Brightness.light
            : override == 'dark'
                ? Brightness.dark
                : resolveBrightness(platform, now,
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
