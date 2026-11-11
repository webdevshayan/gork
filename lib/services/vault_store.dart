import 'dart:convert';

import '../services/secure_store.dart';

/// One entry in the encrypted vault: passwords, logins, card details.
class VaultEntry {
  final String id;
  final String title;
  final String username;
  final String secret;
  final String notes;
  final int createdAt;

  const VaultEntry({
    required this.id,
    required this.title,
    required this.username,
    required this.secret,
    required this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'username': username,
        'secret': secret,
        'notes': notes,
        'createdAt': createdAt,
      };

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        username: json['username'] as String? ?? '',
        secret: json['secret'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        createdAt: json['createdAt'] as int,
      );
}

/// Encrypted vault storage. The whole vault is one JSON blob inside
/// flutter_secure_storage (device keystore encryption). Nothing is stored in
/// plain preferences.
class VaultStore {
  final SecureStore _store;

  VaultStore(this._store);

  static const String _kKey = 'vault.entries';

  List<VaultEntry> _decode(String raw) {
    if (raw.isEmpty) return [];
    return [
      for (final e in jsonDecode(raw) as List) VaultEntry.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<List<VaultEntry>> all() async =>
      _decode(await _store.read(_kKey) ?? '');

  Future<void> save(VaultEntry entry) async {
    final entries = await all();
    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      entries[index] = entry;
    } else {
      entries.add(entry);
    }
    await _store.write(
        _kKey, jsonEncode([for (final e in entries) e.toJson()]));
  }

  Future<void> delete(String id) async {
    final entries = await all();
    entries.removeWhere((e) => e.id == id);
    await _store.write(
        _kKey, jsonEncode([for (final e in entries) e.toJson()]));
  }
}
