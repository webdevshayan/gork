import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/integrations.dart';
import '../services/locator.dart';
import '../widgets/g_button.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';

/// Connect services (GitHub, Slack, Strava, Spotify, Gmail, PayPal) by
/// pasting your own token. Tokens are stored encrypted on this device only.
class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(RadiusTokens.xl)),
      ),
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
                    Text(def.name,
                        style: TypeScale.title(color: palette.textPrimary)),
                    const SizedBox(height: Spacing.xs),
                    Text(def.tokenHint,
                        style: TypeScale.caption(color: palette.textTertiary)),
                    const SizedBox(height: Spacing.md),
                    Text('${def.tokenLabel} (stored only on this device)',
                        style: TypeScale.caption(color: palette.textSecondary)),
                    const SizedBox(height: Spacing.xs),
                    TextField(
                      controller: tokenController,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: TypeScale.code(color: palette.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'paste your token',
                        border: OutlineInputBorder(),
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
                        label: 'Remove token',
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
      title: 'Integrations',
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        itemCount: kIntegrations.length,
        itemBuilder: (context, index) {
          final def = kIntegrations[index];
          final connected = _connected[def.id] ?? false;
          return Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: GCard(
              child: InkWell(
                borderRadius: BorderRadius.circular(RadiusTokens.lg),
                onTap: () => _openEditor(context, def),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: connected
                            ? palette.success.withValues(alpha: 0.12)
                            : palette.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(RadiusTokens.md),
                      ),
                      child: Icon(
                        connected ? Icons.link : Icons.add_link,
                        color: connected ? palette.success : palette.textTertiary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(def.name,
                              style:
                                  TypeScale.heading(color: palette.textPrimary)),
                          const SizedBox(height: Spacing.xs),
                          Text(
                            connected
                                ? 'Connected — one-time setup, stays until '
                                    'you remove it'
                                : def.tokenLabel,
                            style: TypeScale.caption(
                              color: connected
                                  ? palette.success
                                  : palette.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit_outlined,
                        size: 18, color: palette.textTertiary),
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
