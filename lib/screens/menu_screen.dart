import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../constants/version.dart';
import '../services/handoff_service.dart';
import '../services/locator.dart';
import '../services/profile_info.dart';
import '../widgets/glass.dart';
import 'accounts_screen.dart';
import 'cloud_computer_screen.dart';
import 'google_accounts_screen.dart';
import 'inbox_screen.dart';
import 'integrations_screen.dart';
import 'panels_screen.dart';
import 'profile_edit_screen.dart';
import 'providers_screen.dart';
import 'search_screen.dart';
import 'security_screen.dart';
import 'settings_screen.dart';
import 'tasks_screen.dart';
import 'updates_screen.dart';

/// The profile/menu surface (opened from the avatar): big identity header,
/// a card of rows covering EVERY settings surface (Profile / Scheduled
/// Tasks / Accounts / Integrations / Google / Inbox / Panels / Cloud
/// Computer / Theme), a Security card, the AI Providers row, the
/// Sync-to-daemon action, Updates and the Search pill. Movement 55: Inbox,
/// Panels and Cloud Computer were reachable from nowhere — now they are
/// listed here like every other settings screen. No wallet (removed,
/// Movement 50), no upsell, no plan rows.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, this.onBack, this.onOpenChat});

  final VoidCallback? onBack;

  /// Hands a conversation id to the shell (opened from the Search surface).
  final ValueChanged<String>? onOpenChat;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
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
    return ValueListenableBuilder<String>(
      valueListenable: profileName,
      builder: (context, name, _) => ValueListenableBuilder<String>(
        valueListenable: profileEmail,
        builder: (context, email, _) {
          return ListView(
      // Movement 55: clip — scrolled rows must not paint behind the nav pill.
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          name,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            color: GlassColors.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          email,
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
                // Movement 52: every website account the user logged into
                // from the app, in one place.
                onTap: () => _push(context, const AccountsScreen()),
              ),
              Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-integrations'),
                icon: Icons.extension_outlined,
                label: 'Integrations',
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
                key: const ValueKey('menu-inbox'),
                icon: Icons.inbox_outlined,
                label: 'Inbox',
                // Movement 55: the agent Inbox was built but never linked
                // from the menu — every settings surface is listed here.
                onTap: () => _push(context, const InboxScreen()),
              ),
              Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-settings'),
                icon: Icons.tune,
                label: 'Settings',
                // Movement 62: the ONE settings page — the theme lives in
                // its Preferences tab now (moved off Home).
                onTap: () => _push(context, const SettingsScreen()),
              ),
              Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-panels'),
                icon: Icons.grid_view_outlined,
                label: 'Panels',
                onTap: () => _push(context, const PanelsScreen()),
              ),
              Divider(color: GlassColors.divider, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-cloud'),
                icon: Icons.cloud_outlined,
                label: 'Cloud Computer',
                onTap: () => _push(context, const CloudComputerScreen()),
              ),
              // Movement 59: the Theme page is gone — the app is always
              // auto (light by day, dark by night), gray and black only.
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
            onTap: () => _push(context, const SecurityScreen()),
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
        },
      ),
    );
  }
}
