import 'package:flutter/material.dart';

import '../services/locator.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/glass.dart';

/// Theme page from the reference: glass back button, centered title, and a
/// single glass card of radio rows (Auto / System / Light / Dark). The
/// choice persists and drives the ambient backdrop scrim.
class ThemePage extends StatefulWidget {
  const ThemePage({super.key});

  @override
  State<ThemePage> createState() => _ThemePageState();
}

class _ThemePageState extends State<ThemePage> {
  static const List<String> _modes = ['Auto', 'System', 'Light', 'Dark'];

  String get _current =>
      Locator.prefs.getString('ui.theme') ?? 'System';

  void _choose(String mode) {
    Locator.prefs.setString('ui.theme', mode);
    themeSetting.value = mode == 'Dark' ? 'Dark' : mode == 'Light' ? 'Light' : null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientBackdrop(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      GlassIconButton(
                        key: const ValueKey('theme-back'),
                        icon: Icons.u_turn_left,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Theme',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GlassContainer(
                    key: const ValueKey('theme-card'),
                    radius: 32,
                    opacity: 0.45,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (var i = 0; i < _modes.length; i++) ...[
                          if (i > 0) const Divider(color: Colors.black12, height: 1),
                          GlassMenuRow(
                            key: ValueKey('theme-${_modes[i].toLowerCase()}'),
                            label: _modes[i],
                            trailing: GlassRadio(
                              selected: _current == _modes[i],
                            ),
                            onTap: () => _choose(_modes[i]),
                          ),
                        ],
                      ],
                    ),
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
