import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One message in a conversation.
class ChatTurn {
  final String role;
  final String content;

  /// Wall-clock epoch ms when the message was created (null for legacy turns).
  /// Drives the date separators in the chat UI.
  final int? time;

  const ChatTurn(this.role, this.content, {this.time});

  Map<String, dynamic> toJson() => time == null
      ? {'role': role, 'content': content}
      : {'role': role, 'content': content, 'time': time};

  factory ChatTurn.fromJson(Map<String, dynamic> json) => ChatTurn(
        json['role'] as String,
        json['content'] as String,
        time: json['time'] as int?,
      );
}

/// A saved conversation.
class Conversation {
  final String id;
  final String title;
  final String providerId;
  final int updatedAt;
  final List<ChatTurn> messages;

  const Conversation({
    required this.id,
    required this.title,
    required this.providerId,
    required this.updatedAt,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'providerId': providerId,
        'updatedAt': updatedAt,
        'messages': [for (final m in messages) m.toJson()],
      };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        title: json['title'] as String,
        providerId: json['providerId'] as String,
        updatedAt: json['updatedAt'] as int,
        messages: [
          for (final m in (json['messages'] as List))
            ChatTurn.fromJson(m as Map<String, dynamic>)
        ],
      );
}

/// Chat history persisted with shared_preferences — simple JSON, no database.
class HistoryStore {
  final SharedPreferences _prefs;

  HistoryStore(this._prefs);

  static const String _kKey = 'chat.conversations';

  Map<String, Conversation> _load() {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in map.entries)
        e.key: Conversation.fromJson(e.value as Map<String, dynamic>)
    };
  }

  List<Conversation> all() {
    final list = _load().values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Conversation? byId(String id) => _load()[id];

  Conversation? get latest {
    final all0 = all();
    return all0.isEmpty ? null : all0.first;
  }

  Future<void> save(Conversation conversation) async {
    final map = _load();
    map[conversation.id] = conversation;
    await _prefs.setString(_kKey, jsonEncode({
      for (final e in map.entries) e.key: e.value.toJson(),
    }));
  }

  Future<void> delete(String id) async {
    final map = _load();
    map.remove(id);
    await _prefs.setString(_kKey, jsonEncode({
      for (final e in map.entries) e.key: e.value.toJson(),
    }));
  }

  Future<void> clear() async {
    await _prefs.remove(_kKey);
  }
}
