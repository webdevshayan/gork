import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/locator.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  Locator.bind(prefs: prefs);
  runApp(const GorkApp());
}
