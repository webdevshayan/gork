import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:gork/services/weather_service.dart';

void main() {
  test('parses Open-Meteo current weather', () async {
    final service = WeatherService(MockClient((request) async {
      expect(request.url.host, 'api.open-meteo.com');
      expect(request.url.queryParameters['latitude'], '24.8607');
      expect(request.url.queryParameters['current'],
          'temperature_2m,weather_code,wind_speed_10m');
      return http.Response(
        jsonEncode({
          'current': {
            'temperature_2m': 31.2,
            'weather_code': 2,
            'wind_speed_10m': 14.8,
          }
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }));

    final weather = await service.fetch(lat: 24.8607, lon: 67.0011);
    expect(weather.tempC, 31.2);
    expect(weather.code, 2);
    expect(weather.label, 'Partly cloudy');
    expect(weather.isWet, isFalse);
  });

  test('wet codes flag isWet', () {
    expect(const WeatherNow(20, 61, 10).isWet, isTrue);
    expect(const WeatherNow(20, 80, 10).isWet, isTrue);
    expect(const WeatherNow(20, 95, 10).isWet, isTrue);
    expect(const WeatherNow(20, 0, 10).isWet, isFalse);
    expect(const WeatherNow(20, 45, 10).label, 'Fog');
    expect(const WeatherNow(20, 71, 10).label, 'Snow');
  });

  test('non-200 throws', () async {
    final service = WeatherService(
        MockClient((request) async => http.Response('', 503)));
    expect(() => service.fetch(lat: 1, lon: 1), throwsException);
  });
}
