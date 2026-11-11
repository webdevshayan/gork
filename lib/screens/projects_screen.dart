import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/locator.dart';
import '../services/projects_store.dart';
import '../widgets/g_button.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';

/// Projects: long-running workspaces with their own notes and files.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Project> _projects = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() => _projects = Locator.projects.all());
  }

  Future<void> _createOrEdit([Project? existing]) async {
    final titleController = TextEditingController(text: existing?.title);
    final notesController = TextEditingController(text: existing?.notes);
    final palette = paletteOf(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RadiusTokens.xl)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: Spacing.lg,
            right: Spacing.lg,
            top: Spacing.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'New project' : 'Edit project',
                  style: TypeScale.title(color: palette.textPrimary)),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: titleController,
                style: TypeScale.body(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Project name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: notesController,
                minLines: 3,
                maxLines: 8,
                style: TypeScale.body(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Notes…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              GButton(
                label: 'Save project',
                expands: true,
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isEmpty) return;
                  final now = DateTime.now().millisecondsSinceEpoch;
                  final project = (existing == null)
                      ? Project(
                          id: now.toString(),
                          title: title,
                          notes: notesController.text.trim(),
                          files: const [],
                          createdAt: now,
                          updatedAt: now,
                        )
                      : existing.copyWith(
                          title: title,
                          notes: notesController.text.trim(),
                          updatedAt: now,
                        );
                  Locator.projects.save(project);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Screen(
      title: 'Projects',
      fab: FloatingActionButton(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        child: const Icon(Icons.add),
        onPressed: () => _createOrEdit(),
      ),
      body: _projects.isEmpty
          ? GCard(
              child: Text(
                'No projects yet. Tap + to create your first workspace.',
                style: TypeScale.body(color: palette.textSecondary),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: Spacing.md),
              itemCount: _projects.length,
              itemBuilder: (context, index) {
                final p = _projects[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.md),
                  child: GCard(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(RadiusTokens.lg),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ProjectDetailScreen(projectId: p.id)),
                        );
                        _refresh();
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.title,
                              style: TypeScale.heading(color: palette.textPrimary)),
                          if (p.notes.isNotEmpty) ...[
                            const SizedBox(height: Spacing.xs),
                            Text(
                              p.notes,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TypeScale.bodySmall(
                                  color: palette.textSecondary),
                            ),
                          ],
                          const SizedBox(height: Spacing.sm),
                          Text(
                            '${p.files.length} file(s)',
                            style: TypeScale.caption(color: palette.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Detail view: notes + files for one project.
class ProjectDetailScreen extends StatefulWidget {
  final String projectId;

  const ProjectDetailScreen({super.key, required this.projectId});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  Project? _project;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() => _project = Locator.projects.byId(widget.projectId));
  }

  Future<void> _addFile() async {
    final nameController = TextEditingController();
    final contentController = TextEditingController();
    final palette = paletteOf(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RadiusTokens.xl)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: Spacing.lg,
            right: Spacing.lg,
            top: Spacing.lg,
            bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New file', style: TypeScale.title(color: palette.textPrimary)),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: nameController,
                style: TypeScale.code(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'notes.md',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: contentController,
                minLines: 3,
                maxLines: 10,
                style: TypeScale.code(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'File content…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              GButton(
                label: 'Save file',
                expands: true,
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty || _project == null) return;
                  final files = [
                    ..._project!.files,
                    ProjectFile(name, contentController.text),
                  ];
                  Locator.projects.save(_project!.copyWith(
                    files: files,
                    updatedAt: DateTime.now().millisecondsSinceEpoch,
                  ));
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
    _refresh();
  }

  Future<void> _showFile(ProjectFile file) async {
    final palette = paletteOf(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RadiusTokens.xl)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name,
                    style: TypeScale.heading(color: palette.textPrimary)),
                const SizedBox(height: Spacing.md),
                SelectableText(file.content,
                    style: TypeScale.code(color: palette.textPrimary)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final project = _project;
    if (project == null) {
      return const Screen(title: 'Project', body: SizedBox.shrink());
    }
    return Screen(
      title: project.title,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        children: [
          GCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notes', style: TypeScale.caption(color: palette.textSecondary)),
                const SizedBox(height: Spacing.xs),
                SelectableText(
                  project.notes.isEmpty ? 'No notes yet.' : project.notes,
                  style: TypeScale.body(color: palette.textPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Files',
                  style: TypeScale.heading(color: palette.textPrimary)),
              GButton(
                label: 'Add file',
                onPressed: _addFile,
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          if (project.files.isEmpty)
            Text('No files yet.',
                style: TypeScale.bodySmall(color: palette.textTertiary)),
          for (final file in project.files)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: GCard(
                child: InkWell(
                  borderRadius: BorderRadius.circular(RadiusTokens.lg),
                  onTap: () => _showFile(file),
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined,
                          size: 20, color: palette.primary),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(file.name,
                            style: TypeScale.code(color: palette.textPrimary)),
                      ),
                      Icon(Icons.chevron_right,
                          size: 18, color: palette.textTertiary),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: Spacing.lg),
          GButton(
            label: 'Delete project',
            variant: ButtonVariant.ghost,
            onPressed: () async {
              await Locator.projects.delete(project.id);
              if (context.mounted) Navigator.pop(context);
            },
            expands: true,
          ),
        ],
      ),
    );
  }
}
