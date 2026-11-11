import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Pure scheduling logic shared by the daemon (and mirrored in the app).
class Task {
  final String id;
  final String title;
  final String prompt;
  final int repeatMinutes;
  final bool enabled;
  final int? lastRun;

  const Task({
    required this.id,
    required this.title,
    required this.prompt,
    required this.repeatMinutes,
    required this.enabled,
    this.lastRun,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'prompt': prompt,
        'repeatMinutes': repeatMinutes,
        'enabled': enabled,
        'lastRun': lastRun,
      };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        id: json['id'] as String,
        title: json['title'] as String,
        prompt: json['prompt'] as String,
        repeatMinutes: (json['repeatMinutes'] as num?)?.toInt() ?? 60,
        enabled: json['enabled'] as bool? ?? true,
        lastRun: json['lastRun'] as int?,
      );
}

typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now();

bool isDue(Task task, DateTime now) {
  if (!task.enabled) return false;
  if (task.lastRun == null) return true;
  return now.millisecondsSinceEpoch - task.lastRun! >= task.repeatMinutes * 60000;
}

List<Task> dueTasks(List<Task> tasks, DateTime now) =>
    [for (final t in tasks) if (isDue(t, now)) t];

/// Where tasks live.
abstract class TaskStore {
  List<Task> all();
  Future<void> save(Task task);
  Future<void> markRan(String id, DateTime when);
  Future<void> delete(String id);
}

/// JSON file store (survives restarts).
class FileTaskStore implements TaskStore {
  final String path;

  FileTaskStore(this.path);

  List<Task> _read() {
    final file = File(path);
    if (!file.existsSync()) return [];
    final raw = file.readAsStringSync();
    if (raw.isEmpty) return [];
    return [
      for (final e in jsonDecode(raw) as List) Task.fromJson(e as Map<String, dynamic>)
    ];
  }

  void _write(List<Task> tasks) {
    File(path)
        .writeAsStringSync(jsonEncode([for (final t in tasks) t.toJson()]));
  }

  @override
  List<Task> all() => _read();

  @override
  Future<void> save(Task task) async {
    final list = _read();
    final index = list.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      list[index] = task;
    } else {
      list.add(task);
    }
    _write(list);
  }

  @override
  Future<void> markRan(String id, DateTime when) async {
    final list = _read();
    final index = list.indexWhere((t) => t.id == id);
    if (index >= 0) {
      list[index] = Task(
        id: list[index].id,
        title: list[index].title,
        prompt: list[index].prompt,
        repeatMinutes: list[index].repeatMinutes,
        enabled: list[index].enabled,
        lastRun: when.millisecondsSinceEpoch,
      );
      _write(list);
    }
  }

  @override
  Future<void> delete(String id) async {
    final list = _read();
    list.removeWhere((t) => t.id == id);
    _write(list);
  }
}

/// Calls the LLM (OpenAI-compatible endpoint, configured via env).
abstract class LlmCaller {
  Future<String> call(String prompt);
  String describe();
}

class EnvLlmCaller implements LlmCaller {
  final http.Client _http;

  EnvLlmCaller([http.Client? client]) : _http = client ?? http.Client();

  String get _baseUrl =>
      Platform.environment['GORK_BASE_URL'] ?? 'https://api.openai.com/v1';
  String get _apiKey => Platform.environment['GORK_API_KEY'] ?? '';
  String get _model => Platform.environment['GORK_MODEL'] ?? 'gpt-4o-mini';

  @override
  String describe() => _apiKey.isEmpty
      ? 'not configured (set GORK_API_KEY)'
      : '$_baseUrl model=$_model';

  @override
  Future<String> call(String prompt) async {
    if (_apiKey.isEmpty) {
      throw StateError('GORK_API_KEY is not set on the VPS');
    }
    final response = await _http
        .post(
          Uri.parse('$_baseUrl/chat/completions'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $_apiKey',
          },
          body: jsonEncode({
            'model': _model,
            'messages': [
              {
                'role': 'system',
                'content': 'You are gork, running a scheduled task. Be brief.'
              },
              {'role': 'user', 'content': prompt},
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw HttpException('LLM ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List;
    final message = choices.first['message'] as Map<String, dynamic>;
    return (message['content'] as String?) ?? '';
  }
}

/// Pushes results to the phone.
abstract class Notifier {
  Future<void> notify(String title, String body);
}

class NoopNotifier implements Notifier {
  const NoopNotifier();

  @override
  Future<void> notify(String title, String body) async {}
}

/// ntfy.sh push — free, no account, self-hostable.
class NtfyNotifier implements Notifier {
  final String topic;
  final http.Client _http;

  NtfyNotifier(this.topic, [http.Client? client])
      : _http = client ?? http.Client();

  @override
  Future<void> notify(String title, String body) async {
    try {
      await _http.post(
        Uri.parse('https://ntfy.sh/$topic'),
        headers: {'title': title},
        body: body,
      );
    } catch (_) {}
  }
}
