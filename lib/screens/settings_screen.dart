import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../constants/version.dart';
import '../services/locator.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/g_button.dart';
import '../widgets/glass.dart';
import '../widgets/screen.dart';
import "../constants/ambient.dart";
import "updates_screen.dart";

/// Settings — ONE page with two tabs:
///
///   Preferences  the user's choices: the THEME lives here now (moved off
///                Home in Movement 62 — Home is the weather/panels surface,
///                settings belong in settings).
///   About        what this build is (version) and where updates come from.
///
/// The theme choice is the SAME pref the Home toggle wrote ('ui.theme'), so
/// a choice made in an older app version carries over untouched.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _preferences = true;

  static const String kThemeKey = 'ui.theme';

  String get _themeChoice => Locator.prefs.getString(kThemeKey) ?? 'auto';

  Future<void> _setTheme(String mode) async {
    await Locator.prefs.setString(kThemeKey, mode);
    // The app shell listens to the ambient version — nudge it so the new
    // choice rebuilds MaterialApp, the glass colors and the backdrop.
    ambient.refresh();
    if (mounted) setState(() {});
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Screen(
      title: 'Settings',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsTabs(
            preferences: _preferences,
            onPick: (v) => setState(() => _preferences = v),
          ),
          const SizedBox(height: 16),
          if (_preferences) ...[
            _ThemeCard(choice: _themeChoice, onPick: _setTheme),
            const SizedBox(height: 16),
            GlassContainer(
              radius: 28,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Background responses',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: GlassColors.text)),
                  const SizedBox(height: 8),
                  Text(
                    'Messages you send run on YOUR VPS — the phone can die, '
                    'the app can close, the answer still completes there '
                    'and arrives as a notification when you are back.',
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: GlassColors.textDim),
                  ),
                ],
              ),
            ),
          ] else ...[
            GlassContainer(
              radius: 28,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('gork v$kAppVersion',
                      key: const ValueKey('settings-version'),
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: GlassColors.text)),
                  const SizedBox(height: 8),
                  Text(
                    'Install over any earlier version — settings, keys, '
                    'tasks and the vault are kept.',
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: GlassColors.textDim),
                  ),
                  const SizedBox(height: 12),
                  GButton(
                    key: const ValueKey('settings-updates'),
                    label: 'Check for updates',
                    variant: ButtonVariant.secondary,
                    expands: true,
                    onPressed: () => _push(context, const UpdatesScreen()),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The two-tab header: Preferences | About. Solid chips, gray & black —
/// Movement 59/60 language, no color.
class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs({required this.preferences, required this.onPick});

  final bool preferences;
  final void Function(bool) onPick;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool active, VoidCallback onTap,
        {String? testKey}) {
      return Expanded(
        child: GestureDetector(
          key: testKey == null ? null : ValueKey(testKey),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: active ? GlassColors.chip : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? GlassColors.textOnChip
                          : GlassColors.textDim)),
            ),
          ),
        ),
      );
    }

    return GlassContainer(
      radius: 28,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          tab('Preferences', preferences, () => onPick(true),
              testKey: 'settings-tab-preferences'),
          const SizedBox(width: 8),
          tab('About', !preferences, () => onPick(false),
              testKey: 'settings-tab-about'),
        ],
      ),
    );
  }
}

/// The theme picker, moved off Home (Movement 62). Same keys, same behavior:
/// Auto (the sun decides), Light or Dark — persisted in 'ui.theme'.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.choice, required this.onPick});

  final String choice;
  final void Function(String mode) onPick;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
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
                child: Text('Theme',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: GlassColors.text)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Auto follows the sun (light by day, dark by night). Your choice '
            'wins over the sun until you switch back.',
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
                      onTap: () => onPick(option.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: choice == option.$1
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
                              color: choice == option.$1
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
                                  color: choice == option.$1
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
    );
  }
}
