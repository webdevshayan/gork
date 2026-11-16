import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants/ambient.dart';
import 'services/locator.dart';

import 'app.dart';
import 'services/profile_info.dart';
import 'widgets/ambient_backdrop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  Locator.bind(prefs: prefs);
  await initProfilePhoto();
  initProfile();
  initTheme();
  runApp(const GorkApp());

  // Notifications + periodic scheduler tick (while the app is alive).
  Locator.notifications.init();
  Timer.periodic(const Duration(minutes: 1), (_) {
    try {
      Locator.scheduler.tick(DateTime.now());
    } catch (_) {}
  });

  // Ambient (Movement 57): fetch the weather NOW — the first palette is
  // already weather-correct instead of waiting a full timer cycle — then
  // keep phase and weather fresh every 5 minutes. The tick only nudges the
  // controller; the app shell recomputes phase (solar, at the user's
  // location) and palette on each nudge.
  Future<void> ambientTick() async {
    ambient.refresh();
    try {
      final weather = await Locator.weather.fetch(
        lat: Locator.ambientLat,
        lon: Locator.ambientLon,
      );
      ambient.wetWeather = weather.isWet;
      ambient.weatherCode = weather.code;
      ambient.tempC = weather.tempC;
    } catch (_) {
      // Offline: the palette keeps its last known weather (clear default).
    }
  }

  unawaited(ambientTick());
  Timer.periodic(const Duration(minutes: 5), (_) => unawaited(ambientTick()));
}
