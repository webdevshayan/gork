import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/locator.dart';
import '../services/vault_store.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/glass.dart';

/// Security — the credentials vault surface. Secrets (passwords, auth codes)
/// live in the vault and are only ever filled into forms at the user's
/// command; this screen shows WHAT is stored but never the secret itself.
/// The wallet feature was removed (Movement 50); Security owns its own page.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  List<VaultEntry>? _entries;

  @override
  void initState() {
    super.initState();
    Locator.vault.all().then((entries) {
      if (mounted) setState(() => _entries = entries);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
