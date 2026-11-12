import 'package:flutter/material.dart';

import '../services/locator.dart';
import '../services/projects_store.dart';
import '../widgets/glass.dart';
import 'projects_screen.dart';

/// Projects tab, matching the reference's project conversation surface: a
/// project chip on the first card, the workspace's notes rendered as
/// assistant-style white bubbles, files as preview cards, and an
/// "Open workspace" pill. With no projects it offers creation instead.
class ProjectsSurface extends StatelessWidget {
  const ProjectsSurface({super.key});

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final projects = Locator.projects.all();
    if (projects.isEmpty) {
      return _EmptyProjects(onCreate: () => _push(context, const ProjectsScreen()));
    }
    final active = projects.first;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _BubbleChip(title: active.title),
        const SizedBox(height: 8),
        if (active.notes.isNotEmpty)
          _Bubble(text: active.notes)
        else
          const _Bubble(text: 'This workspace has no notes yet. Open it and '
              'add notes — the assistant can read them as context.'),
        const SizedBox(height: 16),
        for (final file in active.files.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _FilePreviewCard(file: file),
          ),
        const SizedBox(height: 8),
        GlassContainer(
          radius: 30,
          opacity: 0.35,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _push(context, const ProjectsScreen()),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_outlined, size: 20, color: Colors.black87),
                SizedBox(width: 10),
                Text(
                  'Open workspace',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The floating project chip that sits on top of the first bubble in the
/// reference (e.g. "School Project").
class _BubbleChip extends StatelessWidget {
  const _BubbleChip({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GlassContainer(
        key: const ValueKey('project-chip'),
        radius: 24,
        opacity: 0.65,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_outlined, size: 16, color: Colors.black87),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
          ),
        ),
      ),
    );
  }
}

class _FilePreviewCard extends StatelessWidget {
  const _FilePreviewCard({required this.file});

  final ProjectFile file;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined,
                  size: 16, color: Colors.black54),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            file.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
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
              'Projects are workspaces with notes and files for one goal.',
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
