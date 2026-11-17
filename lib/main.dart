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
  runApp(const GorkApp());

  // Notifications + periodic scheduler tick (while the app is alive).
  Locator.notifications.init();
  Timer.periodic(const Duration(minutes: 1), (_) {
    try {
      Locator.scheduler.tick(DateTime.now());
    } catch (_) {}
  });

  // Ambient (Movement 59): the ONLY theme mode is auto — light by day,
  // dark by night. The nudge every minute re-resolves the sun (or the
  // clock), so the app flips light ⇄ dark "after some time" with no user
  // action and no weather fetch. The weather card fetches on its own.
  Timer.periodic(
      const Duration(minutes: 1), (_) => ambient.refresh());
}
