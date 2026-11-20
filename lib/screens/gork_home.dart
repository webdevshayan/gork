import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/locator.dart';
import '../services/panels_store.dart';
import '../services/weather_service.dart';
import '../widgets/glass.dart';
import '../widgets/panel_view.dart';
import 'panels_screen.dart';
import '../constants/design_tokens.dart';

/// Movement 69 — the Home feed. Instant by design:
///  * the CLOCK ticks from the first frame (a live timer, no async gap);
///  * the TEMPERATURE renders from the persisted cache the moment the
///    widget builds — the network only REFINES it, never gates it;
///  * every panel the AI has authored lands here, not just manual ones.
/// The layout is flat: one bordered weather block with hairline dividers
/// instead of the old card-in-card-in-card stack.
class GorkHome extends StatefulWidget {
  const GorkHome({super.key});

  @override
  State<GorkHome> createState() => _GorkHomeState();
}

class _GorkHomeState extends State<GorkHome> {
  WeatherNow? _weather;

  /// True only when we have neither cache nor network — the honest '—' state.
  bool _weatherFailed = false;
  Timer? _clock;
  DateTime _now = DateTime.now();

  /// The persisted sunset override ('HH:mm'), set by tapping the tile.
  static const String kSunsetKey = 'home.sunset';
  static const String kCacheKey = 'home.weather.cache';

  @override
  void initState() {
    super.initState();
    _loadCachedWeather();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _loadWeather();
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  /// Cached-first: the last fetched conditions render instantly on the
  /// first frame — no '26°C' placeholder pretending to be data.
  void _loadCachedWeather() {
    final raw = Locator.prefs.getString(kCacheKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _weather = WeatherNow(
          (map['tempC'] as num).toDouble(),
          (map['code'] as num?)?.toInt() ?? 0,
          (map['windKmh'] as num?)?.toDouble() ?? 0,
        );
      });
    } catch (_) {
      // A corrupt cache is the same as no cache.
    }
  }

  Future<void> _loadWeather() async {
    try {
      final weather = await Locator.weather.fetch(
        lat: Locator.ambientLat,
        lon: Locator.ambientLon,
      );
      if (!mounted) return;
      setState(() {
        _weather = weather;
        _weatherFailed = false;
      });
      await Locator.prefs.setString(
          kCacheKey,
          jsonEncode({
            'tempC': weather.tempC,
            'code': weather.code,
            'windKmh': weather.windKmh,
          }));
    } catch (_) {
      if (!mounted) return;
      // Only mark failed when there was never anything to show.
      setState(() => _weatherFailed = _weather == null);
    }
  }

  /// Sunset tile value: the user's override when they edited it, otherwise
  /// computed locally from the coordinates (no network).
  String get _sunsetLabel {
    final override = Locator.prefs.getString(kSunsetKey);
    if (override != null && override.isNotEmpty) return _formatTime(override);
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
      return '—';
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

  /// The live clock label — h:mm AM/PM, ticking, INSTANT (no async load).
  String get _clockLabel {
    final int h12 = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final String min = _now.minute.toString().padLeft(2, '0');
    return '$h12:$min ${_now.hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _editSunset(BuildContext context) async {
    final controller =
        TextEditingController(text: _sunsetLabel);
    String? error;
    final saved = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: GlassColors.fill,
          title: const Text('Edit sunset time'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('sunset-input'),
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.text,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9:apmAPM\s]')),
                ],
                decoration: InputDecoration(
                  hintText: '5:40 PM, 17:40 or 1740',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  key: const ValueKey('sunset-error'),
                  maxLines: 3,
                  softWrap: true,
                  style: TextStyle(
                      fontSize: 13, color: GlassColors.danger),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Your edit is kept on this device and wins over the '
                'computed time.',
                style: TextStyle(
                    fontSize: 13, color: GlassColors.textDim),
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

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final feedPanels = Locator.panels
        .all()
        .where((p) => p.id != 'weather-now' && p.source != PanelSource.manual)
        .toList();
    return RefreshIndicator(
      color: palette.primary,
      backgroundColor: GlassColors.fill,
      onRefresh: _loadWeather,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // One flat block: location + live clock, then hairline-separated
          // rows for conditions / temperature / sunset.
          Container(
            decoration: BoxDecoration(
              color: GlassColors.fill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: GlassColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          Locator.locationLabel,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            color: GlassColors.text,
                          ),
                        ),
                      ),
                      Icon(Icons.schedule,
                          size: 18, color: GlassColors.textDim),
                      const SizedBox(width: 8),
                      Text(
                        _clockLabel,
                        key: const ValueKey('home-clock'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: GlassColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: GlassColors.divider, height: 1),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _weatherFailed ? _loadWeather : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          // The cached temperature — INSTANT, honest when
                          // nothing was ever fetched ('—', never a fake 26).
                          _weather == null
                              ? '—'
                              : '${_weather!.tempC.toStringAsFixed(0)}°C',
                          key: const ValueKey('home-temp'),
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w500,
                            color: GlassColors.text,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _weather == null
                                    ? (_weatherFailed
                                        ? 'Weather unavailable — tap to retry'
                                        : 'Loading…')
                                    : _weather!.label,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: GlassColors.textDim,
                                ),
                              ),
                              if (_weather != null)
                                Text(
                                  'wind ${_weather!.windKmh.toStringAsFixed(0)} km/h',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: GlassColors.textFaint,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_weatherFailed)
                          Icon(Icons.refresh,
                              size: 22, color: GlassColors.textDim),
                      ],
                    ),
                  ),
                ),
                Divider(color: GlassColors.divider, height: 1),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _editSunset(context),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sunset',
                              style: TextStyle(
                                  fontSize: 15, color: GlassColors.textDim),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _sunsetLabel,
                              key: const ValueKey('weather-sunset-tile'),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w500,
                                color: GlassColors.text,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: GlassColors.textFaint,
                          semanticLabel: 'Edit sunset time',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // The AI-built feed: every panel gork has authored for this user.
          if (feedPanels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                'Your feed is yours. Ask gork in chat — "build me a widget '
                'for my study streak" or "track my shipped PRs" — and the '
                'widget lands right here. Tune it for your role on the '
                'Panels screen.',
                style: TextStyle(
                    fontSize: 15, height: 1.45, color: GlassColors.textDim),
              ),
            )
          else
            for (final panel in feedPanels)
              PanelTile(
                panel: panel,
                compact: true,
                weather: panel.source == PanelSource.weather
                    ? _weather
                    : null,
                onDelete: panel.source == PanelSource.agent
                    ? () async {
                        await Locator.panels.delete(panel.id);
                        if (mounted) setState(() {});
                      }
                    : null,
              ),
          const SizedBox(height: 8),
          GlassContainer(
            radius: 30,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _push(context, const PanelsScreen()),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.dashboard_customize_outlined,
                        size: 20, color: GlassColors.text),
                    const SizedBox(width: 10),
                    Text(
                      'Customize feed',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: GlassColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}
