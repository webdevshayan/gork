import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// What a panel shows.
enum PanelKind { metric, list }

enum PanelSource { weather, manual }

/// One panel card on the dashboards screen.
class PanelSpec {
  final String id;
  final String title;
  final PanelKind kind;
  final PanelSource source;
  final String manualValue;
  final int createdAt;

  const PanelSpec({
    required this.id,
    required this.title,
    required this.kind,
    required this.source,
    required this.manualValue,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'kind': kind.name,
        'source': source.name,
        'manualValue': manualValue,
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
        createdAt: json['createdAt'] as int,
      );
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

  Future<void> delete(String id) async {
    final list = all()..removeWhere((p) => p.id == id);
    await _saveAll(list);
  }
}
