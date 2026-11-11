import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/locator.dart';
import '../services/panels_store.dart';
import '../services/weather_service.dart';
import '../widgets/g_button.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';

/// Panels: mini-dashboards. The weather panel is live (Open-Meteo, no key).
/// LLM-built panels arrive with tool calling.
class PanelsScreen extends StatefulWidget {
  const PanelsScreen({super.key});

  @override
  State<PanelsScreen> createState() => _PanelsScreenState();
}

class _PanelsScreenState extends State<PanelsScreen> {
  List<PanelSpec> _panels = [];
  Map<String, WeatherNow> _weather = {};

  @override
  void initState() {
    super.initState();
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
      // Weather is optional decoration; panel shows "unavailable".
    }
  }

  Future<void> _addManualPanel() async {
    final titleController = TextEditingController();
    final valueController = TextEditingController();
    final palette = paletteOf(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RadiusTokens.xl)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: Spacing.lg,
            right: Spacing.lg,
            top: Spacing.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New panel', style: TypeScale.title(color: palette.textPrimary)),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: titleController,
                style: TypeScale.body(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Title (e.g. Water the plants)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: valueController,
                style: TypeScale.body(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Value to show',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              GButton(
                label: 'Save panel',
                expands: true,
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isEmpty) return;
                  Locator.panels.save(PanelSpec(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: title,
                    kind: PanelKind.metric,
                    source: PanelSource.manual,
                    manualValue: valueController.text.trim(),
                    createdAt: DateTime.now().millisecondsSinceEpoch,
                  ));
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Screen(
      title: 'Panels',
      fab: FloatingActionButton(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        child: const Icon(Icons.add),
        onPressed: _addManualPanel,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        children: [
          GCard(
            child: Text(
              'Mini-dashboards. The weather panel is live; describe new panels '
              'in chat and gork builds them.',
              style: TypeScale.caption(color: palette.textSecondary),
            ),
          ),
          const SizedBox(height: Spacing.md),
          for (final panel in _panels)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: GCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(panel.title,
                              style: TypeScale.heading(
                                  color: palette.textPrimary)),
                        ),
                        if (panel.source == PanelSource.manual)
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 20, color: palette.error),
                            onPressed: () async {
                              await Locator.panels.delete(panel.id);
                              _refresh();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: Spacing.sm),
                    if (panel.source == PanelSource.weather)
                      _weatherContent(panel.id, palette)
                    else
                      Text(
                        panel.manualValue.isEmpty ? '—' : panel.manualValue,
                        style:
                            TypeScale.title(color: palette.textPrimary),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _weatherContent(String panelId, Palette palette) {
    final weather = _weather[panelId];
    if (weather == null) {
      return Text('Loading weather…',
          style: TypeScale.body(color: palette.textTertiary));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('${weather.tempC.toStringAsFixed(0)}°C',
            style: TypeScale.display(color: palette.primary)),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(weather.label,
                  style: TypeScale.body(color: palette.textPrimary)),
              Text('wind ${weather.windKmh.toStringAsFixed(0)} km/h',
                  style: TypeScale.caption(color: palette.textTertiary)),
            ],
          ),
        ),
        GButton(
          label: 'Refresh',
          variant: ButtonVariant.secondary,
          onPressed: () => _loadWeather(panelId),
        ),
      ],
    );
  }
}
