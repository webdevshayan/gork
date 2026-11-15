import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/browser_service.dart';
import '../services/locator.dart';
import '../services/vault_store.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/glass.dart';

/// Accounts — every account the user has logged into for all websites,
/// from our app. VPS accounts (recorded logins) + on-device vault entries,
/// listed by site and username. Secrets never appear here — that is the
/// whole point of the secure fill protocol (Movement 52).
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Map<String, dynamic>>? _accounts;
  List<VaultEntry>? _vault;
  bool _vpsConfigured = false;

  @override
  void initState() {
    super.initState();
    final browser = BrowserService();
    _vpsConfigured = browser.configured;
    browser.accounts().then((accounts) {
      if (mounted) setState(() => _accounts = accounts);
    });
    Locator.vault.all().then((entries) {
      if (mounted) setState(() => _vault = entries);
    });
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    final vault = _vault;
    final hasAny = (accounts != null && accounts.isNotEmpty) ||
        (vault != null && vault.isNotEmpty);
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
                        'Accounts',
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
                  child: Text(
                    'Every website account you logged into from this app. '
                    'When the AI fills a login it asks for the field by '
                    'label and the value is filled for it — the AI never '
                    'sees a password or auth code.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: GlassColors.textDim,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (accounts == null || vault == null)
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
                else if (!hasAny) ...[
                  if (!_vpsConfigured)
                    GlassContainer(
                      radius: 28,
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Connect your Cloud Computer to see the accounts the '
                        'AI uses in its browser. On-device entries appear '
                        'either way.',
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
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No accounts yet. Log into a website through the AI '
                        'and the account is listed here — by site and '
                        'username only.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: GlassColors.textDim,
                        ),
                      ),
                    ),
                ],
                if (accounts != null && accounts.isNotEmpty) ...[
                  GlassContainer(
                    radius: 28,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final (i, account) in accounts.indexed) ...[
                          if (i > 0)
                            Divider(color: GlassColors.divider, height: 1),
                          GlassMenuRow(
                            key: ValueKey('acct-${account['site']}-'
                                '${account['username']}'),
                            icon: Icons.public_outlined,
                            label: account['site'] as String? ?? '',
                            trailing: Text(
                              account['username'] as String? ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                color: GlassColors.textFaint,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (vault != null && vault.isNotEmpty)
                  GlassContainer(
                    radius: 28,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final (i, entry) in vault.indexed) ...[
                          if (i > 0)
                            Divider(color: GlassColors.divider, height: 1),
                          GlassMenuRow(
                            key: ValueKey('vault-${entry.id}'),
                            icon: Icons.key_outlined,
                            label: entry.title,
                            trailing: Text(
                              entry.username.isEmpty ? 'saved' : entry.username,
                              style: TextStyle(
                                fontSize: 13,
                                color: GlassColors.textFaint,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
