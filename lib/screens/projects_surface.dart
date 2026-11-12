import 'package:flutter/material.dart';

import '../services/locator.dart';
import '../services/projects_store.dart';
import '../widgets/glass.dart';
import 'projects_screen.dart';

/// Projects tab: projects are FOLDERS — each folder holds its own chats and
/// shared resources (files, images, notes). This surface lists the folders;
/// tapping one opens the workspace detail where chats and resources live.
class ProjectsSurface extends StatelessWidget {
  const ProjectsSurface({super.key, this.onOpenChat});

  /// Called when the user opens (or creates) a chat inside a project — the
  /// shell switches to the Chat tab with that conversation.
  final ValueChanged<String>? onOpenChat;

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final projects = Locator.projects.all();
    if (projects.isEmpty) {
      return _EmptyProjects(onCreate: () => _push(context, const ProjectsScreen()));
    }
    return ListView(
      key: const ValueKey('projects-folder-list'),
      padding: const EdgeInsets.all(16),
      children: [
        for (final project in projects)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FolderCard(
              project: project,
              onTap: () => _push(
                context,
                ProjectDetailScreen(projectId: project.id, onOpenChat: onOpenChat),
              ),
            ),
          ),
      ],
    );
  }
}

/// A folder card in the projects list: folder glyph, title, and what is
/// inside (chats / files / images).
class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.project, required this.onTap});

  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('folder-${project.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.folder_outlined, size: 26, color: Colors.black87),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${project.chats.length} chats · '
                    '${project.files.length} files · '
                    '${project.images.length} images',
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassContainer(
        radius: 28,
        opacity: 0.45,
        width: MediaQuery.of(context).size.width - 32,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_outlined, size: 28, color: Colors.black87),
            const SizedBox(height: 12),
            const Text(
              'No projects yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Projects are folders that hold chats, notes, files and '
              'images for one goal.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            GlassContainer(
              radius: 30,
              opacity: 0.35,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: GestureDetector(
                key: const ValueKey('create-project'),
                behavior: HitTestBehavior.opaque,
                onTap: onCreate,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 18, color: Colors.black87),
                    SizedBox(width: 8),
                    Text(
                      'Create a project',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
