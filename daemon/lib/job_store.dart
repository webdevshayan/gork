import 'dart:convert';
import 'dart:io';

/// Server-side chat jobs — the "never losable" contract.
///
/// The phone's outbox POSTs a message to /v1/messages; the daemon persists
/// it to $GORK_HOME/jobs.json, runs it through the LLM, stores the reply and
/// pushes a notification. The phone can die, the app can be closed, the
/// network can vanish mid-flight — the job completes ON THE VPS regardless,
/// and the client pulls the reply whenever it comes back. There is
/// deliberately NO cancel API: once accepted, a request is never cancelled.
class AgentJob {
  final String id;
  final String conversationId;
  final String text;

  /// queued | running | done | error
  final String status;
  final String? reply;
  final int createdAt;
  final int? finishedAt;

  const AgentJob({
    required this.id,
    required this.conversationId,
    required this.text,
    required this.status,
    required this.createdAt,
    this.reply,
    this.finishedAt,
  });

  AgentJob copyWith({
    String? status,
    String? reply,
    int? finishedAt,
  }) =>
      AgentJob(
        id: id,
        conversationId: conversationId,
        text: text,
        status: status ?? this.status,
        createdAt: createdAt,
        reply: reply ?? this.reply,
        finishedAt: finishedAt ?? this.finishedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'text': text,
        'status': status,
        if (reply != null) 'reply': reply,
        'created_at': createdAt,
        if (finishedAt != null) 'finished_at': finishedAt,
      };

  static AgentJob fromJson(Map<String, dynamic> j) => AgentJob(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        text: j['text'] as String,
        status: j['status'] as String,
        createdAt: (j['created_at'] as num).toInt(),
        reply: j['reply'] as String?,
        finishedAt: (j['finished_at'] as num?)?.toInt(),
      );
}

/// Where jobs live. A JSON file in the state dir — survives daemon restarts
/// and box reboots, exactly like tasks.json.
abstract class JobStore {
  List<AgentJob> all();
  Future<void> save(AgentJob job);
}

class FileJobStore implements JobStore {
  FileJobStore(this.path);

  final String path;

  List<AgentJob> _read() {
    final file = File(path);
    if (!file.existsSync()) return <AgentJob>[];
    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      return [
        for (final e in list) AgentJob.fromJson(e as Map<String, dynamic>)
      ];
    } catch (_) {
      return <AgentJob>[]; // corrupt file must never take the daemon down
    }
  }

  @override
  List<AgentJob> all() => List.of(_read());

  @override
  Future<void> save(AgentJob job) async {
    final jobs = _read();
    final i = jobs.indexWhere((j) => j.id == job.id);
    if (i >= 0) {
      jobs[i] = job;
    } else {
      jobs.add(job);
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(jobs));
  }
}

/// The notification body: the first few lines of the reply, clipped —
/// "faster to understand" means the user reads the gist from the lock
/// screen without opening the app.
String jobNotificationPreview(String reply) {
  final lines = reply
      .trim()
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .take(3)
      .join('\n');
  if (lines.isEmpty) return '(empty reply)';
  return lines.length <= 220 ? lines : '${lines.substring(0, 220)}…';
}
