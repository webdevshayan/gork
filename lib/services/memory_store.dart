import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent memory: small facts the assistant should remember across
/// sessions. Stored locally as a JSON list of strings.
class MemoryStore {
  final SharedPreferences _prefs;

  MemoryStore(this._prefs);

  static const String _kKey = 'memory.facts';

  List<String> all() {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return [];
    return [for (final f in jsonDecode(raw) as List) f as String];
  }

  Future<void> remember(String fact) async {
    final facts = all();
    if (facts.contains(fact)) return;
    facts.add(fact);
    await _prefs.setString(_kKey, jsonEncode(facts));
  }

  Future<bool> forget(String fact) async {
    final facts = all();
    final removed = facts.remove(fact);
    if (removed) {
      await _prefs.setString(_kKey, jsonEncode(facts));
    }
    return removed;
  }

  Future<void> clear() async {
    await _prefs.remove(_kKey);
  }

  /// Memory block injected into the system prompt, or empty string.
  String systemPromptBlock() {
    final facts = all();
    if (facts.isEmpty) return '';
    return '\n\nThings you remember about the user:\n- ${facts.join('\n- ')}';
  }
}
