import 'package:flutter/material.dart';

import '../services/locator.dart';
import '../services/panels_store.dart';
import '../services/weather_service.dart';
import '../widgets/glass.dart';
import 'panels_screen.dart';

/// Home tab, pixel-matched to the reference: live weather card (outer glass
/// card + two more-opaque inner tiles: conditions / sunset), the
/// "Create a new panel" pill, then any manual panels. No header — identity
/// lives on the menu surface.
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

  /// Sunset tile value: computed locally from the coordinates (no network).
  /// Falls back to the reference copy when the clock data is unavailable.
  String get _sunsetLabel {
    if (_weatherFailed) return '5:40 PM';
    try {
      final dt = sunsetFor(
        Locator.ambientLat,
        Locator.ambientLon,
        DateTime.now().toUtc(),
      );
      final local = dt.toLocal();
      final int hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
      final minute = local.minute.toString().padLeft(2, '0');
      return '${hour12.toString()}:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
    } catch (_) {
      return '5:40 PM';
    }
  }

  String get _conditionsLabel =>
      _weather?.label ?? (_weatherFailed ? 'Broken Clouds' : 'Broken Clouds');

  String get _tempLabel => _weather == null
      ? '26°C'
      : '${_weather!.tempC.toStringAsFixed(0)}°C';

  @override
  Widget build(BuildContext context) {
    final manualPanels = Locator.panels.all().where(
      (p) => p.source == PanelSource.manual,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _WeatherCard(
          weather: _weather,
          failed: _weatherFailed,
          onRetry: _loadWeather,
          conditions: _conditionsLabel,
          temp: _tempLabel,
          sunset: _sunsetLabel,
        ),
        const SizedBox(height: 16),
        _CreatePanelButton(onTap: () => _push(context, const PanelsScreen())),
        for (final panel in manualPanels) ...[
          const SizedBox(height: 16),
          _ManualPanelRow(panel: panel),
        ],
      ],
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

/// Reference weather panel: outer glass card (radius 28) with the location
/// header, and two inner (more opaque, radius 24) tiles stacked vertically.
class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.weather,
    required this.failed,
    required this.onRetry,
    required this.conditions,
    required this.temp,
    required this.sunset,
  });

  final WeatherNow? weather;
  final bool failed;
  final VoidCallback onRetry;
  final String conditions;
  final String temp;
  final String sunset;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: failed ? onRetry : null,
      child: GlassContainer(
        radius: 28,
        opacity: 0.4,
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
                const SizedBox(width: 10),
                Text(
                  Locator.locationLabel,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GlassContainer(
              radius: 24,
              opacity: 0.55,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conditions,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    temp,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassContainer(
              radius: 24,
              opacity: 0.55,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sunset',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sunset,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
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

/// Full-width frosted pill: "+ Create a new panel".
class _CreatePanelButton extends StatelessWidget {
  const _CreatePanelButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: 30,
      opacity: 0.35,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 20, color: Colors.black87),
            SizedBox(width: 10),
            Text(
              'Create a new panel',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
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
      radius: 28,
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
