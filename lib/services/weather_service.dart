import 'dart:convert';
import 'dart:math' as math;

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

/// Local solar sunset time (NOAA approximation — pure math, no network).
/// Accurate to roughly ±2 minutes for mid latitudes.
DateTime sunsetFor(double lat, double lon, DateTime dateUtc) {
  double rad(double d) => d * math.pi / 180.0;
  double deg(double d) => d * 180.0 / math.pi;

  // Day-of-year.
  final int n = dateUtc.difference(DateTime(dateUtc.year)).inDays + 1;
  // Fractional year (radians).
  final double gamma = 2.0 * math.pi / 365.0 * (n - 1);
  // Equation of time (minutes) + declination (radians).
  final double eqTime =
      229.18 *
      (0.000075 +
          0.001868 * math.cos(gamma) -
          0.032077 * math.sin(gamma) -
          0.014615 * math.cos(2 * gamma) -
          0.040849 * math.sin(2 * gamma));
  final double decl =
      0.006918 -
      0.399912 * math.cos(gamma) +
      0.070257 * math.sin(gamma) -
      0.006758 * math.cos(2 * gamma) +
      0.000907 * math.sin(2 * gamma) -
      0.002697 * math.cos(3 * gamma) +
      0.00148 * math.sin(3 * gamma);

  // Hour angle for zenith 90.833 degrees (accounts for refraction + disc).
  final double latR = rad(lat);
  double cosOmega =
      math.cos(rad(90.8333)) / (math.cos(latR) * math.cos(decl)) -
      math.tan(latR) * math.tan(decl);
  if (cosOmega > 1) cosOmega = 1; // polar day -> sunset at solar noon
  if (cosOmega < -1) cosOmega = -1; // polar night
  final double omega = math.acos(cosOmega); // radians

  // Solar noon (minutes from UTC midnight) for this longitude.
  final double solarNoon = 720 - 4.0 * lon - eqTime;
  final double sunsetMinutes = solarNoon + 4.0 * deg(omega);
  return DateTime.utc(
    dateUtc.year,
    dateUtc.month,
    dateUtc.day,
  ).add(Duration(minutes: sunsetMinutes.round()));
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
