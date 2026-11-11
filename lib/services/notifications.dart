import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications. All errors are swallowed:
/// notifications must never crash the app.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings);
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
    _ready = true;
  }

  Future<void> show(String title, String body) async {
    try {
      await init();
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'gork_tasks',
            'gork tasks',
            channelDescription: 'Results of scheduled tasks',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }
}
