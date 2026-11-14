import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

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
      backgroundColor: Colors.transparent,
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

/// Detail view: chats + notes + files + images for one project. Projects
/// are folders: every chat below belongs to this folder and shares its
/// resources as context.
class ProjectDetailScreen extends StatefulWidget {
  final String projectId;

  /// Called when a project chat is opened or created — the shell switches
  /// to the Chat tab with that conversation id.
  final ValueChanged<String>? onOpenChat;

  const ProjectDetailScreen({
    super.key,
    required this.projectId,
    this.onOpenChat,
  });

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
      backgroundColor: Colors.transparent,
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

  Future<void> _newChat() async {
    final project = _project;
    if (project == null) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final chats = [
      ...project.chats,
      ProjectChat(id, 'New chat', DateTime.now().millisecondsSinceEpoch),
    ];
    await Locator.projects.save(project.copyWith(
      chats: chats,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    _refresh();
    widget.onOpenChat?.call(id);
  }

  Future<void> _openChat(String chatId) async {
    widget.onOpenChat?.call(chatId);
  }

  Future<void> _addImage() async {
    final project = _project;
    if (project == null) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 80,
      );
      if (picked == null) return;
      final dir = await getApplicationSupportDirectory();
      final imagesDir = Directory('${dir.path}/project-images');
      if (!imagesDir.existsSync()) imagesDir.createSync(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${imagesDir.path}/$stamp.jpg');
      await file.writeAsBytes(await picked.readAsBytes());
      final images = [
        ...project.images,
        ProjectImage('image-$stamp.jpg', file.path),
      ];
      await Locator.projects.save(project.copyWith(
        images: images,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add that image.')),
        );
      }
    }
  }

  Future<void> _showFile(ProjectFile file) async {
    final palette = paletteOf(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
          // ---- Chats: this project's own conversations ----------------
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Chats',
                  style: TypeScale.heading(color: palette.textPrimary)),
              GButton(
                key: const ValueKey('new-project-chat'),
                label: 'New chat',
                onPressed: _newChat,
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          if (project.chats.isEmpty)
            Text('No chats in this folder yet.',
                style: TypeScale.bodySmall(color: palette.textTertiary)),
          for (final chat in project.chats)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: GCard(
                child: InkWell(
                  key: ValueKey('open-chat-${chat.id}'),
                  borderRadius: BorderRadius.circular(RadiusTokens.lg),
                  onTap: () => _openChat(chat.id),
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 20, color: palette.primary),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          Locator.history.byId(chat.id)?.title ?? chat.title,
                          style: TypeScale.body(color: palette.textPrimary),
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 18, color: palette.textTertiary),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: Spacing.md),
          // ---- Files (text resources) ---------------------------------
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
          const SizedBox(height: Spacing.md),
          // ---- Images (visual resources) ------------------------------
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Images',
                  style: TypeScale.heading(color: palette.textPrimary)),
              GButton(
                label: 'Add image',
                onPressed: _addImage,
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          if (project.images.isEmpty)
            Text('No images yet.',
                style: TypeScale.bodySmall(color: palette.textTertiary)),
          if (project.images.isNotEmpty)
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: project.images.length,
                separatorBuilder: (_, __) => const SizedBox(width: Spacing.sm),
                itemBuilder: (context, index) {
                  final image = project.images[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(RadiusTokens.lg),
                    child: Image.file(
                      File(image.path),
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 96,
                        height: 96,
                        color: palette.surface,
                        child: Icon(Icons.broken_image_outlined,
                            color: palette.textTertiary),
                      ),
                    ),
                  );
                },
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
