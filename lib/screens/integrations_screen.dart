import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/integrations.dart';
import '../services/locator.dart';
import '../widgets/g_button.dart';
import '../widgets/screen.dart';
import '../widgets/glass.dart';
import 'accounts_screen.dart';
import 'google_accounts_screen.dart';
import 'providers_screen.dart';

/// Movement 69 — Connections, ChatGPT-style. ONE screen, ONE list: every
/// outside service gork can act through, each with a one-tap Connect.
/// Google is first — a real one-tap sign-in guided inside its own screen
/// (Android client, no credentials.json hunt). Tokens for the rest are
/// verified on save and sealed on this device. No separate "Integrations"
/// or "Accounts" screens to hunt through any more: connections, skills,
/// providers — everything a person signs INTO lives here.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final Map<String, bool> _connected = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    for (final i in kIntegrations) {
      _connected[i.id] = await Locator.integrations.isConnected(i.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _openEditor(BuildContext context, IntegrationDef def) async {
    final palette = paletteOf(context);
    final tokenController = TextEditingController();
    String? testResult;
    Color? testColor;

    await showGorkSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: Spacing.lg,
                right: Spacing.lg,
                top: Spacing.lg,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + Spacing.lg,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connect ${def.name}',
                        style: TypeScale.title(color: palette.textPrimary)),
                    const SizedBox(height: Spacing.xs),
                    Text(def.tokenHint,
                        style: TypeScale.caption(color: palette.textTertiary)),
                    const SizedBox(height: Spacing.md),
                    TextField(
                      controller: tokenController,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: TypeScale.code(color: palette.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'paste your ${def.tokenLabel}',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    if (testResult != null) ...[
                      Text(testResult!,
                          style: TypeScale.bodySmall(color: testColor)),
                      const SizedBox(height: Spacing.md),
                    ],
                    // One-click connect: ONE button that saves, verifies and
                    // closes. If verification fails nothing is stored and the
                    // sheet stays open with the honest error.
                    GButton(
                      label: 'Connect',
                      onPressed: () async {
                        final t = tokenController.text.trim();
                        if (t.isEmpty) return;
                        setSheetState(() {
                          testResult = 'Verifying…';
                          testColor = palette.textSecondary;
                        });
                        final result = await Locator.integrations
                            .testConnection(def.id, tokenOverride: t);
                        if (result != null) {
                          setSheetState(() {
                            testResult = 'Failed: $result';
                            testColor = palette.error;
                          });
                          return;
                        }
                        await Locator.integrations.vault.setToken(def.id, t);
                        await _refresh();
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                      expands: true,
                    ),
                    const SizedBox(height: Spacing.sm),
                    Text('One-time setup — it stays connected until you '
                        'remove it. No expiry, no re-auth prompts.',
                        style:
                            TypeScale.caption(color: palette.textTertiary)),
                    if (_connected[def.id] == true) ...[
                      const SizedBox(height: Spacing.sm),
                      GButton(
                        label: 'Disconnect',
                        variant: ButtonVariant.ghost,
                        onPressed: () async {
                          await Locator.integrations.vault.clearToken(def.id);
                          await _refresh();
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        expands: true,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Screen(
      title: 'Connections',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            child: Text(
              'Everything gork can act through, connected in one tap — and '
              'staying connected.',
              style: TypeScale.body(color: palette.textSecondary),
            ),
          ),
          const SizedBox(height: Spacing.md),

          // --- Google: the flagship one-tap connection ---
          _ConnectionRow(
            key: const ValueKey('connection-google'),
            name: 'Google',
            detail: 'Gmail, Google Docs and YouTube in one sign-in',
            connectedText: 'Connected',
            icon: Icons.account_circle_outlined,
            connected: Locator.prefs.getBool('google.connectedHint') ?? false,
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const GoogleAccountsScreen()));
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: Spacing.sm),

          // --- The rest: one-click token connections ---
          for (final def in kIntegrations) ...[
            _ConnectionRow(
              key: ValueKey('connection-${def.id}'),
              name: def.name,
              detail: connectedRowDetail(def),
              connectedText: 'Connected',
              icon: Icons.link,
              connected: _connected[def.id] ?? false,
              onTap: () => _openEditor(context, def),
            ),
            const SizedBox(height: Spacing.sm),
          ],

          const SizedBox(height: Spacing.md),
          Divider(color: GlassColors.divider, height: 1),
          const SizedBox(height: Spacing.md),

          // --- Website accounts (what gork logged into FOR you) ---
          _ConnectionRow(
            key: const ValueKey('connection-accounts'),
            name: 'Website accounts',
            detail: 'Accounts gork signed into from the in-app browser',
            connectedText: '',
            icon: Icons.public,
            connected: false,
            showChevronOnly: true,
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AccountsScreen()));
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: Spacing.sm),
          _ConnectionRow(
            key: const ValueKey('connection-providers'),
            name: 'AI providers',
            detail: 'OpenAI, Gemini, Anthropic or your own endpoint',
            connectedText: '',
            icon: Icons.key_outlined,
            connected: false,
            showChevronOnly: true,
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProvidersScreen()));
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

String connectedRowDetail(IntegrationDef def) =>
    def.id == 'gmail'
        ? 'Gmail over your own token — reads, drafts, labels'
        : 'Connect with your own ${def.tokenLabel}';

/// One connection row: flat, bordered, one obvious tap. Connected rows
/// show a quiet green check; unconnected ones a Connect pill.
class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    super.key,
    required this.name,
    required this.detail,
    required this.connectedText,
    required this.icon,
    required this.connected,
    required this.onTap,
    this.showChevronOnly = false,
  });

  final String name;
  final String detail;
  final String connectedText;
  final IconData icon;
  final bool connected;
  final VoidCallback onTap;
  final bool showChevronOnly;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: GlassColors.fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GlassColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 26, color: palette.textPrimary),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TypeScale.heading(color: palette.textPrimary)),
                    const SizedBox(height: 2),
                    Text(detail,
                        style: TypeScale.caption(color: palette.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (connected) ...[
                Icon(Icons.check_circle_outline,
                    size: 20, color: palette.success),
                const SizedBox(width: 4),
                Text('Connected',
                    style: TypeScale.caption(color: palette.success)),
              ] else if (showChevronOnly)
                Icon(Icons.chevron_right,
                    size: 24, color: palette.textSecondary)
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Connect',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: palette.onPrimary)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
