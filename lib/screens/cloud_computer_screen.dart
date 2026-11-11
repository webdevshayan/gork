import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/design_tokens.dart';
import '../services/cloud_computer_store.dart';
import '../services/locator.dart';
import '../widgets/g_button.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';

/// Cloud Computer settings: pick a backend, paste credentials, test it.
/// The actual browser agent runs later; connection + health check work today.
class CloudComputerScreen extends StatefulWidget {
  const CloudComputerScreen({super.key});

  @override
  State<CloudComputerScreen> createState() => _CloudComputerScreenState();
}

class _CloudComputerScreenState extends State<CloudComputerScreen> {
  CloudComputerConfig _config = CloudComputerConfig(
      backend: CloudBackend.agentvps, endpoint: '', apiKey: '', updatedAt: 0);
  String? _status;

  @override
  void initState() {
    super.initState();
    _config = Locator.cloudComputer.load();
  }

  Future<void> _persist(CloudComputerConfig config) async {
    await Locator.cloudComputer.save(config);
    setState(() => _config = config);
  }

  Future<void> _test() async {
    setState(() => _status = 'Testing…');
    final error = await pingCloudComputer(_config, Locator.httpClient);
    setState(() {
      _status = error == null
          ? 'Connection OK — backend reachable.'
          : 'Failed: $error';
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final endpointController = TextEditingController(text: _config.endpoint);
    final keyController = TextEditingController(text: _config.apiKey);
    const installCommand =
        'curl -fsSL https://raw.githubusercontent.com/webdevshayan/gork/main/daemon/install.sh | bash';

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
          if (_config.needsEndpoint) ...[
            Text('Endpoint URL',
                style: TypeScale.caption(color: palette.textSecondary)),
            const SizedBox(height: Spacing.xs),
            TextField(
              controller: endpointController,
              style: TypeScale.code(color: palette.textPrimary),
              decoration: const InputDecoration(
                hintText: 'http://123.45.67.89:8787',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          if (_config.needsApiKey) ...[
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
          if (_config.backend == CloudBackend.agentvps) ...[
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
        ],
      ),
    );
  }
}
