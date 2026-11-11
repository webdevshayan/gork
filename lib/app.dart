import 'package:flutter/material.dart';

import 'constants/ambient.dart';
import 'constants/design_tokens.dart';
import 'screens/home_screen.dart';

/// Ambient scope: exposes phase + wet-weather flag down the tree.
class AmbientScope extends InheritedWidget {
  final AmbientPhase phase;
  final bool wet;

  const AmbientScope({
    super.key,
    required this.phase,
    required this.wet,
    required super.child,
  });

  static AmbientScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmbientScope>()!;

  @override
  bool updateShouldNotify(AmbientScope oldWidget) =>
      oldWidget.phase != phase || oldWidget.wet != wet;
}

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
    return ValueListenableBuilder<int>(
      valueListenable: ambient.version,
      builder: (context, _, __) {
        final phase = phaseFor(DateTime.now());
        final wet = ambient.wetWeather;
        return AmbientScope(phase: phase, wet: wet, child: Builder(builder: (context) {
          final scope = AmbientScope.of(context);
          final isDark =
              MediaQuery.platformBrightnessOf(context) == Brightness.dark;
          final base = isDark ? Palette.dark : Palette.light;
          final palette =
              ambientPalette(base, scope.phase, wet: scope.wet);
          return MaterialApp(
            title: 'gork',
            theme: _theme(palette, Brightness.light),
            darkTheme: _theme(palette, Brightness.dark),
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            home: const HomeScreen(),
          );
        }));
      },
    );
  }
}

/// Ambient controller singleton: main() refreshes it on a timer.
final AmbientController ambient = AmbientController();
