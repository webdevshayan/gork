import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications. All errors are swallowed:
/// notifications must never crash the app.
///
/// Movement 64 — reply notifications got honest:
///   * suppressed while the user is IN the chat (the answer is already in
///     the thread when they look up) — the flag is [inChat];
///   * a dedicated channel + sequential ids and timestamps, so multiple
///     replies arrange in the order the conversation produced them
///     (previously random ids made the shade order random).
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Whether the chat surface is currently in front of the user. The chat
  /// screen sets it true on init and false on dispose; the shell also
  /// clears it whenever the menu surface covers the app.
  bool inChat = false;

  /// Monotonic counter — stable, unique ids AND ascending timestamps so
  /// Android orders the shade exactly in reply order.
  int _seq = 0;

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

  /// Scheduled-task results — the original channel, unchanged.
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

  /// A chat reply finished on the VPS. [stagger] positions the reply in
  /// the conversation: reply 0 of a burst is the oldest, each next one
  /// newer — the shade reads exactly in thread order, every time.
  Future<void> showReply(String title, String body, {int stagger = 0}) async {
    if (inChat) return; // the user is looking at the thread already
    try {
      await init();
      _seq++;
      final now = DateTime.now().millisecondsSinceEpoch;
      // Same-millisecond bursts would sort randomly — spread them so the
      // FIRST reply of a burst is the OLDEST and the last one sits newest.
      final when = now - (stagger * 1000);
      await _plugin.show(
        _seq % 2147483647,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'gork_replies',
            'gork replies',
            channelDescription:
                'Answers that finished on your VPS while you were away',
            importance: Importance.max,
            priority: Priority.high,
            groupKey: 'gork_replies',
            when: when,
            whenShown: false,
          ),
        ),
      );
    } catch (_) {}
  }
}
