import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A task that runs on a timer, not on demand.
class ScheduledTask {
  final String id;
  final String title;
  final String prompt;
  final int repeatMinutes;
  final bool enabled;
  final int? lastRun;
  final int createdAt;

  const ScheduledTask({
    required this.id,
    required this.title,
    required this.prompt,
    required this.repeatMinutes,
    required this.enabled,
    required this.createdAt,
    this.lastRun,
  });

  ScheduledTask copyWith({bool? enabled, int? lastRun}) => ScheduledTask(
        id: id,
        title: title,
        prompt: prompt,
        repeatMinutes: repeatMinutes,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt,
        lastRun: lastRun ?? this.lastRun,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'prompt': prompt,
        'repeatMinutes': repeatMinutes,
        'enabled': enabled,
        'lastRun': lastRun,
        'createdAt': createdAt,
      };

  factory ScheduledTask.fromJson(Map<String, dynamic> json) => ScheduledTask(
        id: json['id'] as String,
        title: json['title'] as String,
        prompt: json['prompt'] as String,
        repeatMinutes: json['repeatMinutes'] as int,
        enabled: json['enabled'] as bool,
        lastRun: json['lastRun'] as int?,
        createdAt: json['createdAt'] as int,
      );
}

/// Pure due-check — easy to test, no clock hidden inside.
bool isTaskDue(ScheduledTask task, DateTime now) {
  if (!task.enabled) return false;
  if (task.lastRun == null) return true;
  return now.millisecondsSinceEpoch - task.lastRun! >= task.repeatMinutes * 60000;
}

class TasksStore {
  final SharedPreferences _prefs;

  TasksStore(this._prefs);

  static const String _kKey = 'tasks.items';

  List<ScheduledTask> all() {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return [];
    return [
      for (final e in jsonDecode(raw) as List)
        ScheduledTask.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<void> save(ScheduledTask task) async {
    final list = all();
    final index = list.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      list[index] = task;
    } else {
      list.add(task);
    }
    await _prefs.setString(
        _kKey, jsonEncode([for (final t in list) t.toJson()]));
  }

  Future<void> delete(String id) async {
    final list = all();
    list.removeWhere((t) => t.id == id);
    await _prefs.setString(
        _kKey, jsonEncode([for (final t in list) t.toJson()]));
  }
}
