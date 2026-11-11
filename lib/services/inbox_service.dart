import 'package:shared_preferences/shared_preferences.dart';

import 'locator.dart';
import 'tasks_store.dart';
import 'weather_service.dart';

/// One proactive suggestion with a one-tap action.
class InboxAction {
  final String id;
  final IconDataCompat icon;
  final String title;
  final String detail;
  final String ctaLabel;
  final bool requiresConfirm;

  const InboxAction({
    required this.id,
    required this.icon,
    required this.title,
    required this.detail,
    required this.ctaLabel,
    required this.requiresConfirm,
  });
}

/// So we don't need flutter icons in the service layer.
typedef IconDataCompat = int;

/// Proactive inbox: gork looks at live data (weather, memory, tasks) and
/// suggests one-tap actions. Sensitive actions ask for confirmation first.
class InboxService {
  final SharedPreferences _prefs;
  final WeatherService _weather;

  InboxService(this._prefs, this._weather);

  static const String _kDone = 'inbox.done';

  bool isDone(String id) =>
      (_prefs.getStringList(_kDone) ?? []).contains(id);

  Future<void> markDone(String id) async {
    final done = _prefs.getStringList(_kDone) ?? [];
    if (!done.contains(id)) {
      done.add(id);
      await _prefs.setStringList(_kDone, done);
    }
  }

  /// Build today's suggestions from real, local signals.
  Future<List<InboxAction>> suggestions({double? tempC, int? code}) async {
    final actions = <InboxAction>[];

    // Live weather signal (real API, free).
    WeatherNow? weather;
    try {
      weather = tempC != null && code != null
          ? WeatherNow(tempC, code, 0)
          : await _weather.fetch(lat: Locator.ambientLat, lon: Locator.ambientLon);
    } catch (_) {
      weather = null;
    }

    if (weather != null && weather.tempC >= 35) {
      actions.add(const InboxAction(
        id: 'heat-reminder',
        icon: 0xE1C7, // wb_sunny-ish
        title: 'It is very hot outside',
        detail:
            'Current temperature is {temp}°C. Want a water-break reminder every 2 hours?',
        ctaLabel: 'Schedule reminder',
        requiresConfirm: true,
      ));
    }
    if (weather != null && weather.isWet) {
      actions.add(const InboxAction(
        id: 'rain-reminder',
        icon: 0xF1A9,
        title: 'Rain expected today',
        detail: 'Want a one-off "take an umbrella" task before you leave?',
        ctaLabel: 'Schedule reminder',
        requiresConfirm: true,
      ));
    }

    // Memory hygiene signal.
    if (Locator.memory.all().length > 10) {
      actions.add(const InboxAction(
        id: 'memory-review',
        icon: 0xE88B,
        title: 'Memory is growing',
        detail:
            'You have {n} remembered facts. Reviewing them keeps gork sharp.',
        ctaLabel: 'Mark reviewed',
        requiresConfirm: false,
      ));
    }

    // Filter out done items; inject live values into detail strings.
    final done = _prefs.getStringList(_kDone) ?? [];
    return actions.where((a) => !done.contains(a.id)).map((a) {
      var detail = a.detail;
      if (weather != null && a.id == 'heat-reminder') {
        detail = detail.replaceAll('{temp}', weather.tempC.toStringAsFixed(0));
      }
      if (a.id == 'memory-review') {
        detail = detail.replaceAll('{n}', Locator.memory.all().length.toString());
      }
      return InboxAction(
        id: a.id,
        icon: a.icon,
        title: a.title,
        detail: detail,
        ctaLabel: a.ctaLabel,
        requiresConfirm: a.requiresConfirm,
      );
    }).toList();
  }

  /// Execute the action: real effect on the device.
  Future<String> perform(InboxAction action) async {
    switch (action.id) {
      case 'heat-reminder':
        final now = DateTime.now().millisecondsSinceEpoch;
        await Locator.tasks.save(ScheduledTask(
          id: now.toString(),
          title: 'Water break (heat)',
          prompt: 'It is very hot today. Remind me briefly to drink water.',
          repeatMinutes: 120,
          enabled: true,
          createdAt: now,
        ));
        await markDone(action.id);
        return 'Reminder scheduled: water break every 2 hours.';
      case 'rain-reminder':
        final now = DateTime.now().millisecondsSinceEpoch;
        await Locator.tasks.save(ScheduledTask(
          id: now.toString(),
          title: 'Take an umbrella',
          prompt: 'Rain is expected. Remind me to take an umbrella.',
          repeatMinutes: 240,
          enabled: true,
          createdAt: now,
        ));
        await markDone(action.id);
        return 'Reminder scheduled: umbrella.';
      case 'memory-review':
        await markDone(action.id);
        return 'Marked as reviewed.';
      default:
        return 'Unknown action.';
    }
  }
}
