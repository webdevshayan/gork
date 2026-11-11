import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/design_tokens.dart';
import '../services/locator.dart';
import '../services/vault_store.dart';
import '../widgets/g_button.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';

/// Encrypted vault: passwords, logins, card details. Everything lives in the
/// device keystore; copying to clipboard is one tap.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  List<VaultEntry> _entries = [];
  final Set<String> _revealed = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final entries = await Locator.vault.all();
    entries.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _createOrEdit([VaultEntry? existing]) async {
    final titleController = TextEditingController(text: existing?.title);
    final usernameController = TextEditingController(text: existing?.username);
    final secretController = TextEditingController(text: existing?.secret);
    final notesController = TextEditingController(text: existing?.notes);
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
              Text(existing == null ? 'New vault entry' : 'Edit entry',
                  style: TypeScale.title(color: palette.textPrimary)),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: titleController,
                style: TypeScale.body(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Name (e.g. GitHub login)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: usernameController,
                style: TypeScale.body(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Username or email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: secretController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                style: TypeScale.code(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Password / secret / card number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: notesController,
                style: TypeScale.bodySmall(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.lg),
              GButton(
                label: 'Save entry',
                expands: true,
                onPressed: () {
                  final title = titleController.text.trim();
                  final secret = secretController.text.trim();
                  if (title.isEmpty || secret.isEmpty) return;
                  final now = DateTime.now().millisecondsSinceEpoch;
                  Locator.vault.save(VaultEntry(
                    id: existing?.id ?? now.toString(),
                    title: title,
                    username: usernameController.text.trim(),
                    secret: secret,
                    notes: notesController.text.trim(),
                    createdAt: existing?.createdAt ?? now,
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

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Screen(
      title: 'Vault',
      fab: FloatingActionButton(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        child: const Icon(Icons.add),
        onPressed: () => _createOrEdit(),
      ),
      body: _entries.isEmpty
          ? GCard(
              child: Text(
                'Vault is empty. Entries are encrypted on this device only.',
                style: TypeScale.body(color: palette.textSecondary),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: Spacing.md),
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final e = _entries[index];
                final revealed = _revealed.contains(e.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.md),
                  child: GCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock_outline,
                                size: 20, color: palette.primary),
                            const SizedBox(width: Spacing.sm),
                            Expanded(
                              child: Text(e.title,
                                  style: TypeScale.heading(
                                      color: palette.textPrimary)),
                            ),
                          ],
                        ),
                        if (e.username.isNotEmpty) ...[
                          const SizedBox(height: Spacing.xs),
                          Text(e.username,
                              style: TypeScale.bodySmall(
                                  color: palette.textSecondary)),
                        ],
                        const SizedBox(height: Spacing.sm),
                        Text(
                          revealed ? e.secret : '••••••••••••',
                          style: TypeScale.code(color: palette.textPrimary),
                        ),
                        const SizedBox(height: Spacing.md),
                        Row(
                          children: [
                            GButton(
                              label: revealed ? 'Hide' : 'Reveal',
                              variant: ButtonVariant.secondary,
                              onPressed: () => setState(() {
                                revealed
                                    ? _revealed.remove(e.id)
                                    : _revealed.add(e.id);
                              }),
                            ),
                            const SizedBox(width: Spacing.sm),
                            GButton(
                              label: 'Copy',
                              variant: ButtonVariant.ghost,
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: e.secret));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Copied to clipboard',
                                          style: TypeScale.bodySmall(
                                              color: palette.onPrimary)),
                                    ),
                                  );
                                }
                              },
                            ),
                            const Spacer(),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 20, color: palette.error),
                              onPressed: () async {
                                await Locator.vault.delete(e.id);
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
    );
  }
}
