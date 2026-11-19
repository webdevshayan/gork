import 'package:flutter/material.dart';

import '../constants/ambient.dart';
import '../constants/design_tokens.dart';
import '../services/locator.dart';
import '../widgets/glass.dart';
import '../widgets/screen.dart';

/// Movement 65 — Theme gets its own preference screen. The picker used to
/// be embedded in the menu's Preferences section (Movement 63); now the
/// menu carries a "Theme" row that pushes THIS screen. Same pref key
/// ('ui.theme'), same three modes, same keys for tests and muscle memory.
class ThemePreferencesScreen extends StatefulWidget {
  const ThemePreferencesScreen({super.key});

  @override
  State<ThemePreferencesScreen> createState() =>
      _ThemePreferencesScreenState();
}

class _ThemePreferencesScreenState extends State<ThemePreferencesScreen> {
  static const String kThemeKey = 'ui.theme';

  String get _themeChoice =>
      Locator.maybePrefs?.getString(kThemeKey) ?? 'auto';

  Future<void> _setTheme(String mode) async {
    final prefs = Locator.maybePrefs;
    if (prefs == null) return;
    await prefs.setString(kThemeKey, mode);
    // The app shell listens to the ambient version — nudge it so the new
    // choice rebuilds MaterialApp, the glass colors and the backdrop.
    ambient.refresh();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Screen(
      title: 'Theme',
      body: ListView(
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          GlassContainer(
            radius: 28,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined,
                        size: 22, color: GlassColors.text),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Appearance',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: GlassColors.text)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Auto follows the sun (light by day, dark by night). '
                  'Your choice wins over the sun until you switch back.',
                  style: TextStyle(
                      fontSize: 14, height: 1.4, color: GlassColors.textDim),
                ),
                const SizedBox(height: 12),
                GlassContainer(
                  radius: 20,
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      for (final (i, option) in const [
                        ('auto', 'Auto'),
                        ('light', 'Light'),
                        ('dark', 'Dark'),
                      ].indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            key: ValueKey('theme-${option.$1}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _setTheme(option.$1),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _themeChoice == option.$1
                                    ? GlassColors.chip
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    switch (option.$1) {
                                      'light' => Icons.light_mode_outlined,
                                      'dark' => Icons.dark_mode_outlined,
                                      _ => Icons.auto_awesome_outlined,
                                    },
                                    size: 16,
                                    color: _themeChoice == option.$1
                                        ? GlassColors.textOnChip
                                        : GlassColors.textDim,
                                    semanticLabel: 'Theme ${option.$2}',
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    option.$2,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _themeChoice == option.$1
                                            ? GlassColors.textOnChip
                                            : GlassColors.textDim),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
