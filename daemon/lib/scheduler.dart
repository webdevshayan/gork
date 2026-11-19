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
  /// [system] overrides the default persona line — chat jobs ask gork as
  /// the user's assistant, scheduled tasks ask the brief task runner.
  /// [history] carries the earlier turns of the conversation (oldest
  /// first) so a chat job is answered with the thread in mind, not cold.
  Future<String> call(String prompt,
      {String? system, List<({String role, String content})>? history});

  /// Movement 67 — one completion against [messages] with the agent's
  /// [tools] offered as OpenAI-style function calling. The server's agent
  /// loop drives this directly: it appends tool results and re-calls until
  /// the model answers in plain text. [tools] empty = a plain call.
  Future<LlmTurn> chat(List<Map<String, dynamic>> messages,
      {List<Map<String, dynamic>>? tools});

  String describe();
}

/// One model turn: either text, or tool-call requests (possibly both).
class LlmTurn {
  const LlmTurn({
    this.content,
    this.toolCalls = const [],
    this.raw = const {},
  });

  final String? content;
  final List<AgentToolCall> toolCalls;

  /// The assistant message EXACTLY as the provider returned it — fed back
  /// verbatim before the tool results (tool_call ids must match).
  final Map<String, dynamic> raw;
}

/// A parsed function-call request from the model.
class AgentToolCall {
  const AgentToolCall({
    required this.id,
    required this.name,
    required this.argsJson,
  });

  final String id;
  final String name;

  /// The arguments as a raw JSON string — decoded defensively by the
  /// caller (models occasionally emit invalid JSON).
  final String argsJson;
}

/// The provider's own one-line message out of an error body. Scheduled-task
/// failures land in notifications, where a raw JSON dump (an OpenRouter 402
/// alone carries kilobytes of repeated previous_errors) is pure noise.
String _briefLlmError(String body) {
  final raw = body.trim();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      final err = decoded['error'];
      if (err is Map<String, dynamic> &&
          (err['message']?.toString() ?? '').isNotEmpty) {
        final msg = err['message'].toString();
        final metadata = err['metadata'];
        final hint = metadata is Map<String, dynamic>
            ? metadata['remedy_hint']?.toString()
            : null;
        final out = (hint == null || hint.isEmpty) ? msg : '$msg — $hint';
        return out.length <= 300 ? out : out.substring(0, 300);
      }
    }
  } catch (_) {
    // not JSON — fall through to the clipped raw text
  }
  return raw.length <= 300 ? raw : raw.substring(0, 300);
}

class EnvLlmCaller implements LlmCaller {
  final http.Client _http;

  /// Live config overlay: POST /config writes here so a running daemon picks
  /// up new LLM credentials without a restart. Overlay wins over env vars.
  final Map<String, String> overlay;

  EnvLlmCaller([http.Client? client, Map<String, String>? overlay])
      : _http = client ?? http.Client(),
        overlay = overlay ?? const {};

  String _env(String key, String fallback) {
    final live = overlay[key];
    if (live != null && live.isNotEmpty) return live;
    return Platform.environment[key] ?? fallback;
  }

  String get _baseUrl =>
      _env('GORK_BASE_URL', 'https://api.openai.com/v1');
  String get _apiKey => _env('GORK_API_KEY', '');
  String get _model => _env('GORK_MODEL', 'gpt-4o-mini');

  @override
  String describe() => _apiKey.isEmpty
      ? 'not configured (set GORK_API_KEY)'
      : '$_baseUrl model=$_model';

  @override
  Future<String> call(String prompt,
      {String? system, List<({String role, String content})>? history}) async {
    final turn = await chat([
      {
        'role': 'system',
        'content': system ??
            'You are gork, running a scheduled task. Be brief.'
      },
      for (final turn in history ?? const [])
        {'role': turn.role, 'content': turn.content},
      {'role': 'user', 'content': prompt},
    ]);
    return turn.content ?? '';
  }

  @override
  Future<LlmTurn> chat(List<Map<String, dynamic>> messages,
      {List<Map<String, dynamic>>? tools}) async {
    if (_apiKey.isEmpty) {
      throw StateError('GORK_API_KEY is not set on the VPS');
    }
    final body = <String, dynamic>{
      'model': _model,
      // Cap the output ceiling: without it providers assume the model's
      // maximum, which OpenRouter refuses with 402 when the balance cannot
      // cover that worst case. Tasks are "be brief".
      'max_tokens': 1024,
      'messages': messages,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
    };
    http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('$_baseUrl/chat/completions'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
    } on http.ClientException {
      rethrow;
    }
    if (response.statusCode != 200) {
      // Movement 67 — an endpoint that rejects `tools` (text-only
      // providers answer 400 naming the field) must not break chat:
      // retry once without tools so the agent degrades to talking.
      if (tools != null &&
          tools.isNotEmpty &&
          response.statusCode >= 400 &&
          response.statusCode < 500) {
        final brief = _briefLlmError(response.body).toLowerCase();
        final looksLikeToolsRefusal = brief.contains('tool') ||
            brief.contains('function') ||
            brief.contains('unsupported') ||
            brief.contains('unknown');
        if (looksLikeToolsRefusal) {
          final retry = Map<String, dynamic>.from(body)..remove('tools');
          final second = await _http
              .post(
                Uri.parse('$_baseUrl/chat/completions'),
                headers: {
                  'content-type': 'application/json',
                  'authorization': 'Bearer $_apiKey',
                },
                body: jsonEncode(retry),
              )
              .timeout(const Duration(seconds: 60));
          if (second.statusCode == 200) {
            return _turnFrom(second.body);
          }
        }
      }
      throw HttpException(
          'LLM ${response.statusCode}: ${_briefLlmError(response.body)}');
    }
    return _turnFrom(response.body);
  }

  /// Parses a chat-completions response body into an [LlmTurn].
  LlmTurn _turnFrom(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final choices = data['choices'] as List;
    final message =
        (choices.first['message'] as Map<String, dynamic>? ?? {});
    final toolCalls = <AgentToolCall>[];
    final rawCalls = message['tool_calls'];
    if (rawCalls is List) {
      for (final c in rawCalls) {
        if (c is! Map<String, dynamic>) continue;
        final fn = c['function'] as Map<String, dynamic>? ?? {};
        toolCalls.add(AgentToolCall(
          id: c['id']?.toString() ?? 'call-${toolCalls.length}',
          name: fn['name']?.toString() ?? '',
          argsJson: fn['arguments']?.toString() ?? '{}',
        ));
      }
    }
    return LlmTurn(
      content: message['content'] as String?,
      toolCalls: toolCalls,
      raw: message,
    );
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
