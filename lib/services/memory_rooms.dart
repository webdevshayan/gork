import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'locator.dart';
import 'secure_store.dart';

/// One memory operation inside the single-call room memory API.
///
/// Rooms are categories of information; each room holds blocks; each block
/// has a title, a subcategory and the content. Retrieval, mutation, adding
/// (and deleting) always travel TOGETHER in one POST /v1/memory/op — the
/// agent never pays a round trip per action.
enum MemoryOpKind { retrieve, add, mutate, delete }

class MemoryOp {
  const MemoryOp.retrieve(this.room, {this.block})
      : kind = MemoryOpKind.retrieve,
        title = null,
        category = null,
        content = null;

  const MemoryOp.add(this.room,
      {required this.title, required this.category, required this.content})
      : kind = MemoryOpKind.add,
        block = null;

  const MemoryOp.mutate(
      {required this.block, this.title, this.category, this.content})
      : room = '',
        kind = MemoryOpKind.mutate;

  const MemoryOp.delete({required this.block})
      : room = '',
        kind = MemoryOpKind.delete,
        title = null,
        category = null,
        content = null;

  final MemoryOpKind kind;
  final String room;
  final String? block; // target block id (retrieve/mutate/delete)
  final String? title;
  final String? category;
  final String? content;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (room.isNotEmpty) 'room': room,
        if (block != null) 'block': block,
        if (title != null) 'title': title,
        if (category != null) 'category': category,
        if (content != null) 'content': content,
      };

  /// Parses a model-produced op object into a typed [MemoryOp].
  static MemoryOp fromJson(Map<String, dynamic> json) {
    switch (json['kind']) {
      case 'retrieve':
        return MemoryOp.retrieve(
          (json['room'] as String?) ?? '',
          block: json['block'] as String?,
        );
      case 'add':
        return MemoryOp.add(
          (json['room'] as String?) ?? '',
          title: (json['title'] as String?) ?? '',
          category: (json['category'] as String?) ?? '',
          content: (json['content'] as String?) ?? '',
        );
      case 'mutate':
        return MemoryOp.mutate(
          block: (json['block'] as String?) ?? '',
          title: json['title'] as String?,
          category: json['category'] as String?,
          content: json['content'] as String?,
        );
      case 'delete':
      default:
        return MemoryOp.delete(block: (json['block'] as String?) ?? '');
    }
  }
}

/// Client for the VPS room-based memory. The VPS is the source of truth;
/// nothing here ever blocks a chat — every call degrades to null/empty on
/// a missing configuration or network trouble.
class MemoryRoomsService {
  MemoryRoomsService({http.Client? client, SharedPreferences? prefs, SecureStore? store})
      : _client = client,
        _prefsOverride = prefs,
        _storeOverride = store;

  final http.Client? _client;
  final SharedPreferences? _prefsOverride;
  final SecureStore? _storeOverride;

  SharedPreferences get prefs => _prefsOverride ?? Locator.prefs;
  SecureStore get _store => _storeOverride ?? Locator.store;
  http.Client get _http => _client ?? Locator.httpClient;

  String? get url {
    final v = prefs.getString('vps.url');
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  bool get configured => url != null;

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// THE one call: any mix of retrieve / add / mutate / delete in one round
  /// trip. Returns the response ({results, map}) or null when the VPS is
  /// not configured or unreachable — callers carry on without memory.
  Future<Map<String, dynamic>?> op(List<MemoryOp> ops) async {
    final base = url;
    if (base == null || ops.isEmpty) return null;
    try {
      final res = await _http.post(
        Uri.parse('$base/v1/memory/op'),
        headers: _headers(await _store.read('vps.token')),
        body: jsonEncode({'ops': [for (final op in ops) op.toJson()]}),
      );
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// The system-prompt block: the full room map (rooms → blocks, titles +
  /// subcategories + sizes) plus the one-call instructions. Null when the
  /// VPS is unconfigured or unreachable — the agent then just has no rooms.
  Future<String?> promptBlock() async {
    final base = url;
    if (base == null) return null;
    try {
      final res = await _http.get(
        Uri.parse('$base/v1/memory/map'),
        headers: _headers(await _store.read('vps.token')),
      );
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rooms = (body['rooms'] as List? ?? const []);
      if (rooms.isEmpty) return null;
      final buf = StringBuffer(
          '\n\nRoom-based memory lives on your VPS. You are always aware of '
          'every room and block below. Retrieve, mutate and add happen in '
          'ONE call with the memory_op tool (a list of ops).\n');
      for (final r in rooms) {
        final room = r as Map<String, dynamic>;
        buf.write('Room "${room['room']}":');
        final blocks = room['blocks'] as List? ?? const [];
        if (blocks.isEmpty) {
          buf.write(' (empty)');
        } else {
          buf.write('\n');
          for (final b in blocks) {
            final block = b as Map<String, dynamic>;
            buf.write(
                '  - "${block['title']}" (${block['category']}, '
                '${block['chars']} chars, id ${block['id']})\n');
          }
        }
      }
      return buf.toString();
    } catch (_) {
      return null;
    }
  }

  /// Fire-and-forget context-length extraction: asks the VPS to distill the
  /// conversation into the rooms when its transcript grows past the model's
  /// usable context. Never throws, never blocks the chat.
  Future<void> maybeExtract(String conversationId, {int contextTokens = 128000}) async {
    final base = url;
    if (base == null) return;
    try {
      await _http.post(
        Uri.parse('$base/v1/memory/extract'),
        headers: _headers(await _store.read('vps.token')),
        body: jsonEncode({
          'conversation_id': conversationId,
          'context_chars': contextTokens * 4,
        }),
      );
    } catch (_) {
      // The VPS keeps the request once it is reached; nothing to do here.
    }
  }

  /// Tool entry point for `memory_op` — args as produced by the model:
  /// {"ops": [{"kind": "retrieve"|"add"|"mutate"|"delete", ...}]}
  Future<String> execute(Map<String, dynamic> args) async {
    if (!configured) {
      return 'error: room memory lives on your VPS — configure it in '
          'Cloud Computer first';
    }
    final rawOps = args['ops'];
    if (rawOps is! List || rawOps.isEmpty) {
      return 'error: ops must be a non-empty list';
    }
    final result = await op([
      for (final raw in rawOps)
        MemoryOp.fromJson(raw as Map<String, dynamic>),
    ]);
    if (result == null) {
      return 'error: the VPS did not answer — memory op not applied';
    }
    return jsonEncode(result);
  }
}
