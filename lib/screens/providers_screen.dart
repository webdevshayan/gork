import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../providers/providers.dart';
import '../services/locator.dart';
import '../widgets/g_button.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';

/// Settings screen where the user brings their own API keys.
/// Keys are stored ONLY on this device, namespaced per provider.
class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({super.key});

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  final Map<String, bool> _saved = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final vaultStatus = <String, bool>{};
    for (final p in kProviders) {
      vaultStatus[p.id] = await Locator.chat.hasKey(p.id);
    }
    if (mounted) setState(() => _saved.addAll(vaultStatus));
  }

  Future<void> _openEditor(BuildContext context, ProviderEntry provider) async {
    final palette = paletteOf(context);
    final keyController = TextEditingController();
    final modelController = TextEditingController(text: provider.defaultModel);
    final baseURLController = TextEditingController();
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
                    Text(provider.name,
                        style: TypeScale.title(color: palette.textPrimary)),
                    const SizedBox(height: Spacing.xs),
                    if (!provider.isCustom)
                      Text(provider.baseURL,
                          style: TypeScale.caption(color: palette.textTertiary)),
                    const SizedBox(height: Spacing.md),
                    if (provider.isCustom) ...[
                      Text('Base URL',
                          style: TypeScale.caption(color: palette.textSecondary)),
                      const SizedBox(height: Spacing.xs),
                      TextField(
                        controller: baseURLController,
                        style: TypeScale.code(color: palette.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'http://192.168.1.10:1234/v1',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: Spacing.md),
                    ],
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
                    Text('Model',
                        style: TypeScale.caption(color: palette.textSecondary)),
                    const SizedBox(height: Spacing.xs),
                    TextField(
                      controller: modelController,
                      style: TypeScale.code(color: palette.textPrimary),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    if (testResult != null) ...[
                      Text(testResult!,
                          style: TypeScale.bodySmall(color: testColor)),
                      const SizedBox(height: Spacing.md),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: GButton(
                            label: 'Save key',
                            onPressed: () async {
                              final key = keyController.text.trim();
                              if (key.isEmpty) return;
                              await Locator.chat.saveKey(provider.id, key);
                              await _refresh();
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                            },
                            expands: true,
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: GButton(
                            label: 'Test connection',
                            variant: ButtonVariant.secondary,
                            onPressed: () async {
                              setSheetState(() {
                                testResult = 'Testing...';
                                testColor = palette.textSecondary;
                              });
                              final result = await Locator.chat.testConnection(
                                providerId: provider.id,
                                model: modelController.text.trim(),
                                baseURL: baseURLController.text.trim(),
                                defaultModel: modelController.text.trim(),
                              );
                              setSheetState(() {
                                testResult = (result == null)
                                    ? 'Connection OK — key works.'
                                    : 'Failed: $result';
                                testColor =
                                    result == null ? palette.success : palette.error;
                              });
                            },
                            expands: true,
                          ),
                        ),
                      ],
                    ),
                    if (_saved[provider.id] == true) ...[
                      const SizedBox(height: Spacing.sm),
                      GButton(
                        label: 'Remove key',
                        variant: ButtonVariant.ghost,
                        onPressed: () async {
                          await Locator.chat.clearKey(provider.id);
                          await _refresh();
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
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
      title: 'Providers',
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        itemCount: kProviders.length,
        itemBuilder: (context, index) {
          final p = kProviders[index];
          final saved = _saved[p.id] ?? false;
          return Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: GCard(
              child: InkWell(
                borderRadius: BorderRadius.circular(RadiusTokens.lg),
                onTap: () => _openEditor(context, p),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: saved
                            ? palette.success.withValues(alpha: 0.12)
                            : palette.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(RadiusTokens.md),
                      ),
                      child: Icon(
                        saved ? Icons.key : Icons.key_off_outlined,
                        color: saved ? palette.success : palette.textTertiary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              style: TypeScale.heading(color: palette.textPrimary)),
                          const SizedBox(height: Spacing.xs),
                          Text(
                            saved ? 'Key saved on this device' : 'No key yet',
                            style: TypeScale.caption(
                              color: saved ? palette.success : palette.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.edit_outlined, size: 18, color: palette.textTertiary),
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
