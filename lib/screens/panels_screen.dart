import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/locator.dart';
import '../services/panels_store.dart';
import '../services/weather_service.dart';
import '../widgets/screen.dart';
import '../widgets/glass.dart';
import '../widgets/panel_view.dart';

/// Movement 69 — Panels are AI-authored, never hand-filled. The agent
/// replies with a ```gork-panel fenced JSON block and the widget lands on
/// this feed: stats, sparkline graphs, progress bars and lists — study
/// streaks, shipped PRs, topics to read today, whatever the user's life
/// needs. This screen renders the feed and offers per-role starter prompts
/// (student, farmer, freelancer, hotel owner…) that ask the AI to BUILD the
/// widgets — there is no manual form anywhere.
class PanelsScreen extends StatefulWidget {
  const PanelsScreen({super.key});

  @override
  State<PanelsScreen> createState() => _PanelsScreenState();
}

class _PanelsScreenState extends State<PanelsScreen> {
  List<PanelSpec> _panels = [];
  Map<String, WeatherNow> _weather = {};

  /// The role the feed is tuned for — remembered, shown as the active chip.
  String _role = 'everyone';

  static const List<String> kRoles = [
    'everyone',
    'student',
    'teacher',
    'software engineer',
    'web developer',
    'mobile developer',
    'freelancer',
    'farmer',
    'hotel owner',
    'restaurant owner',
    'shop owner',
    'parent',
    'athlete',
  ];

  @override
  void initState() {
    super.initState();
    _role = Locator.prefs.getString('panels.role') ?? 'everyone';
    _refresh();
  }

  void _refresh() {
    setState(() => _panels = Locator.panels.all());
    for (final p in _panels.where((p) => p.source == PanelSource.weather)) {
      _loadWeather(p.id);
    }
  }

  Future<void> _loadWeather(String panelId) async {
    try {
      final weather = await Locator.weather.fetch(
        lat: Locator.ambientLat,
        lon: Locator.ambientLon,
      );
      if (mounted) {
        setState(() => _weather[panelId] = weather);
      }
    } catch (_) {
      // Weather is optional decoration; panel shows the cached value.
    }
  }

  /// A role chip was picked: remember it — the feed is tuned for that life.
  /// The widgets themselves are built by gork in chat (the user asks once
  /// and the reply's gork-panel blocks land on the feed automatically).
  Future<void> _pickRole(String role) async {
    await Locator.prefs.setString('panels.role', role);
    setState(() => _role = role);
    if (role == 'everyone' || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Feed tuned for a $role — ask gork in chat: '
            '"rebuild my feed for a $role" and the widgets land here.')));
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Screen(
      title: 'Panels',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: Text(
              'Every widget here was built by gork — ask in chat for more, '
              'or tune the feed for your work and life below.',
              style: TypeScale.body(color: palette.textSecondary),
            ),
          ),
          const SizedBox(height: Spacing.md),
          // Role chips — the feed is customizable for every kind of person.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in kRoles)
                  _RoleChip(
                    label: role,
                    active: role == _role,
                    onTap: () => _pickRole(role),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),
          if (_panels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Text(
                'No panels yet. Ask gork in chat — "build me a widget for '
                'my study streak" — and it appears here.',
                style: TypeScale.body(color: palette.textTertiary),
              ),
            )
          else
            for (final panel in _panels)
              PanelTile(
                panel: panel,
                weather: panel.source == PanelSource.weather
                    ? _weather[panel.id]
                    : null,
                onWeatherRefresh: panel.source == PanelSource.weather
                    ? () => _loadWeather(panel.id)
                    : null,
                onDelete: panel.source == PanelSource.agent
                    ? () async {
                        await Locator.panels.delete(panel.id);
                        _refresh();
                      }
                    : null,
              ),
        ],
      ),
    );
  }
}

/// The role chip: plain pill, ink when active — no color, the Movement 59
/// language.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? palette.primary : GlassColors.fill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? palette.primary : GlassColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? palette.onPrimary : palette.textPrimary,
          ),
        ),
      ),
    );
  }
}
