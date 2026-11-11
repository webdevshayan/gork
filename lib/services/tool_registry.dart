import 'llm_client.dart';
import 'locator.dart';
import 'memory_store.dart';
import 'panels_store.dart';
import 'projects_store.dart';
import 'tasks_store.dart';
import 'vault_store.dart';
import 'weather_service.dart';

/// The tools gork may call during a chat. Every tool touches something real
/// on the device: memory, projects, tasks, panels, vault, weather.
class ToolRegistry {
  final MemoryStore memory;
  final ProjectsStore projects;
  final TasksStore tasks;
  final PanelsStore panels;
  final VaultStore vault;
  final WeatherService weather;

  ToolRegistry({
    required this.memory,
    required this.projects,
    required this.tasks,
    required this.panels,
    required this.vault,
    required this.weather,
  });

  List<ToolDef> get defs => const [
        ToolDef('remember', 'Store a fact the user wants remembered across sessions.', {
          'type': 'object',
          'properties': {
            'fact': {'type': 'string', 'description': 'The fact to remember'}
          },
          'required': ['fact'],
        }),
        ToolDef('list_memory', 'List everything remembered about the user.', {
          'type': 'object',
          'properties': {},
        }),
        ToolDef('create_project', 'Create a project workspace with notes.', {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'notes': {'type': 'string'}
          },
          'required': ['title'],
        }),
        ToolDef('list_projects', 'List project titles and file counts.', {
          'type': 'object',
          'properties': {},
        }),
        ToolDef('create_task', 'Schedule a recurring AI task.', {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'prompt': {'type': 'string'},
            'repeatMinutes': {'type': 'integer'}
          },
          'required': ['title', 'prompt'],
        }),
        ToolDef('create_panel', 'Add a panel card to the dashboards screen.', {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'value': {'type': 'string'}
          },
          'required': ['title'],
        }),
        ToolDef('save_vault_entry', 'Store a secret in the encrypted vault.', {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
            'username': {'type': 'string'},
            'secret': {'type': 'string'}
          },
          'required': ['title', 'secret'],
        }),
        ToolDef('get_weather', 'Current weather for the user\u2019s location.', {
          'type': 'object',
          'properties': {},
        }),
      ];

  /// Execute a tool call, returning the text result for the model.
  Future<String> execute(String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'remember':
        final fact = (args['fact'] as String?)?.trim() ?? '';
        if (fact.isEmpty) return 'error: fact is empty';
        await memory.remember(fact);
        return 'remembered: $fact';

      case 'list_memory':
        final facts = memory.all();
        return facts.isEmpty ? 'memory is empty' : facts.join('\n');

      case 'create_project':
        final title = (args['title'] as String?)?.trim() ?? '';
        if (title.isEmpty) return 'error: title is empty';
        final now = DateTime.now().millisecondsSinceEpoch;
        await projects.save(Project(
          id: now.toString(),
          title: title,
          notes: args['notes'] as String? ?? '',
          files: const [],
          createdAt: now,
          updatedAt: now,
        ));
        return 'project created: $title';

      case 'list_projects':
        final all = projects.all();
        return all.isEmpty
            ? 'no projects'
            : [for (final p in all) '${p.title} (${p.files.length} files)']
                .join('\n');

      case 'create_task':
        final title = (args['title'] as String?)?.trim() ?? '';
        final prompt = (args['prompt'] as String?)?.trim() ?? '';
        if (title.isEmpty || prompt.isEmpty) return 'error: title and prompt required';
        final minutes = (args['repeatMinutes'] as num?)?.toInt() ?? 60;
        await tasks.save(ScheduledTask(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: title,
          prompt: prompt,
          repeatMinutes: minutes.clamp(5, 1440),
          enabled: true,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        return 'task scheduled: $title every $minutes minutes';

      case 'create_panel':
        final title = (args['title'] as String?)?.trim() ?? '';
        if (title.isEmpty) return 'error: title is empty';
        await panels.save(PanelSpec(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: title,
          kind: PanelKind.metric,
          source: PanelSource.manual,
          manualValue: args['value'] as String? ?? '',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        return 'panel created: $title';

      case 'save_vault_entry':
        final title = (args['title'] as String?)?.trim() ?? '';
        final secret = (args['secret'] as String?)?.trim() ?? '';
        if (title.isEmpty || secret.isEmpty) return 'error: title and secret required';
        final now = DateTime.now().millisecondsSinceEpoch;
        await vault.save(VaultEntry(
          id: now.toString(),
          title: title,
          username: args['username'] as String? ?? '',
          secret: secret,
          notes: '',
          createdAt: now,
        ));
        return 'vault entry saved: $title';

      case 'get_weather':
        try {
          final w = await weather.fetch(
              lat: Locator.ambientLat, lon: Locator.ambientLon);
          return '${w.tempC.toStringAsFixed(1)}°C, ${w.label}, '
              'wind ${w.windKmh.toStringAsFixed(0)} km/h';
        } catch (e) {
          return 'weather unavailable: $e';
        }

      default:
        return 'error: unknown tool $name';
    }
  }
}

/// Convenience constructor with the app's real services.
ToolRegistry buildAppToolRegistry() => ToolRegistry(
      memory: Locator.memory,
      projects: Locator.projects,
      tasks: Locator.tasks,
      panels: Locator.panels,
      vault: Locator.vault,
      weather: Locator.weather,
    );
