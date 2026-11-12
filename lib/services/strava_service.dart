import 'package:http/http.dart' as http;

import 'integrations.dart';

/// Strava API v3 with an access token.
/// docs: developers.strava.com — bearer auth, plain JSON.
class StravaService {
  static const String base = 'https://www.strava.com/api/v3';

  final http.Client client;
  final Future<String?> Function() token;

  StravaService({required this.client, required this.token});

  Future<dynamic> _call(String method, String path,
      {Map<String, String>? query}) async {
    final t = await token();
    if (t == null || t.isEmpty) {
      throw const IntegrationException('Strava token missing — connect it in Integrations');
    }
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    return jsonRequest(client, method, uri, headers: {
      'Authorization': 'Bearer $t',
    });
  }

  /// Test connection: athlete's name.
  Future<String> whoAmI() async {
    final data = await _call('GET', '/athlete') as Map<String, dynamic>;
    final first = data['firstname'] as String? ?? '';
    final last = data['lastname'] as String? ?? '';
    return ('$first $last').trim().isEmpty
        ? 'athlete ${data['id']}'
        : '$first $last'.trim();
  }

  /// Recent activities, e.g. "Morning Ride — 21.4 km in 4820 s".
  Future<List<String>> recentActivities({int limit = 5}) async {
    final data = await _call('GET', '/athlete/activities',
        query: {'per_page': '$limit'}) as List;
    return [
      for (final raw in data.take(limit))
        _line(raw as Map<String, dynamic>)
    ];
  }

  String _line(Map<String, dynamic> a) {
    final name = a['name'] as String? ?? 'Activity';
    final distance = ((a['distance'] as num?) ?? 0) / 1000.0;
    final moving = (a['moving_time'] as num?) ?? 0;
    return '$name — ${distance.toStringAsFixed(1)} km in ${_hms(moving)}';
  }

  String _hms(num seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
