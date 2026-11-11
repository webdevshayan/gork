import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/locator.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  Locator.bind(prefs: prefs);
  runApp(const GorkApp());

  // Notifications + periodic scheduler tick (while the app is alive).
  Locator.notifications.init();
  Timer.periodic(const Duration(minutes: 1), (_) {
    try {
      Locator.scheduler.tick(DateTime.now());
    } catch (_) {}
  });
}
