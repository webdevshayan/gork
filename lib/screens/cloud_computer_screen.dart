import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/design_tokens.dart';
import '../services/cloud_computer_store.dart';
import '../services/handoff_service.dart';
import '../services/locator.dart';
import '../services/secure_store.dart';
import '../widgets/g_button.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';

/// Cloud Computer settings: pick a backend, configure it, test it.
///
/// Movement 60 — ONE VPS setup. The self-hosted agent backend configures
/// THE VPS connection (`vps.url` + shared secret) that everything shares:
/// chat handoff, scheduled tasks, the browser agent, the sealed vault and
/// the credentials upload. No separate daemon URL or secret anywhere else.
class CloudComputerScreen extends StatefulWidget {
  const CloudComputerScreen({super.key, this.store});

  /// Injectable for tests; defaults to the keystore-backed store.
  final SecureStore? store;

  @override
  State<CloudComputerScreen> createState() => _CloudComputerScreenState();
}

class _CloudComputerScreenState extends State<CloudComputerScreen> {
  CloudComputerConfig _config = CloudComputerConfig(
      backend: CloudBackend.agentvps, endpoint: '', apiKey: '', updatedAt: 0);
  String? _status;
  String? _handoffStatus;
  String? _daemonVersion;
  late final TextEditingController _endpointController;
  late final TextEditingController _keyController;
  late final TextEditingController _vpsUrlController;
  final TextEditingController _vpsSecretController = TextEditingController();

  SecureStore get _store => widget.store ?? Locator.store;

  @override
  void initState() {
    super.initState();
    _config = Locator.cloudComputer.load();
    _endpointController = TextEditingController(text: _config.endpoint);
    _keyController = TextEditingController(text: _config.apiKey);
    _vpsUrlController = TextEditingController(text: Locator.handoff.url ?? '');
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _keyController.dispose();
    _vpsUrlController.dispose();
    _vpsSecretController.dispose();
    super.dispose();
  }

  Future<void> _persist(CloudComputerConfig config) async {
    await Locator.cloudComputer.save(config);
    setState(() => _config = config);
  }

  Future<void> _test() async {
    setState(() => _status = 'Testing…');
    // AgentVPS IS the gork daemon — test it with the real shared secret.
    final error = _config.backend == CloudBackend.agentvps
        ? await _pingHandoff()
        : await pingCloudComputer(_config, Locator.httpClient);
    setState(() {
      _status = error == null
          ? 'Connection OK — backend reachable.'
          : 'Failed: $error';
    });
  }

  Future<String?> _pingHandoff() async {
    try {
      await Locator.handoff.ping();
      // Movement 61: surface the daemon's version so "up to date" is a fact
      // the user can see, not a guess. Older daemons simply report nothing.
      final v = await Locator.handoff.daemonVersion().catchError((_) => null);
      if (v != null && mounted) setState(() => _daemonVersion = v);
      return null;
    } catch (e) {
      return e.toString().replaceFirst(RegExp(r'^(IntegrationException|Exception):\s*'), '');
    }
  }

  /// Saves the ONE VPS connection: address + shared secret. An empty secret
  /// keeps the saved one.
  Future<void> _saveVps() async {
    final url = _vpsUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _status = 'Enter the VPS address first (e.g. '
          'http://123.45.67.89:8787).');
      return;
    }
    await Locator.handoff.vps.save(url,
        token: _vpsSecretController.text.trim().isEmpty
            ? null
            : _vpsSecretController.text.trim());
    // Keep the picker config coherent — same server.
    await _persist(_config.copyWith(
      endpoint: url,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    _vpsSecretController.clear();
    setState(() {
      _status = 'Connection OK — saved. Chat, tasks, browser work, vault '
          'and credentials all use this VPS.';
      _vpsUrlController.text = url;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final endpointController = _endpointController;
    final keyController = _keyController;
    const installCommand =
        'curl -fsSL https://raw.githubusercontent.com/webdevshayan/gork/main/daemon/install.sh | bash';
    final isAgentVps = _config.backend == CloudBackend.agentvps;

    return Screen(
      title: 'Cloud Computer',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        children: [
          GCard(
            child: Text(
              'Where should gork run its autonomous browser work? '
              'Pick a backend — everything stays under your control.',
              style: TypeScale.body(color: palette.textSecondary),
            ),
          ),
          const SizedBox(height: Spacing.md),
          for (final backend in CloudBackend.values)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: GCard(
                child: InkWell(
                  borderRadius: BorderRadius.circular(RadiusTokens.lg),
                  onTap: () =>
                      _persist(CloudComputerConfig(
                        backend: backend,
                        endpoint: _config.endpoint,
                        apiKey: _config.apiKey,
                        updatedAt: DateTime.now().millisecondsSinceEpoch,
                      )),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Radio<CloudBackend>(
                        value: backend,
                        groupValue: _config.backend,
                        onChanged: (value) {
                          if (value != null) {
                            _persist(CloudComputerConfig(
                              backend: value,
                              endpoint: _config.endpoint,
                              apiKey: _config.apiKey,
                              updatedAt: DateTime.now().millisecondsSinceEpoch,
                            ));
                          }
                        },
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(backend.label,
                                style: TypeScale.heading(
                                    color: palette.textPrimary)),
                            const SizedBox(height: Spacing.xs),
                            Text(backend.blurb,
                                style: TypeScale.caption(
                                    color: palette.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (isAgentVps) ...[
            GCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your VPS — one setup for everything',
                      style: TypeScale.heading(color: palette.textPrimary)),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'This address and secret are shared by chat handoff, '
                    'scheduled tasks, the browser agent, the sealed vault '
                    'and the credentials upload. Set it once — done.',
                    style:
                        TypeScale.caption(color: palette.textSecondary),
                  ),
                  const SizedBox(height: Spacing.md),
                  Text('VPS address',
                      style: TypeScale.caption(color: palette.textSecondary)),
                  const SizedBox(height: Spacing.xs),
                  TextField(
                    key: const Key('vps-url'),
                    controller: _vpsUrlController,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.url,
                    style: TypeScale.code(color: palette.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'http://123.45.67.89:8787',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  Text('Shared secret (X-Gork-Secret, optional)',
                      style: TypeScale.caption(color: palette.textSecondary)),
                  const SizedBox(height: Spacing.xs),
                  TextField(
                    key: const Key('vps-secret'),
                    controller: _vpsSecretController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: TypeScale.code(color: palette.textPrimary),
                    decoration: InputDecoration(
                      hintText: Locator.handoff.configured
                          ? '(saved — leave empty to keep)'
                          : 'the daemon\'s shared secret',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  GButton(
                    key: const ValueKey('vps-save'),
                    label: 'Save VPS connection',
                    onPressed: _saveVps,
                    expands: true,
                  ),
                  const SizedBox(height: Spacing.sm),
                  GButton(
                    label: 'Test connection',
                    variant: ButtonVariant.secondary,
                    expands: true,
                    onPressed: Locator.handoff.configured ? _test : null,
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: Spacing.md),
                    Text(
                      _status!,
                      style: TypeScale.bodySmall(
                        color: _status!.startsWith('Connection OK')
                            ? palette.success
                            : palette.textSecondary,
                      ),
                    ),
                  ],
                  if (_daemonVersion != null) ...[
                    const SizedBox(height: Spacing.sm),
                    Text(
                      'gork daemon v$_daemonVersion is what that VPS runs '
                      '(update it from the VPS: gork daemon update — keys, '
                      'tasks and vault are kept).',
                      key: const ValueKey('vps-daemon-version'),
                      style:
                          TypeScale.caption(color: palette.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
            GCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Install on your VPS — paste this one line there:',
                      style: TypeScale.caption(color: palette.textSecondary)),
                  const SizedBox(height: Spacing.sm),
                  SelectableText(installCommand,
                      style: TypeScale.code(color: palette.textPrimary)),
                  const SizedBox(height: Spacing.sm),
                  GButton(
                    label: 'Copy command',
                    variant: ButtonVariant.secondary,
                    onPressed: () async {
                      await Clipboard.setData(
                          const ClipboardData(text: installCommand));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Copied to clipboard',
                                style: TypeScale.bodySmall(
                                    color: palette.onPrimary))));
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          if (!isAgentVps && _config.needsEndpoint) ...[
            Text('Endpoint URL',
                style: TypeScale.caption(color: palette.textSecondary)),
            const SizedBox(height: Spacing.xs),
            TextField(
              key: const Key('cloud-endpoint'),
              controller: endpointController,
              style: TypeScale.code(color: palette.textPrimary),
              decoration: const InputDecoration(
                hintText: 'http://123.45.67.89:8787',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          if (!isAgentVps && _config.needsApiKey) ...[
            Text('API key (stored only on this device)',
                style: TypeScale.caption(color: palette.textSecondary)),
            const SizedBox(height: Spacing.xs),
            TextField(
              controller: keyController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              style: TypeScale.code(color: palette.textPrimary),
              decoration: const InputDecoration(
                hintText: 'paste your key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          if (!isAgentVps) ...[
            GButton(
              label: 'Save',
              expands: true,
              onPressed: () => _persist(_config.copyWith(
                endpoint: endpointController.text.trim(),
                apiKey: keyController.text.trim(),
                updatedAt: DateTime.now().millisecondsSinceEpoch,
              )),
            ),
            const SizedBox(height: Spacing.sm),
            GButton(
              label: 'Test connection',
              variant: ButtonVariant.secondary,
              expands: true,
              onPressed: _config.isConfigured ? _test : null,
            ),
            if (_status != null) ...[
              const SizedBox(height: Spacing.md),
              Text(
                _status!,
                style: TypeScale.bodySmall(
                  color: _status!.startsWith('Connection OK')
                      ? palette.success
                      : palette.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: Spacing.xl),
          ],
          _buildHandoff(context, palette),
        ],
      ),
    );
  }

  /// Scheduled tasks ride the SAME VPS connection — status + sync actions
  /// only. There are no separate daemon credentials anywhere.
  Widget _buildHandoff(BuildContext context, Palette palette) {
    final handoff = Locator.handoff;
    final ntfyController =
        TextEditingController(text: handoff.ntfyTopic ?? '');
    final connected = handoff.configured;

    return GCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('24/7 Handoff (companion daemon)',
              style: TypeScale.heading(color: palette.textPrimary)),
          const SizedBox(height: Spacing.xs),
          Text(
            connected
                ? 'Connected to ${handoff.url} — the same server as chat, '
                    'browser work, the vault and the credentials upload. '
                    'One setup, nothing to duplicate.'
                : 'Keep tasks running while this phone sleeps. Set up the '
                    'VPS above, install the daemon, then sync.',
            style: TypeScale.caption(color: palette.textSecondary),
          ),
          const SizedBox(height: Spacing.md),
          Text('ntfy topic for push results (optional)',
              style: TypeScale.caption(color: palette.textSecondary)),
          const SizedBox(height: Spacing.xs),
          TextField(
            controller: ntfyController,
            style: TypeScale.code(color: palette.textPrimary),
            decoration: const InputDecoration(
              hintText: 'gork-my-phone-xyz',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.md),
          GButton(
            label: 'Save ntfy topic',
            onPressed: () async {
              await handoff.setNtfyTopic(ntfyController.text);
              if (mounted) {
                setState(() {
                  _handoffStatus = 'ntfy topic saved.';
                });
              }
            },
            expands: true,
          ),
          if (_handoffStatus != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(_handoffStatus!,
                style: TypeScale.caption(color: palette.textSecondary)),
          ],
          const SizedBox(height: Spacing.lg),
          Row(children: [
            Expanded(
              child: GButton(
                label: 'Test',
                variant: ButtonVariant.secondary,
                onPressed: connected
                    ? () async {
                        try {
                          final msg = await handoff.ping();
                          _showHandoff(msg, palette.success);
                        } catch (e) {
                          _showHandoff('Failed: $e', palette.error);
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: GButton(
                label: 'Sync now',
                variant: ButtonVariant.secondary,
                onPressed: connected
                    ? () async {
                        try {
                          final msg =
                              await handoff.pushTasks();
                          final msg2 = await handoff.pullTasks();
                          _showHandoff('$msg; $msg2', palette.success);
                        } catch (e) {
                          _showHandoff('Failed: $e', palette.error);
                        }
                      }
                    : null,
              ),
            ),
          ]),
          const SizedBox(height: Spacing.sm),
          GButton(
            label: 'Run due tasks on daemon',
            variant: ButtonVariant.ghost,
            onPressed: connected
                ? () async {
                    try {
                      _showHandoff(await handoff.triggerRun(), palette.success);
                    } catch (e) {
                      _showHandoff('Failed: $e', palette.error);
                    }
                  }
                : null,
            expands: true,
          ),
        ],
      ),
    );
  }

  void _showHandoff(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message, style: TypeScale.bodySmall(color: color))));
  }
}
