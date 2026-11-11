import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A text file inside a project.
class ProjectFile {
  final String name;
  final String content;

  const ProjectFile(this.name, this.content);

  Map<String, dynamic> toJson() => {'name': name, 'content': content};

  factory ProjectFile.fromJson(Map<String, dynamic> json) =>
      ProjectFile(json['name'] as String, json['content'] as String);
}

/// A long-running workspace with its own notes and files.
class Project {
  final String id;
  final String title;
  final String notes;
  final List<ProjectFile> files;
  final int createdAt;
  final int updatedAt;

  const Project({
    required this.id,
    required this.title,
    required this.notes,
    required this.files,
    required this.createdAt,
    required this.updatedAt,
  });

  Project copyWith({String? title, String? notes, List<ProjectFile>? files, int? updatedAt}) =>
      Project(
        id: id,
        title: title ?? this.title,
        notes: notes ?? this.notes,
        files: files ?? this.files,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'files': [for (final f in files) f.toJson()],
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        title: json['title'] as String,
        notes: json['notes'] as String? ?? '',
        files: [
          for (final f in (json['files'] as List? ?? []))
            ProjectFile.fromJson(f as Map<String, dynamic>)
        ],
        createdAt: json['createdAt'] as int,
        updatedAt: json['updatedAt'] as int,
      );
}

/// Projects persisted locally as JSON in shared_preferences.
class ProjectsStore {
  final SharedPreferences _prefs;

  ProjectsStore(this._prefs);

  static const String _kKey = 'projects.items';

  Map<String, Project> _load() {
    final raw = _prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in map.entries)
        e.key: Project.fromJson(e.value as Map<String, dynamic>)
    };
  }

  List<Project> all() {
    final list = _load().values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Project? byId(String id) => _load()[id];

  Future<void> save(Project project) async {
    final map = _load();
    map[project.id] = project;
    await _prefs.setString(_kKey,
        jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}));
  }

  Future<void> delete(String id) async {
    final map = _load();
    map.remove(id);
    await _prefs.setString(_kKey,
        jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}));
  }
}
