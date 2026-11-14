import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../constants/version.dart';
import '../services/handoff_service.dart';
import '../services/locator.dart';
import '../services/profile_info.dart';
import '../widgets/glass.dart';
import 'cloud_computer_screen.dart';
import 'google_accounts_screen.dart';
import 'integrations_screen.dart';
import 'profile_edit_screen.dart';
import 'providers_screen.dart';
import 'search_screen.dart';
import 'tasks_screen.dart';
import 'theme_page.dart';
import 'updates_screen.dart';
import 'wallet_screen.dart';

/// The profile/menu surface (opened from the avatar): big identity header,
/// the gork wordmark card, a card of rows (Profile / Scheduled Tasks /
/// Accounts / Google / Wallet), a Security card, the AI Providers row, the
/// Sync-to-daemon action and the Search pill. No upsell, no plan rows.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, this.onBack, this.onOpenChat});

  final VoidCallback? onBack;

  /// Hands a conversation id to the shell (opened from the Search surface).
  final ValueChanged<String>? onOpenChat;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  /// The identity, read synchronously at build time — no async gap, no
  /// notifier race. Safe when the locator is unbound (widget tests).
  String get _name {
    try {
      return Locator.prefs.getString('profile.name') ?? kDefaultName;
    } catch (_) {
      return kDefaultName;
    }
  }

  String get _email {
    try {
      return Locator.prefs.getString('profile.email') ?? kDefaultEmail;
    } catch (_) {
      return kDefaultEmail;
    }
  }

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
        Text(
          _name,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            color: GlassColors.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _email,
          style: TextStyle(fontSize: 16, color: GlassColors.textDim),
        ),
        const SizedBox(height: 24),
        GlassContainer(
          radius: 28,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              GlassMenuRow(
                key: const ValueKey('menu-profile'),
                icon: Icons.person_outline,
                label: 'Profile',
                onTap: () => _push(context, const ProfileEditScreen()),
              ),
              Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-tasks'),
                icon: Icons.schedule_outlined,
                label: 'Scheduled Tasks',
                onTap: () => _push(context, const TasksScreen()),
              ),
              Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-accounts'),
                icon: Icons.link,
                label: 'Accounts',
                onTap: () => _push(context, const IntegrationsScreen()),
              ),
              Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-google'),
                icon: Icons.account_circle_outlined,
                label: 'Google',
                onTap: () => _push(context, const GoogleAccountsScreen()),
              ),
              Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-wallet'),
                icon: Icons.account_balance_wallet_outlined,
                label: 'Wallet',
                onTap: () => _push(context, const WalletScreen()),
              ),
              Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-theme'),
                icon: Icons.dark_mode_outlined,
                label: 'Theme',
                onTap: () => _push(context, const ThemePage()),
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
                    style: TextStyle(
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
              SearchScreen(onOpenChat: widget.onOpenChat ?? (_) {}),
            ),
            child: Padding(
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
