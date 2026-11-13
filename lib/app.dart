import 'package:flutter/material.dart';

import 'constants/ambient.dart';
import 'constants/design_tokens.dart';
import 'screens/onboarding_screen.dart';

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
          // Movement 34: the whole app is dark glass — one theme everywhere.
          final palette =
              ambientPalette(Palette.dark, scope.phase, wet: scope.wet);
          return MaterialApp(
            title: 'gork',
            theme: _theme(palette, Brightness.dark),
            darkTheme: _theme(palette, Brightness.dark),
            themeMode: ThemeMode.dark,
            home: const OnboardingGate(),
          );
        }));
      },
    );
  }
}

/// Ambient controller singleton: main() refreshes it on a timer.
final AmbientController ambient = AmbientController();
