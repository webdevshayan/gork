import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 69 — Skills: markdown files the agent (and the user) can read.
/// A skill is one .md file in the app documents dir:
///
///     skills/20261120093000-nightly-backup.md
///     # Nightly backup
///     1. ssh into the VPS…
///
/// The agent LEARNS skills two ways: the user teaches one here, or the
/// agent replies in chat with a ```gork-skill fenced block (harvested like
/// panels) — every skill syncs to the VPS (POST /v1/skills) when a daemon
/// is configured, so the agent can follow it in later sessions.
class Skill {
  final String id;
  final String title;
  final String body;
  final int updatedAt;

  const Skill({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  /// The full markdown file content (what the agent reads).
  String get markdown => '# $title\n\n$body\n';

  Skill copyWith({String? title, String? body}) => Skill(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'updatedAt': updatedAt,
      };

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String? ?? '',
        updatedAt: json['updatedAt'] as int? ?? 0,
      );

  /// Parse a saved .md file: first `# ` line is the title.
  factory Skill.fromMarkdown(String id, String content) {
    final lines = content.split('\n');
    String title = 'Untitled skill';
    var rest = lines;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('# ')) {
        title = lines[i].substring(2).trim();
        rest = lines.skip(i + 1).toList();
        break;
      }
    }
    return Skill(
        id: id,
        title: title,
        body: rest.join('\n').trim(),
        updatedAt: DateTime.now().millisecondsSinceEpoch);
  }
}

class SkillsStore {
  SkillsStore(this._prefs);

  final SharedPreferences _prefs;

  /// The last-known sync state per skill id ('synced' once the VPS acked).
  static const String _kSyncKey = 'skills.synced';

  /// Prefs fallback when the documents dir is unavailable (tests, locked
  /// storage): the skills live as JSON entries instead of .md files.
  static const String _kFallbackKey = 'skills.fallback';

  Directory? _dir;

  Future<Directory> _skillsDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/skills');
    if (!_dir!.existsSync()) _dir!.createSync(recursive: true);
    return _dir!;
  }

  Future<List<Skill>> all() async {
    final out = <Skill>[];
    try {
      final dir = await _skillsDir();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final f in files) {
        out.add(Skill.fromMarkdown(
            f.path.split('/').last.replaceAll('.md', ''),
            f.readAsStringSync()));
      }
    } catch (_) {
      // No documents dir (tests, locked storage) — the prefs fallback below
      // keeps every skill the user wrote.
    }
    final seen = out.map((s) => s.id).toSet();
    final raw = _prefs.getStringList(_kFallbackKey) ?? const [];
    for (final e in raw) {
      try {
        final skill = Skill.fromJson(jsonDecode(e) as Map<String, dynamic>);
        if (!seen.contains(skill.id)) out.insert(0, skill);
      } catch (_) {}
    }
    return out;
  }

  Future<Skill> save({String? id, required String title, required String body}) async {
    final String skillId = id ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final skill = Skill(
        id: skillId,
        title: title.trim(),
        body: body.trim(),
        updatedAt: DateTime.now().millisecondsSinceEpoch);
    try {
      final dir = await _skillsDir();
      await File('${dir.path}/$skillId.md')
          .writeAsString(skill.markdown, flush: true);
    } catch (_) {
      // Files unavailable — keep the skill in prefs so nothing is lost.
      final raw = _prefs.getStringList(_kFallbackKey) ?? const [];
      await _prefs.setStringList(_kFallbackKey, [
        ...raw.where((e) {
          try {
            return (jsonDecode(e) as Map<String, dynamic>)['id'] != skillId;
          } catch (_) {
            return true;
          }
        }),
        jsonEncode(skill.toJson()),
      ]);
    }
    return skill;
  }

  /// The agent's fenced ```gork-skill block becomes a real skill file.
  Future<Skill?> addFromAgent(Map<String, dynamic> json) async {
    final title = json['title']?.toString();
    final steps = json['steps']?.toString();
    if (title == null || title.isEmpty || steps == null || steps.isEmpty) {
      return null;
    }
    return save(title: title, body: steps);
  }

  Future<void> delete(String id) async {
    try {
      final dir = await _skillsDir();
      final f = File('${dir.path}/$id.md');
      if (f.existsSync()) await f.delete();
    } catch (_) {}
    final raw = _prefs.getStringList(_kFallbackKey) ?? const [];
    await _prefs.setStringList(
        _kFallbackKey,
        [
          for (final e in raw)
            if (e.contains('"$id"') == false) e,
        ],
    );
  }

  /// Read one skill's markdown (the detail view). Works from the files
  /// AND from the prefs fallback — a test-persisted skill is readable.
  Future<String> read(String id) async {
    try {
      final dir = await _skillsDir();
      final f = File('${dir.path}/$id.md');
      if (f.existsSync()) return f.readAsStringSync();
    } catch (_) {}
    try {
      final raw = _prefs.getStringList(_kFallbackKey) ?? const [];
      for (final e in raw) {
        final skill = Skill.fromJson(jsonDecode(e) as Map<String, dynamic>);
        if (skill.id == id) return skill.markdown;
      }
    } catch (_) {}
    return '';
  }

  /// Push every skill to the daemon so the agent can follow them. Returns
  /// how many synced (0 when no VPS configured).
  Future<int> syncToServer({required String baseUrl, required String secret}) async {
    final skills = await all();
    var synced = 0;
    final client = HttpClient();
    try {
      for (final skill in skills) {
        final req = await client.postUrl(Uri.parse('$baseUrl/v1/skills'));
        req.headers.set('X-Gork-Secret', secret);
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode({
          'id': skill.id,
          'title': skill.title,
          'markdown': skill.markdown,
        })));
        final res = await req.close();
        await res.drain();
        if (res.statusCode == 200 || res.statusCode == 201) synced++;
      }
    } catch (_) {
      return synced;
    } finally {
      client.close();
    }
    await _prefs.setString(_kSyncKey, DateTime.now().millisecondsSinceEpoch.toString());
    return synced;
  }
}
