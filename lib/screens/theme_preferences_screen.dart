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
                // Movement 69 — proper RADIO rows, not chips: one obvious
                // choice, big round targets, the classic settings pattern
                // every phone user already knows.
                Column(
                  children: [
                    for (final (i, option) in const [
                      ('auto', 'Auto', 'Light by day, dark by night'),
                      ('light', 'Light', 'Always the bright look'),
                      ('dark', 'Dark', 'Always the dark look'),
                    ].indexed) ...[
                      if (i > 0)
                        Divider(color: GlassColors.divider, height: 1),
                      GestureDetector(
                        key: ValueKey('theme-${option.$1}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _setTheme(option.$1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            children: [
                              Icon(
                                switch (option.$1) {
                                  'light' => Icons.light_mode_outlined,
                                  'dark' => Icons.dark_mode_outlined,
                                  _ => Icons.auto_awesome_outlined,
                                },
                                size: 22,
                                color: GlassColors.text,
                                semanticLabel: 'Theme ${option.$2}',
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(option.$2,
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: GlassColors.text)),
                                    const SizedBox(height: 2),
                                    Text(option.$3,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: GlassColors.textDim)),
                                  ],
                                ),
                              ),
                              // The radio: outlined ring, filled dot when
                              // selected — instant to read at any age.
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      width: 2,
                                      color: _themeChoice == option.$1
                                          ? GlassColors.text
                                          : GlassColors.textFaint),
                                ),
                                child: _themeChoice == option.$1
                                    ? Center(
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: GlassColors.text,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
