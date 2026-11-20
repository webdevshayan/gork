import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What a panel shows.
enum PanelKind { metric, list, graph, progress }

enum PanelSource { weather, manual, agent }

/// One panel card on the dashboards screen. Movement 69 — panels are
/// AI-authored: the agent replies with a ```gork-panel fenced JSON block
/// and the app harvests it into the Home feed. A human never fills a form
/// to create a widget; they just ask.
class PanelSpec {
  final String id;
  final String title;
  final PanelKind kind;
  final PanelSource source;
  final String manualValue;

  /// Graph panels: the series the AI wants plotted (sparkline).
  final List<double> series;

  /// Progress panels: 0..1.
  final double? progress;

  /// List panels: the items the AI seeded.
  final List<String> items;

  /// One line of context the AI can attach ("streak: 4 days").
  final String note;
  final int createdAt;

  const PanelSpec({
    required this.id,
    required this.title,
    required this.kind,
    required this.source,
    required this.manualValue,
    this.series = const [],
    this.progress,
    this.items = const [],
    this.note = '',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind.name,
        'source': source.name,
        'manualValue': manualValue,
        'series': series,
        'progress': progress,
        'items': items,
        'note': note,
        'createdAt': createdAt,
      };

  factory PanelSpec.fromJson(Map<String, dynamic> json) => PanelSpec(
        id: json['id'] as String,
        title: json['title'] as String,
        kind: PanelKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => PanelKind.metric,
        ),
        source: PanelSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => PanelSource.manual,
        ),
        manualValue: json['manualValue'] as String? ?? '',
        series: [
          for (final v in (json['series'] as List?) ?? const [])
            (v as num).toDouble(),
        ],
        progress: (json['progress'] as num?)?.toDouble(),
        items: [
          for (final v in (json['items'] as List?) ?? const []) v as String,
        ],
        note: json['note'] as String? ?? '',
        createdAt: json['createdAt'] as int,
      );

  /// Movement 69 — the AI's fenced JSON block becomes a panel. The agent
  /// only supplies the meaningful fields; ids and timestamps are minted
  /// here so the agent can't collide with existing panels.
  factory PanelSpec.fromAgent(Map<String, dynamic> json) {
    final title = (json['title'] as String? ?? 'Untitled panel').trim();
    String kindName = (json['kind'] as String? ?? 'stat').trim().toLowerCase();
    if (kindName == 'stat' || kindName == 'metric') kindName = 'metric';
    final kind = PanelKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => PanelKind.metric,
    );
    final value = json['value']?.toString() ?? '';
    final series = [
      for (final v in (json['series'] as List?) ?? const [])
        (v as num).toDouble(),
    ];
    final items = [
      for (final v in (json['items'] as List?) ?? const []) v.toString(),
    ];
    final progress = (json['progress'] as num?)?.toDouble().clamp(0.0, 1.0);
    // A graph with a series, a progress with a fraction, a list with items —
    // everything else renders as a stat.
    final PanelKind resolved = kind == PanelKind.graph && series.isNotEmpty
        ? PanelKind.graph
        : kind == PanelKind.progress && progress != null
            ? PanelKind.progress
            : kind == PanelKind.list && items.isNotEmpty
                ? PanelKind.list
                : PanelKind.metric;
    return PanelSpec(
      id: 'agent-${DateTime.now().millisecondsSinceEpoch}-$title.hashCode',
      title: title,
      kind: resolved,
      source: PanelSource.agent,
      manualValue: value,
      series: series,
      progress: progress,
      items: items,
      note: json['note']?.toString() ?? '',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

const PanelSpec kWeatherPanel = PanelSpec(
  id: 'weather-now',
  title: 'Weather now',
  kind: PanelKind.metric,
  source: PanelSource.weather,
  manualValue: '',
  createdAt: 0,
);

class PanelsStore {
  final SharedPreferences _prefs;

  PanelsStore(this._prefs);

  static const String _kKey = 'panels.items';

  List<PanelSpec> all() {
    final raw = _prefs.getString(_kKey);
    final list = raw == null || raw.isEmpty
        ? <PanelSpec>[]
        : [
            for (final e in jsonDecode(raw) as List)
              PanelSpec.fromJson(e as Map<String, dynamic>)
          ];
    // The built-in weather panel always exists (first movement of Panels).
    if (!list.any((p) => p.id == kWeatherPanel.id)) {
      list.insert(0, kWeatherPanel);
    }
    return list;
  }

  Future<void> _saveAll(List<PanelSpec> panels) async {
    await _prefs.setString(
        _kKey, jsonEncode([for (final p in panels) p.toJson()]));
  }

  Future<void> save(PanelSpec panel) async {
    final list = all()..removeWhere((p) => p.id == panel.id);
    list.add(panel);
    await _saveAll(list);
  }

  /// Movement 69 — an AI-harvested panel lands on the feed (front, so the
  /// newest widget is the first thing the user sees below the weather).
  Future<void> addSpec(PanelSpec panel) async {
    final list = all()..removeWhere((p) => p.id == panel.id);
    list.insert(list.indexWhere((p) => p.id == kWeatherPanel.id) + 1, panel);
    await _saveAll(list);
  }

  Future<void> delete(String id) async {
    final list = all()..removeWhere((p) => p.id == id);
    await _saveAll(list);
  }
}
