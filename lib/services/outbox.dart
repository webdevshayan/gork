import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'locator.dart';
import 'secure_store.dart';

/// A message sent while the VPS is configured lives on the SERVER: the phone
/// can die, the app can go inactive — the job keeps running server-side and
/// the reply is pulled when the client returns. There is deliberately NO
/// cancel API: once accepted, a request is never cancelled.
enum OutboxStatus { pending, accepted, failed }

class OutboxEntry {
  OutboxEntry({
    required this.id,
    required this.conversationId,
    required this.text,
    required this.createdAt,
    required this.status,
    this.jobId,
    this.notified = false,
  });

  final String id;
  final String conversationId;
  final String text;
  final int createdAt;
  OutboxStatus status;

  /// The VPS job id once the server accepted the message.
  String? jobId;

  /// True once the finished reply has been surfaced (notification). The
  /// reply itself is NEVER lost: it stays on the VPS until the chat pulls
  /// it — [notified] only tracks what the user has already been told.
  bool notified;

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'text': text,
        'createdAt': createdAt,
        'status': status.name,
        if (jobId != null) 'jobId': jobId,
        'notified': notified,
      };

  static OutboxEntry fromJson(Map<String, dynamic> j) => OutboxEntry(
        id: j['id'] as String,
        conversationId: j['conversationId'] as String,
        text: j['text'] as String,
        createdAt: j['createdAt'] as int,
        status: OutboxStatus.values.byName(j['status'] as String),
        jobId: j['jobId'] as String?,
        notified: j['notified'] as bool? ?? false,
      );
}

/// The device-side queue for server-processed messages. Entries persist in
/// prefs (survives process death); the flusher retries until the server
/// accepts each one; accepted jobs are polled for their reply. Nothing here
/// cancels work — the VPS finishes what it accepted.
class MessageOutbox {
  MessageOutbox({
    http.Client? client,
    SharedPreferences? prefs,
    SecureStore? store,
    this.retryAfter = const Duration(seconds: 30),
  })  : _client = client,
        _prefsOverride = prefs,
        _storeOverride = store;

  final http.Client? _client;
  final SharedPreferences? _prefsOverride;
  final SecureStore? _storeOverride;
  final Duration retryAfter;
  Timer? _retryTimer;

  String? get url {
    final v = prefs.getString('vps.url');
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  Future<String?> token() => (store ?? Locator.store).read('vps.token');

  SharedPreferences get prefs =>
      _prefsOverride ?? Locator.prefs;

  SecureStore? get store => _storeOverride;

  http.Client get _http => _client ?? Locator.httpClient;

  bool get configured => url != null;

  // ------------------------------------------------------------ persistence --
  List<OutboxEntry> _entries() {
    final raw = prefs.getStringList('outbox.entries') ?? const [];
    return [
      for (final s in raw)
        OutboxEntry.fromJson(jsonDecode(s) as Map<String, dynamic>)
    ];
  }

  Future<void> _save(List<OutboxEntry> entries) async {
    await prefs.setStringList(
        'outbox.entries', [for (final e in entries) jsonEncode(e.toJson())]);
  }

  List<OutboxEntry> pending() =>
      _entries().where((e) => e.status == OutboxStatus.pending).toList();

  // ----------------------------------------------------------------- enqueue --
  /// Adds the message to the outbox and immediately tries to hand it to the
  /// VPS. Returns the entry (with [jobId] set when the server accepted it
  /// right away). NEVER throws on network trouble — the entry just stays
  /// pending for the next flush.
  Future<OutboxEntry> enqueue(String conversationId, String text,
      {bool awaitAcceptance = false}) async {
    final entry = OutboxEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      conversationId: conversationId,
      text: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      status: OutboxStatus.pending,
    );
    final entries = _entries()..add(entry);
    await _save(entries);
    if (awaitAcceptance) {
      // The chat screen needs the job id before it can poll; acceptance is
      // still fast (one POST) and offline it just returns the pending entry.
      await _flushOne(entry);
      return _entries().firstWhere((e) => e.id == entry.id);
    }
    // Fire-and-forget: the send path must never block on the network.
    unawaited(_flushOne(entry));
    return entry;
  }

  Future<void> flush() async {
    for (final e in pending()) {
      await _flushOne(e);
    }
    _scheduleRetryIfPending();
  }

  Future<void> _flushOne(OutboxEntry entry) async {
    final base = url;
    if (base == null) return;
    try {
      final res = await _http.post(
        Uri.parse('$base/v1/messages'),
        headers: {
          'Content-Type': 'application/json',
          if (await token() != null) 'Authorization': 'Bearer ${await token()}',
        },
        body: jsonEncode({
          'conversation_id': entry.conversationId,
          'text': entry.text,
        }),
      );
      final entries = _entries();
      final idx = entries.indexWhere((e) => e.id == entry.id);
      if (idx == -1) return;
      if (res.statusCode == 201) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        entries[idx]
          ..status = OutboxStatus.accepted
          ..jobId = body['id'] as String?;
      } else if (res.statusCode >= 400 && res.statusCode < 500) {
        entries[idx].status = OutboxStatus.failed; // bad request: honest fail
      }
      await _save(entries);
    } catch (_) {
      // Network trouble: stays pending — retried by the next flush. The
      // request is NOT cancelled; the server will do the work once reached.
    }
    _scheduleRetryIfPending();
  }

  @visibleForTesting
  bool get retryTimerActive => _retryTimer?.isActive ?? false;

  /// Cancels the retry timer (tests end with fake clocks; production keeps
  /// the singleton alive for the app's lifetime).
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _scheduleRetryIfPending() {
    if (!configured || pending().isEmpty || _retryTimer?.isActive == true) {
      return;
    }
    _retryTimer = Timer(retryAfter, () {
      _retryTimer = null;
      unawaited(flush());
    });
  }

  // ------------------------------------------------------------------- jobs --
  /// Poll one accepted job. Returns ('done', reply) / (status, null).
  Future<String?> jobResult(String jobId) async {
    final base = url;
    if (base == null) return null;
    try {
      final res = await _http.get(
        Uri.parse('$base/v1/jobs/$jobId'),
        headers: {
          if (await token() != null) 'Authorization': 'Bearer ${await token()}',
        },
      );
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'done') return null;
      final result = body['result'] as Map<String, dynamic>?;
      return result?['reply'] as String?;
    } catch (_) {
      return null; // server unreachable — it keeps working regardless
    }
  }

  /// Finished jobs the user has NOT been told about yet — the reply
  /// preview lines for a notification ("response ready: …"), one per job,
  /// marked as notified. Never loses anything: the reply itself stays on
  /// the VPS regardless; [notified] only tracks what was surfaced.
  Future<List<FinishedReply>> pollFinished() async {
    final out = <FinishedReply>[];
    final entries = _entries();
    var dirty = false;
    for (final e in entries) {
      if (e.status != OutboxStatus.accepted || e.jobId == null || e.notified) {
        continue;
      }
      final reply = await jobResult(e.jobId!);
      if (reply == null) continue; // still running / unreachable — later
      e.notified = true;
      dirty = true;
      out.add(FinishedReply(
        conversationId: e.conversationId,
        preview: _preview(reply),
        reply: reply,
      ));
    }
    if (dirty) await _save(entries);
    return out;
  }

  /// The gist for the notification: first lines, clipped, PLAIN TEXT —
  /// the user should understand the answer from the lock screen without
  /// raw markdown noise ("Open [chat.z.ai](https://chat.z.ai) and select
  /// **Si…" — screenshot 2026-11-19). Movement 64 strips the markup.
  static String _preview(String reply) {
    String text = reply.trim();
    // Links: [label](url) → label (url only when the label is generic).
    text = text.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
        (m) => m[1]!.trim() == m[2]!.trim() || m[1]!.trim().isEmpty
            ? m[2]!
            : '${m[1]} (${m[2]})');
    // Emphasis, code spans, headers, list stars.
    text = text
        .replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => m[1] ?? '')
        .replaceAllMapped(RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)'),
            (m) => m[1] ?? '')
        .replaceAllMapped(RegExp(r'__([^_]+)__'), (m) => m[1] ?? '')
        .replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m[1] ?? '')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(3)
        .join('\n');
    if (lines.isEmpty) return '(empty reply)';
    return lines.length <= 200 ? lines : '${lines.substring(0, 200)}…';
  }

  /// All server-side messages for a conversation (processed while the app
  /// was away). Returns pairs: user / assistant.
  Future<List<Map<String, String>>> pullMessages(String conversationId) async {    final base = url;
    if (base == null) return const [];
    try {
      final res = await _http.get(
        Uri.parse('$base/v1/conversations/$conversationId/messages'),
        headers: {
          if (await token() != null) 'Authorization': 'Bearer ${await token()}',
        },
      );
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return [
        for (final m in (body['messages'] as List))
          {
            'role': (m as Map<String, dynamic>)['role'] as String,
            'content': m['content'] as String,
          }
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// A reply that finished on the VPS while the user was away.
class FinishedReply {
  FinishedReply({
    required this.conversationId,
    required this.preview,
    required this.reply,
  });

  final String conversationId;

  /// First lines for the notification body.
  final String preview;

  /// The full reply — already merged into the conversation when the chat
  /// opens (the daemon keeps it until the client pulls it).
  final String reply;
}

@visibleForTesting
void debugStopOutboxTimers() {
  // Tests pump the tree; nothing periodic lives here by design.
}
