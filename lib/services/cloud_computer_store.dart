import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The three free cloud-computer backends we support.
enum CloudBackend { agentvps, browseruse, openbrowse }

extension CloudBackendX on CloudBackend {
  String get id => switch (this) {
        CloudBackend.agentvps => 'agentvps',
        CloudBackend.browseruse => 'browseruse',
        CloudBackend.openbrowse => 'openbrowse',
      };
  String get label => switch (this) {
        CloudBackend.agentvps => 'AgentVPS (self-hosted)',
        CloudBackend.browseruse => 'Browser Use Cloud',
        CloudBackend.openbrowse => 'openbrowse (self-hosted)',
      };
  String get blurb => switch (this) {
        CloudBackend.agentvps =>
          'Open-source agent on your own VPS. Zero limits, you own the machine.',
        CloudBackend.browseruse =>
          'Managed cloud browsers. Free tier: 3 concurrent browsers, no card.',
        CloudBackend.openbrowse =>
          'Open-source browser agent. Paste the endpoint URL of your instance.',
      };
}

CloudBackend? backendFromId(String? id) {
  for (final b in CloudBackend.values) {
    if (b.id == id) return b;
  }
  return null;
}

/// User's chosen cloud computer configuration.
class CloudComputerConfig {
  final CloudBackend backend;
  final String endpoint;
  final String apiKey;
  final int updatedAt;

  const CloudComputerConfig({
    required this.backend,
    required this.endpoint,
    required this.apiKey,
    required this.updatedAt,
  });

  CloudComputerConfig copyWith({String? endpoint, String? apiKey, int? updatedAt}) =>
      CloudComputerConfig(
        backend: backend,
        endpoint: endpoint ?? this.endpoint,
        apiKey: apiKey ?? this.apiKey,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'backend': backend.id,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'updatedAt': updatedAt,
      };

  factory CloudComputerConfig.fromJson(Map<String, dynamic> json) =>
      CloudComputerConfig(
        backend: backendFromId(json['backend'] as String?) ?? CloudBackend.agentvps,
        endpoint: json['endpoint'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        updatedAt: json['updatedAt'] as int? ?? 0,
      );

  bool get needsEndpoint => backend != CloudBackend.browseruse;
  bool get needsApiKey => backend != CloudBackend.openbrowse;

  bool get isConfigured =>
      (!needsEndpoint || endpoint.isNotEmpty) &&
      (!needsApiKey || apiKey.isNotEmpty);
}

class CloudComputerStore {
  final SharedPreferences _prefs;

  CloudComputerStore(this._prefs);

  static const String _kKey = 'cloudcomputer.config';

  CloudComputerConfig load() {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) {
      return CloudComputerConfig(
          backend: CloudBackend.agentvps, endpoint: '', apiKey: '', updatedAt: 0);
    }
    return CloudComputerConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(CloudComputerConfig config) async {
    await _prefs.setString(_kKey, jsonEncode(config.toJson()));
  }
}

/// Health ping for self-hosted endpoints (AgentVPS / openbrowse both expose
/// GET /health on the gork daemon). Returns null on success, error otherwise.
Future<String?> pingCloudComputer(
    CloudComputerConfig config, http.Client client) async {
  if (config.backend == CloudBackend.browseruse) {
    // Browser Use has no public health endpoint we can call for free without
    // burning session quota; key presence is our readiness check for now.
    return config.apiKey.isEmpty ? 'No API key saved.' : null;
  }
  if (config.endpoint.isEmpty) {
    return 'No endpoint saved.';
  }
  try {
    final uri = Uri.parse(
        config.endpoint.endsWith('/') ? config.endpoint : '${config.endpoint}/');
    final response = await client
        .get(uri.resolve('health'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final body = response.body;
      if (body.contains('ok') || body.contains('status')) {
        return null;
      }
      return 'Unexpected response: $body';
    }
    return 'HTTP ${response.statusCode}';
  } catch (e) {
    return e.toString();
  }
}
