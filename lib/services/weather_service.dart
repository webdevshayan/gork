import 'dart:convert';

import 'package:http/http.dart' as http;

/// Weather via Open-Meteo — free, no API key, no account.
class WeatherNow {
  final double tempC;
  final int code;
  final double windKmh;

  const WeatherNow(this.tempC, this.code, this.windKmh);

  String get label {
    if (code == 0) return 'Clear sky';
    if (code >= 1 && code <= 3) return 'Partly cloudy';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Showers';
    if (code >= 95) return 'Thunderstorm';
    return 'Cloudy';
  }

  bool get isWet =>
      (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95;
}

class WeatherService {
  final http.Client _http;

  WeatherService([http.Client? client]) : _http = client ?? http.Client();

  Future<WeatherNow> fetch({required double lat, required double lon}) async {
    final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,weather_code,wind_speed_10m');
    final response = await _http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('Open-Meteo HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>;
    return WeatherNow(
      (current['temperature_2m'] as num).toDouble(),
      (current['weather_code'] as num).toInt(),
      (current['wind_speed_10m'] as num).toDouble(),
    );
  }
}
