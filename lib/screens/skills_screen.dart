import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/locator.dart';
import '../services/skills_store.dart';
import '../widgets/glass.dart';
import '../widgets/screen.dart';

/// Movement 69 — Skills: the agent's memory of HOW to do things, as plain
/// markdown files. The user teaches one, or gork replies in chat with a
/// ```gork-skill fenced block and it saves itself. Every skill syncs to the
/// VPS so the agent can follow it in later sessions.
class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  List<Skill> _skills = [];
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final skills = await Locator.skills.all();
    if (mounted) setState(() => _skills = skills);
  }

  Future<void> _openEditor([Skill? skill]) async {
    final titleController = TextEditingController(text: skill?.title ?? '');
    final bodyController = TextEditingController(text: skill?.body ?? '');
    await showGorkSheet<void>(
      context: context,
      fullTall: true,
      builder: (sheetContext) {
        final palette = paletteOf(sheetContext);
        return Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(skill == null ? 'Teach a skill' : 'Edit skill',
                  style: TypeScale.title(color: palette.textPrimary)),
              const SizedBox(height: Spacing.sm),
              Text(
                'Steps gork should follow next time. Plain words, numbered '
                'steps — like leaving a note to yourself.',
                style: TypeScale.bodySmall(color: palette.textSecondary),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: const ValueKey('skill-title'),
                controller: titleController,
                style: TypeScale.body(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Skill name (e.g. Weekly backup)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              Expanded(
                child: TextField(
                  key: const ValueKey('skill-body'),
                  controller: bodyController,
                  style: TypeScale.body(color: palette.textPrimary),
                  maxLines: null,
                  expands: true,
                  decoration: const InputDecoration(
                    hintText: '1. Open…\n2. Run…\n3. Check that…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(sheetContext),
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: GlassColors.fillStrong,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: GlassColors.border),
                        ),
                        child: Text('Cancel',
                            style: TextStyle(
                                fontSize: 16, color: palette.textPrimary)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        final title = titleController.text.trim();
                        if (title.isEmpty) return;
                        await Locator.skills.save(
                            id: skill?.id,
                            title: title,
                            body: bodyController.text.trim());
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.primary,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text('Save skill',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: palette.onPrimary)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    _refresh();
    _sync();
  }

  Future<void> _sync() async {
    final vps = Locator.prefs.getString('vps.url');
    final secret = Locator.prefs.getString('vps.secret');
    if (vps == null || vps.isEmpty) return;
    setState(() => _syncing = true);
    try {
      await Locator.skills.syncToServer(baseUrl: vps, secret: secret ?? '');
    } catch (_) {
      // Offline — skills stay local and sync next open.
    }
    if (mounted) setState(() => _syncing = false);
  }

  Future<void> _openSkill(Skill skill) async {
    final md = await Locator.skills.read(skill.id);
    if (!mounted) return;
    await showGorkSheet<void>(
      context: context,
      fullTall: true,
      builder: (sheetContext) {
        final palette = paletteOf(sheetContext);
        return Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(skill.title,
                        style: TypeScale.title(color: palette.textPrimary)),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      await Locator.skills.delete(skill.id);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      _refresh();
                    },
                    child: Icon(Icons.delete_outline,
                        size: 22, color: palette.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(md.isEmpty ? skill.body : md,
                      style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: palette.textPrimary)),
                ),
              ),
              const SizedBox(height: Spacing.md),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _openEditor(skill);
                    },
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: GlassColors.fillStrong,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: GlassColors.border),
                      ),
                      child: Text('Edit',
                          style: TextStyle(
                              fontSize: 16, color: palette.textPrimary)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(sheetContext),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: palette.primary,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text('Done',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: palette.onPrimary)),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Screen(
      title: 'Skills',
      body: Column(
        children: [
          Expanded(
            child: _skills.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_stories_outlined,
                              size: 44, color: palette.textTertiary),
                          const SizedBox(height: 16),
                          Text(
                            'No skills yet. Teach one below, or just tell '
                            'gork in chat how you want something done — it '
                            'saves the steps here by itself.',
                            textAlign: TextAlign.center,
                            style: TypeScale.body(
                                color: palette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                    children: [
                      for (final skill in _skills)
                        _SkillRow(
                          skill: skill,
                          onTap: () => _openSkill(skill),
                        ),
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey('skill-teach'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openEditor(),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: palette.primary,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text('Teach a skill',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: palette.onPrimary)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({required this.skill, required this.onTap});

  final Skill skill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 16),
            child: Row(
              children: [
                Icon(Icons.auto_stories_outlined,
                    size: 24, color: palette.textPrimary),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(skill.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TypeScale.body(color: palette.textPrimary)),
                ),
                Icon(Icons.chevron_right,
                    size: 24, color: palette.textSecondary),
              ],
            ),
          ),
        ),
        Divider(color: GlassColors.divider, height: 1, indent: Spacing.md),
      ],
    );
  }
}
