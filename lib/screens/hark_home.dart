import 'package:flutter/material.dart';

import '../services/locator.dart';
import '../services/panels_store.dart';
import '../services/weather_service.dart';
import '../widgets/glass.dart';
import 'cloud_computer_screen.dart';
import 'inbox_screen.dart';
import 'integrations_screen.dart';
import 'panels_screen.dart';
import 'projects_screen.dart';
import 'providers_screen.dart';
import 'tasks_screen.dart';
import 'vault_screen.dart';

/// Home tab: identity header, live weather panel, "Create a new panel" and
/// quick access to everything else — all floating on the ambient backdrop.
class HarkHome extends StatefulWidget {
  const HarkHome({super.key});

  @override
  State<HarkHome> createState() => _HarkHomeState();
}

class _HarkHomeState extends State<HarkHome> {
  WeatherNow? _weather;
  bool _weatherFailed = false;

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    try {
      final weather = await Locator.weather.fetch(
        lat: Locator.ambientLat,
        lon: Locator.ambientLon,
      );
      if (mounted) setState(() => _weather = weather);
    } catch (_) {
      if (mounted) setState(() => _weatherFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manualPanels = Locator.panels.all().where(
      (p) => p.source == PanelSource.manual,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Shayan Ali Jalb',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'shayanalibuilds@gmail.com',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        _WeatherCard(
          weather: _weather,
          failed: _weatherFailed,
          onRetry: _loadWeather,
        ),
        const SizedBox(height: 8),
        _CreatePanelButton(onTap: () => _push(context, const PanelsScreen())),
        for (final panel in manualPanels) ...[
          const SizedBox(height: 8),
          _ManualPanelRow(panel: panel),
        ],
        const SizedBox(height: 16),
        const Text(
          'Quick access',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 8),
        _HomeTile(
          icon: Icons.inbox_outlined,
          label: 'Inbox',
          subtitle: 'Proactive suggestions with one-tap actions',
          onTap: () => _push(context, const InboxScreen()),
        ),
        _HomeTile(
          icon: Icons.schedule_outlined,
          label: 'Tasks',
          subtitle: 'Timed jobs the assistant runs for you',
          onTap: () => _push(context, const TasksScreen()),
        ),
        _HomeTile(
          icon: Icons.folder_outlined,
          label: 'Projects',
          subtitle: 'Workspaces with notes and files',
          onTap: () => _push(context, const ProjectsScreen()),
        ),
        _HomeTile(
          icon: Icons.lock_outline,
          label: 'Vault',
          subtitle: 'Encrypted secrets, stored only on this phone',
          onTap: () => _push(context, const VaultScreen()),
        ),
        _HomeTile(
          icon: Icons.dashboard_outlined,
          label: 'Panels',
          subtitle: 'Mini-dashboards, starting with live weather',
          onTap: () => _push(context, const PanelsScreen()),
        ),
        _HomeTile(
          icon: Icons.dns_outlined,
          label: 'Cloud Computer',
          subtitle: 'Self-hosted or free-tier browser agent backend',
          onTap: () => _push(context, const CloudComputerScreen()),
        ),
        _HomeTile(
          icon: Icons.extension_outlined,
          label: 'Integrations',
          subtitle: 'GitHub, Slack, Strava, Spotify, Gmail, PayPal',
          onTap: () => _push(context, const IntegrationsScreen()),
        ),
        _HomeTile(
          icon: Icons.key_outlined,
          label: 'Providers',
          subtitle: 'Bring your own API keys (BYOK)',
          onTap: () => _push(context, const ProvidersScreen()),
        ),
      ],
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

/// Spec weather panel: outer glass card with location, inner (more opaque)
/// glass card with conditions + sunset. Live data when reachable; the spec
/// copy is the offline fallback.
class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.weather,
    required this.failed,
    required this.onRetry,
  });

  final WeatherNow? weather;
  final bool failed;
  final VoidCallback onRetry;

  String get _conditions {
    if (weather == null) return 'Broken Clouds, 26°C';
    return '${weather!.label}, ${weather!.tempC.toStringAsFixed(0)}°C';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: failed ? onRetry : null,
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.cloud_outlined,
                  size: 20,
                  color: Colors.black87,
                ),
                const SizedBox(width: 8),
                Text(
                  Locator.locationLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GlassContainer(
              radius: 12,
              opacity: 0.4,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _conditions,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Text(
                    'Sunset, 5:40 PM',
                    style: TextStyle(
                      fontSize: 14,
                      color: failed ? Colors.black54 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatePanelButton extends StatelessWidget {
  const _CreatePanelButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: 30,
      opacity: 0.35,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.add, size: 18, color: Colors.black87),
            SizedBox(width: 8),
            Text(
              'Create a new panel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualPanelRow extends StatelessWidget {
  const _ManualPanelRow({required this.panel});

  final PanelSpec panel;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  panel.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                if (panel.manualValue.isNotEmpty)
                  Text(
                    panel.manualValue,
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: Colors.black54),
        ],
      ),
    );
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            children: [
              Icon(icon, size: 20, color: Colors.black87),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }
}
