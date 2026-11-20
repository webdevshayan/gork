import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/browser_service.dart';
import '../services/locator.dart';
import '../services/vault_store.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/glass.dart';
import 'cloud_computer_screen.dart';

/// Security — the credentials vault surface. Secrets (passwords, auth codes)
/// live in the vault and are only ever filled into forms at the user's
/// command; this screen shows WHAT is stored but never the secret itself.
/// Two sources, both listed by name only:
///   * this phone — the on-device encrypted vault;
///   * the VPS agent — the daemon's sealed vault (gork vault set), which is
///     what fill_secret actually draws from in the AI browser.
/// The wallet feature was removed (Movement 50); Security owns its own page.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key, this.browser});

  /// Test seam: the VPS client the screen reads vault labels from.
  final BrowserService? browser;

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  List<VaultEntry>? _entries;
  BrowserService? _browser;
  List<String>? _vpsLabels; // null = the fetch is still in flight
  bool _vpsReachable = false;

  @override
  void initState() {
    super.initState();
    final browser = widget.browser ?? BrowserService();
    _browser = browser;
    Locator.vault.all().then((entries) {
      if (mounted) setState(() => _entries = entries);
    });
    if (browser.configured) {
      browser.vaultLabels().then((labels) {
        if (!mounted) return;
        setState(() {
          _vpsReachable = labels != null;
          _vpsLabels = labels ?? const [];
        });
      });
    }
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: GlassColors.textFaint,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final browser = _browser;
    final vpsLabels = _vpsLabels;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientBackdrop(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                Row(
                  children: [
                    const GlassBackButton(label: 'Back to menu'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Security',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: GlassColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GlassContainer(
                  radius: 28,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 22, color: GlassColors.text),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Credentials vault',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: GlassColors.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Passwords and auth codes are stored in the vault '
                        'and are only filled into forms when you ask. The AI '
                        'selects what to fill by label — it can never read '
                        'the secret itself, on any website.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: GlassColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Movement 60 — the ONE VPS setup lives in Cloud Computer;
                // Security shows its state and routes there. One URL and
                // one secret serve chat, tasks, browser work, the vault
                // and the credentials upload.
                GlassContainer(
                  radius: 28,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.dns_outlined,
                              size: 22, color: GlassColors.text),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'VPS connection',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: GlassColors.text,
                              ),
                            ),
                          ),
                          Icon(
                            Locator.handoff.configured
                                ? Icons.check_circle_outline
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: Locator.handoff.configured
                                ? GlassColors.text
                                : GlassColors.textFaint,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Locator.handoff.configured
                            ? 'Connected to ${Locator.handoff.url} — the '
                                'same server for chat, tasks, browser work, '
                                'the vault and the credentials upload.'
                            : 'Not set up yet. One address and one shared '
                                'secret unlock chat handoff, scheduled '
                                'tasks, browser work, the vault and the '
                                'credentials upload.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: GlassColors.textDim,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const CloudComputerScreen()),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: GlassColors.text.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: GlassColors.border),
                          ),
                          child: Text(
                            Locator.handoff.configured
                                ? 'Change in Cloud Computer'
                                : 'Set up in Cloud Computer',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: GlassColors.text,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionLabel('On this phone'),
                if (entries == null)
                  GlassContainer(
                    radius: 28,
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: GlassColors.textDim,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else if (entries.isEmpty)
                  GlassContainer(
                    radius: 28,
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Nothing saved yet. When the AI fills a login for you, '
                      'the credentials are kept here — listed by name, never '
                      'shown.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: GlassColors.textDim,
                      ),
                    ),
                  )
                else
                  GlassContainer(
                    radius: 28,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final (i, entry) in entries.indexed) ...[
                          if (i > 0)
                            Divider(color: GlassColors.divider, height: 1),
                          GlassMenuRow(
                            key: ValueKey('vault-${entry.id}'),
                            icon: Icons.key_outlined,
                            label: entry.title,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  entry.username.isEmpty
                                      ? 'saved'
                                      : entry.username,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: GlassColors.textFaint,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  entry.aiAccess
                                      ? Icons.check_circle_outline
                                      : Icons.lock_outline,
                                  size: 16,
                                  color: GlassColors.textFaint,
                                  semanticLabel: entry.aiAccess
                                      ? 'AI may fill this entry'
                                      : 'AI may not read this entry',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                if (browser == null || !browser.configured)
                  GlassContainer(
                    radius: 28,
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'The AI browser and its sealed vault run on your VPS '
                      'agent. Connect one in Cloud Computer and its entries '
                      'are listed here too — by name, never by value.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: GlassColors.textDim,
                      ),
                    ),
                  )
                else ...[
                  _sectionLabel('On your VPS agent'),
                  if (vpsLabels == null)
                    GlassContainer(
                      radius: 28,
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: GlassColors.textDim,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  else if (!_vpsReachable)
                    GlassContainer(
                      radius: 28,
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        "Couldn't reach the VPS agent — is the daemon "
                        'running? Check the connection in Cloud Computer.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: GlassColors.textDim,
                        ),
                      ),
                    )
                  else if (vpsLabels.isEmpty)
                    GlassContainer(
                      radius: 28,
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No secrets on the agent yet. Add one on the box: '
                        'gork vault set <label> (the value comes from stdin, '
                        'never argv).',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: GlassColors.textDim,
                        ),
                      ),
                    )
                  else
                    GlassContainer(
                      radius: 28,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (final (i, label) in vpsLabels.indexed) ...[
                            if (i > 0)
                              Divider(color: GlassColors.divider, height: 1),
                            GlassMenuRow(
                              key: ValueKey('vps-vault-$label'),
                              icon: Icons.dns_outlined,
                              label: label,
                              trailing: Icon(
                                Icons.lock_outline,
                                size: 16,
                                color: GlassColors.textFaint,
                                semanticLabel:
                                    'value never leaves the agent',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
