import 'package:flutter/material.dart';

import '../services/locator.dart';
import '../services/panels_store.dart';
import '../services/weather_service.dart';
import '../widgets/glass.dart';
import 'panels_screen.dart';
import '../constants/design_tokens.dart';

/// Home tab: live weather card (outer card + two full-width inner tiles:
/// conditions / sunset), a theme toggle (Movement 60 — the theme is
/// TOGGLEABLE again), the "Create a new panel" pill, then any manual
/// panels. No header — identity lives on the menu surface.
class GorkHome extends StatefulWidget {
  const GorkHome({super.key});

  @override
  State<GorkHome> createState() => _GorkHomeState();
}

class _GorkHomeState extends State<GorkHome> {
  WeatherNow? _weather;
  bool _weatherFailed = false;

  /// The persisted sunset override ('HH:mm'), set by tapping the tile.
  static const String kSunsetKey = 'home.sunset';

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

  /// Sunset tile value: the user's override when they edited it, otherwise
  /// computed locally from the coordinates (no network). Falls back to the
  /// reference copy when the clock data is unavailable.
  String get _sunsetLabel {
    final override = Locator.prefs.getString(kSunsetKey);
    if (override != null && override.isNotEmpty) return _formatTime(override);
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

  bool get _sunsetOverridden =>
      (Locator.prefs.getString(kSunsetKey) ?? '').isNotEmpty;

  /// Accepts '17:40', '5:40 PM', '5:40pm' … and normalizes to 'HH:mm'.
  String? _parseTime(String input) {
    final t = input.trim().toLowerCase();
    final ampm = RegExp(r'^(\d{1,2}):(\d{2})\s*(am|pm)$').firstMatch(t);
    if (ampm != null) {
      var h = int.parse(ampm.group(1)!);
      final m = int.parse(ampm.group(2)!);
      if (m > 59 || h < 1 || h > 12) return null;
      if (ampm.group(3) == 'pm' && h != 12) h += 12;
      if (ampm.group(3) == 'am' && h == 12) h = 0;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    final h24 = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
    if (h24 != null) {
      final h = int.parse(h24.group(1)!);
      final m = int.parse(h24.group(2)!);
      if (h > 23 || m > 59) return null;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    // Digits only — the datetime keyboard on Android is a NUMBER pad, so
    // '1740' (17:40) and '940' (9:40) must work without a colon.
    final digits = RegExp(r'^(\d{3,4})$').firstMatch(t);
    if (digits != null) {
      final raw = digits.group(1)!;
      final h = raw.length == 4
          ? int.parse(raw.substring(0, 2))
          : int.parse(raw.substring(0, 1));
      final m = raw.length == 4
          ? int.parse(raw.substring(2))
          : int.parse(raw.substring(1));
      if (h > 23 || m > 59) return null;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return null;
  }

  /// 'HH:mm' → 'h:MM AM/PM' for display.
  String _formatTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h > 23 || m > 59) return hhmm;
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$hour12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _editSunset(BuildContext context) async {
    final controller =
        TextEditingController(text: _sunsetLabel);
    String? error;
    final saved = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit sunset time'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('sunset-input'),
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.datetime,
                decoration: InputDecoration(
                  hintText: '5:40 PM, 17:40 or 1740',
                  border: const OutlineInputBorder(),
                ),
              ),
              // The error renders as its OWN wrapped text (never inside the
              // field's decorator): the decorator ellipsized it to one line
              // and the user could not read the accepted formats.
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  key: const ValueKey('sunset-error'),
                  maxLines: 3,
                  softWrap: true,
                  style: TextStyle(
                      fontSize: 12, color: GlassColors.danger),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Your edit is kept on this device and wins over the '
                'computed time.',
                style: TextStyle(
                    fontSize: 12, color: GlassColors.textDim),
              ),
            ],
          ),
          actions: [
            if (_sunsetOverridden)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('reset'),
                child: const Text('Use computed'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final parsed = _parseTime(controller.text);
                if (parsed == null) {
                  setDialogState(() => error =
                      'That is not a time — try 5:40 PM, 17:40 or 1740 '
                      '(hours and minutes, no colon needed).');
                  return;
                }
                Navigator.of(dialogContext).pop(parsed);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == null || saved == false) return;
    if (saved == 'reset') {
      await Locator.prefs.remove(kSunsetKey);
    } else if (saved is String) {
      await Locator.prefs.setString(kSunsetKey, saved);
    }
    if (mounted) setState(() {});
  }

  String get _conditionsLabel => _weather?.label ?? 'Broken Clouds';

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
          overridden: _sunsetOverridden,
          onEditSunset: () => _editSunset(context),
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

/// Reference weather panel: outer solid card (radius 28) with the location
/// header, and two inner solid tiles stacked vertically — full width
/// (Movement 60: the inner tiles stretch edge to edge inside the card).
/// The sunset tile is editable: tap it to set or reset the time.
class _WeatherCard extends StatelessWidget {
  const _WeatherCard({
    required this.weather,
    required this.failed,
    required this.onRetry,
    required this.conditions,
    required this.temp,
    required this.sunset,
    required this.overridden,
    required this.onEditSunset,
  });

  final WeatherNow? weather;
  final bool failed;
  final VoidCallback onRetry;
  final String conditions;
  final String temp;
  final String sunset;
  final bool overridden;
  final VoidCallback onEditSunset;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: failed ? onRetry : null,
      child: GlassContainer(
        radius: 28,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_outlined,
                  size: 20,
                  color: GlassColors.text,
                ),
                const SizedBox(width: 10),
                Text(
                  Locator.locationLabel,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: GlassColors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GlassContainer(
              key: const ValueKey('weather-conditions-tile'),
              radius: 24,
              strong: true,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conditions,
                    style: TextStyle(
                      fontSize: 16,
                      color: GlassColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    temp,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w500,
                      color: GlassColors.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onEditSunset,
              child: GlassContainer(
                key: const ValueKey('weather-sunset-tile'),
                radius: 24,
                strong: true,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Sunset',
                          style: TextStyle(
                              fontSize: 16, color: GlassColors.textDim),
                        ),
                        const Spacer(),
                        Icon(
                          overridden
                              ? Icons.edit
                              : Icons.edit_outlined,
                          size: 16,
                          color: GlassColors.textFaint,
                          semanticLabel: 'Edit sunset time',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sunset,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w500,
                        color: GlassColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Full-width pill: "+ Create a new panel".
class _CreatePanelButton extends StatelessWidget {
  const _CreatePanelButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: 30,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 20, color: GlassColors.text),
            SizedBox(width: 10),
            Text(
              'Create a new panel',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: GlassColors.text,
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: GlassColors.text,
                  ),
                ),
                if (panel.manualValue.isNotEmpty)
                  Text(
                    panel.manualValue,
                    style: TextStyle(fontSize: 14, color: GlassColors.textDim),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: GlassColors.textDim),
        ],
      ),
    );
  }
}
