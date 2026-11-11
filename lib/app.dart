import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../screens/home_screen.dart';

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
    return MaterialApp(
      title: 'gork',
      theme: _theme(Palette.light, Brightness.light),
      darkTheme: _theme(Palette.dark, Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
