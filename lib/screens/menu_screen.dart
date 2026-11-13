import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../constants/version.dart';
import '../services/handoff_service.dart';
import '../services/locator.dart';
import '../widgets/glass.dart';
import 'cloud_computer_screen.dart';
import 'integrations_screen.dart';
import 'providers_screen.dart';
import 'search_screen.dart';
import 'tasks_screen.dart';
import 'theme_page.dart';
import 'updates_screen.dart';
import 'wallet_screen.dart';

/// The profile/menu surface (opened from the avatar): big identity header,
/// the gork wordmark card, a card of rows (Profile / Scheduled Tasks /
/// Accounts / Wallet), a Security card, the AI Providers row, the
/// Sync-to-daemon action and the Search pill. No upsell, no plan rows.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key, this.onBack, this.onOpenChat});

  final VoidCallback? onBack;

  /// Hands a conversation id to the shell (opened from the Search surface).
  final ValueChanged<String>? onOpenChat;

  static const String _kName = 'Shayan Ali Jalb';
  static const String _kEmail = 'shayanalibuilds@gmail.com';

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _syncToDaemon(BuildContext context) async {
    final HandoffService handoff = Locator.handoff;
    if (!handoff.configured) {
      _push(context, const CloudComputerScreen());
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Syncing config to the daemon…')));
    try {
      final summary = await handoff.pushConfig();
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(summary)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sync failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        const Text(
          _kName,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            color: GlassColors.text,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          _kEmail,
          style: TextStyle(fontSize: 16, color: GlassColors.textDim),
        ),
        const SizedBox(height: 24),
        GlassContainer(
          radius: 28,
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Text(
                'gork',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: GlassColors.text,
                ),
              ),
              const Spacer(),
              const Icon(Icons.auto_awesome, size: 20,
                  color: GlassColors.textDim),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer(
          radius: 28,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              GlassMenuRow(
                key: const ValueKey('menu-profile'),
                icon: Icons.person_outline,
                label: 'Profile',
                onTap: () => _push(context, const ThemePage()),
              ),
              const Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-tasks'),
                icon: Icons.schedule_outlined,
                label: 'Scheduled Tasks',
                onTap: () => _push(context, const TasksScreen()),
              ),
              const Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-accounts'),
                icon: Icons.link,
                label: 'Accounts',
                onTap: () => _push(context, const IntegrationsScreen()),
              ),
              const Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-wallet'),
                icon: Icons.account_balance_wallet_outlined,
                label: 'Wallet',
                onTap: () => _push(context, const WalletScreen()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer(
          radius: 28,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GlassMenuRow(
            key: const ValueKey('menu-security'),
            icon: Icons.shield_outlined,
            label: 'Security',
            onTap: () => _push(context, const WalletScreen()),
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer(
          radius: 28,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GlassMenuRow(
            key: const ValueKey('menu-providers'),
            icon: Icons.key_outlined,
            label: 'AI Providers',
            onTap: () => _push(context, const ProvidersScreen()),
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer(
          radius: 28,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GlassMenuRow(
            key: const ValueKey('menu-sync'),
            icon: Icons.sync_outlined,
            label: 'Sync to daemon',
            onTap: () => _syncToDaemon(context),
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer(
          radius: 28,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GlassMenuRow(
            key: const ValueKey('menu-updates'),
            icon: Icons.system_update_outlined,
            label: 'Updates',
            trailing: kAppVersion == 'dev'
                ? null
                : Text(
                    'v$kAppVersion',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GlassColors.textFaint,
                    ),
                  ),
            onTap: () => _push(context, const UpdatesScreen()),
          ),
        ),
        const SizedBox(height: 24),
        GlassContainer(
          radius: 30,
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: GestureDetector(
            key: const ValueKey('menu-search'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _push(
              context,
              SearchScreen(onOpenChat: onOpenChat ?? (_) {}),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.search, size: 20, color: GlassColors.textDim),
                  SizedBox(width: 12),
                  Text(
                    'Search',
                    style: TextStyle(fontSize: 17, color: GlassColors.textDim),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
