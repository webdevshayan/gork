import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/design_tokens.dart';
import '../services/locator.dart';
import '../services/vault_store.dart';
import '../widgets/g_button.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';

/// The Wallet: exchanges, on-chain accounts, card details and logins the
/// user keeps for their own AI. Everything is encrypted on this device only;
/// each wallet carries an explicit AI-access toggle — nothing is shared with
/// the AI until the user flips it on.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
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
    final addressController = TextEditingController(text: existing?.username);
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
              Text(existing == null ? 'New wallet' : 'Edit wallet',
                  style: TypeScale.title(color: palette.textPrimary)),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: titleController,
                style: TypeScale.body(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Name (e.g. Metamask, Binance)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                controller: addressController,
                style: TypeScale.body(color: palette.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Address / account / login',
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
                  hintText: 'Seed phrase / private key / card number',
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
                label: 'Save wallet',
                expands: true,
                onPressed: () {
                  final title = titleController.text.trim();
                  final secret = secretController.text.trim();
                  if (title.isEmpty || secret.isEmpty) return;
                  final now = DateTime.now().millisecondsSinceEpoch;
                  Locator.vault.save(VaultEntry(
                    id: existing?.id ?? now.toString(),
                    title: title,
                    username: addressController.text.trim(),
                    secret: secret,
                    notes: notesController.text.trim(),
                    createdAt: existing?.createdAt ?? now,
                    aiAccess: existing?.aiAccess ?? false,
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

  Future<void> _toggleAiAccess(VaultEntry e) async {
    await Locator.vault.save(
      VaultEntry(
        id: e.id,
        title: e.title,
        username: e.username,
        secret: e.secret,
        notes: e.notes,
        createdAt: e.createdAt,
        aiAccess: !e.aiAccess,
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Screen(
      title: 'Wallet',
      fab: FloatingActionButton(
        key: const ValueKey('wallet-add'),
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        child: const Icon(Icons.add),
        onPressed: () => _createOrEdit(),
      ),
      body: _entries.isEmpty
          ? GCard(
              child: Text(
                'No wallets yet. Wallets are encrypted on this device only — '
                'flip AI access on a wallet to let your AI use it.',
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
                            Icon(Icons.account_balance_wallet_outlined,
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
                        const SizedBox(height: Spacing.sm),
                        // The AI-access switch: the user's explicit,
                        // per-wallet grant. Off by default, always honest.
                        Row(
                          children: [
                            GestureDetector(
                              key: ValueKey('ai-access-${e.id}'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _toggleAiAccess(e),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: e.aiAccess
                                      ? palette.success.withValues(alpha: 0.15)
                                      : palette.surfaceElevated,
                                  borderRadius:
                                      BorderRadius.circular(RadiusTokens.md),
                                  border: Border.all(
                                    color: e.aiAccess
                                        ? palette.success
                                        : palette.border,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      e.aiAccess
                                          ? Icons.check_circle_outline
                                          : Icons.do_not_disturb_on_outlined,
                                      size: 16,
                                      color: e.aiAccess
                                          ? palette.success
                                          : palette.textTertiary,
                                    ),
                                    const SizedBox(width: Spacing.sm),
                                    Text(
                                      e.aiAccess
                                          ? 'AI access on'
                                          : 'AI access off',
                                      style: TypeScale.bodySmall(
                                        color: e.aiAccess
                                            ? palette.success
                                            : palette.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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
