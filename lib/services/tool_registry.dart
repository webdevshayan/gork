import 'github_service.dart';
import 'integrations.dart';
import 'llm_client.dart';
import 'locator.dart';
import 'slack_service.dart';
import 'spotify_service.dart';
import 'strava_service.dart';
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
  final Integrations? integrations;

  ToolRegistry({
    required this.memory,
    required this.projects,
    required this.tasks,
    required this.panels,
    required this.vault,
    required this.weather,
    this.integrations,
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
        ToolDef('github_notifications',
            'List unread GitHub notifications for the connected account.', {
          'type': 'object',
          'properties': {},
        }),
        ToolDef('github_list_issues',
            'List open issues of a GitHub repository (no pull requests).', {
          'type': 'object',
          'properties': {
            'repo': {
              'type': 'string',
              'description': 'owner/repo, e.g. webdevshayan/gork'
            }
          },
          'required': ['repo'],
        }),
        ToolDef('github_create_issue',
            'Create an issue in a GitHub repository as the user.', {
          'type': 'object',
          'properties': {
            'repo': {'type': 'string'},
            'title': {'type': 'string'},
            'body': {'type': 'string'}
          },
          'required': ['repo', 'title'],
        }),
        ToolDef('slack_list_channels',
            'List Slack channels the connected bot can see.', {
          'type': 'object',
          'properties': {},
        }),
        ToolDef('slack_post_message',
            'Post a message to a Slack channel as the bot.', {
          'type': 'object',
          'properties': {
            'channel': {
              'type': 'string',
              'description': 'channel name or ID, e.g. #general'
            },
            'text': {'type': 'string'}
          },
          'required': ['channel', 'text'],
        }),
        ToolDef('strava_recent_activities',
            'List the user\u2019s recent Strava activities.', {
          'type': 'object',
          'properties': {},
        }),
        ToolDef('spotify_now_playing',
            'Show the track currently playing on Spotify.', {
          'type': 'object',
          'properties': {},
        }),
        ToolDef('spotify_play_pause',
            'Toggle play/pause on the active Spotify device.', {
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

      case 'github_notifications':
        return _runTool<GitHubService>('github', 'github_notifications',
            () => integrations!.githubService(), (gh) => gh.notifications()
                .then((l) =>
                    l.isEmpty ? 'no unread notifications' : l.join('\n')));

      case 'github_list_issues':
        final repo = (args['repo'] as String?)?.trim() ?? '';
        if (repo.isEmpty || !repo.contains('/')) {
          return 'error: repo must be owner/repo';
        }
        return _runTool<GitHubService>('github', 'github_list_issues',
            () => integrations!.githubService(), (gh) => gh.openIssues(repo)
                .then((l) =>
                    l.isEmpty ? 'no open issues in $repo' : l.join('\n')));

      case 'github_create_issue':
        final cRepo = (args['repo'] as String?)?.trim() ?? '';
        final title = (args['title'] as String?)?.trim() ?? '';
        if (cRepo.isEmpty || !cRepo.contains('/') || title.isEmpty) {
          return 'error: repo and title required';
        }
        return _runTool<GitHubService>('github', 'github_create_issue',
            () => integrations!.githubService(), (gh) => gh.createIssue(
              cRepo,
              title: title,
              body: args['body'] as String? ?? '',
            ));

      case 'slack_list_channels':
        return _runTool<SlackService>('slack', 'slack_list_channels',
            () => integrations!.slackService(),
            (s) => s.channels().then((l) =>
                l.isEmpty ? 'no channels visible' : l.join('\n')));

      case 'slack_post_message':
        final channel = (args['channel'] as String?)?.trim() ?? '';
        final text = (args['text'] as String?)?.trim() ?? '';
        if (channel.isEmpty || text.isEmpty) {
          return 'error: channel and text required';
        }
        return _runTool<SlackService>('slack', 'slack_post_message',
            () => integrations!.slackService(),
            (s) => s.postMessage(channel: channel, text: text));

      case 'strava_recent_activities':
        return _runTool<StravaService>(
            'strava', 'strava_recent_activities',
            () => integrations!.stravaService(),
            (s) => s.recentActivities().then((l) => l.isEmpty
                ? 'no recent activities'
                : l.join('\n')));

      case 'spotify_now_playing':
        return _runTool<SpotifyService>('spotify', 'spotify_now_playing',
            () => integrations!.spotifyService(), (s) => s.nowPlaying());

      case 'spotify_play_pause':
        return _runTool<SpotifyService>('spotify', 'spotify_play_pause',
            () => integrations!.spotifyService(), (s) => s.playPause());

      default:
        return 'error: unknown tool $name';
    }
  }

  /// Run an integration-backed tool; maps connection problems to friendly
  /// text so the model can explain them to the user.
  Future<String> _runTool<T>(String integrationId, String tool,
      Future<T?> Function() make, Future<String> Function(T) run) async {
    final integ = integrations;
    if (integ == null) return 'error: integrations unavailable on this build';
    final T? service = await make();
    if (service == null) {
      return 'error: $integrationId not connected — add a token in Integrations';
    }
    try {
      return await run(service);
    } on IntegrationException catch (e) {
      return 'error: ${e.message}';
    } catch (e) {
      return 'error: $tool failed: $e';
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
      integrations: Locator.integrations,
    );
