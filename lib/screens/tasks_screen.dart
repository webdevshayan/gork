import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/locator.dart';
import '../services/scheduler.dart';
import '../services/tasks_store.dart';
import '../widgets/g_button.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';

/// Scheduled tasks: things that run on a timer, not on demand.
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<ScheduledTask> _tasks = [];
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() => _tasks = Locator.tasks.all());
  }

  String _lastRunLabel(int? lastRun) {
    if (lastRun == null) return 'never run';
    final d = DateTime.fromMillisecondsSinceEpoch(lastRun);
    return 'last run ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _create() async {
    final titleController = TextEditingController();
    final promptController = TextEditingController();
    final minutesController = TextEditingController(text: '60');
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
              Text('New scheduled task',
                  style: TypeScale.title(color: palette.textPrimary)),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: titleController,
                style: TypeScale.body(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Name (e.g. Morning news)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: promptController,
                minLines: 3,
                maxLines: 6,
                style: TypeScale.body(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'What should the AI do each time?',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: minutesController,
                keyboardType: TextInputType.number,
                style: TypeScale.code(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Repeat every N minutes',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              GButton(
                label: 'Save task',
                expands: true,
                onPressed: () {
                  final title = titleController.text.trim();
                  final prompt = promptController.text.trim();
                  final minutes = int.tryParse(minutesController.text.trim());
                  if (title.isEmpty || prompt.isEmpty || minutes == null) return;
                  Locator.tasks.save(ScheduledTask(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: title,
                    prompt: prompt,
                    repeatMinutes: minutes,
                    enabled: true,
                    createdAt: DateTime.now().millisecondsSinceEpoch,
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

  Future<void> _runNow(ScheduledTask task) async {
    setState(() => _message = 'Running "${task.title}"…');
    final error = await Locator.scheduler.runTask(
        task, DateTime.now());
    setState(() {
      _message =
          error == null ? 'Task finished — check notifications.' : error;
    });
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Screen(
      title: 'Scheduled tasks',
      fab: FloatingActionButton(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        child: const Icon(Icons.add),
        onPressed: _create,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: GCard(
              child: Text(
                'Tasks run while the app is open. The companion daemon '
                '(own VPS) will run them 24/7.',
                style: TypeScale.caption(color: palette.textSecondary),
              ),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Text(_message!,
                  style: TypeScale.caption(color: palette.textSecondary)),
            ),
          Expanded(
            child: _tasks.isEmpty
                ? GCard(
                    child: Text(
                      'No tasks yet. Tap + to schedule your first one.',
                      style: TypeScale.body(color: palette.textSecondary),
                    ),
                  )
                : ListView.builder(
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) {
                      final t = _tasks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.md),
                        child: GCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(t.title,
                                        style: TypeScale.heading(
                                            color: palette.textPrimary)),
                                  ),
                                  Switch(
                                    value: t.enabled,
                                    onChanged: (value) async {
                                      await Locator.tasks
                                          .save(t.copyWith(enabled: value));
                                      _refresh();
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: Spacing.xs),
                              Text(
                                'every ${t.repeatMinutes} min · ${_lastRunLabel(t.lastRun)}',
                                style: TypeScale.caption(
                                    color: palette.textTertiary),
                              ),
                              const SizedBox(height: Spacing.sm),
                              Row(
                                children: [
                                  GButton(
                                    label: 'Run now',
                                    onPressed: () => _runNow(t),
                                  ),
                                  const SizedBox(width: Spacing.sm),
                                  GButton(
                                    label: 'Delete',
                                    variant: ButtonVariant.ghost,
                                    onPressed: () async {
                                      await Locator.tasks.delete(t.id);
                                      _refresh();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
