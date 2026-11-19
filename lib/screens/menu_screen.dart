import 'package:flutter/material.dart';

import '../constants/ambient.dart';
import '../constants/design_tokens.dart';
import '../constants/version.dart';
import '../services/handoff_service.dart';
import '../services/locator.dart';
import '../services/profile_info.dart';
import '../widgets/g_button.dart';
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
import 'tasks_screen.dart';
import 'updates_screen.dart';

/// The profile/menu surface (opened from the avatar): big identity header,
/// a card of rows covering EVERY settings surface (Profile / Scheduled
/// Tasks / Accounts / Integrations / Google / Inbox / Panels / Cloud
/// Computer), then the PREFERENCES section embedded right here — Movement
/// 63: no separate Settings screen anymore. Where the old Settings row sat
/// the menu now carries the Preferences | About tabs directly (theme,
/// background responses, version, updates), followed by Security, AI
/// Providers, Sync-to-daemon, Updates and the Search pill. Movement 55:
/// Inbox, Panels and Cloud Computer were reachable from nowhere — now they
/// are listed here like every other settings screen. No wallet (removed,
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
  /// Which embedded tab is open: Preferences (default) or About — the
  /// tabs live in the menu itself now, not on a pushed Settings screen.
  bool _preferences = true;

  static const String kThemeKey = 'ui.theme';

  String get _themeChoice =>
      Locator.maybePrefs?.getString(kThemeKey) ?? 'auto';

  Future<void> _setTheme(String mode) async {
    final prefs = Locator.maybePrefs;
    if (prefs == null) return;
    await prefs.setString(kThemeKey, mode);
    // The app shell listens to the ambient version — nudge it so the new
    // choice rebuilds MaterialApp, the glass colors and the backdrop.
    ambient.refresh();
    if (mounted) setState(() {});
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
              // Movement 63: the Settings screen is gone too — the theme
              // lives in the embedded Preferences section right below.
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- Preferences | About, embedded (Movement 63) ----
        // Where the Settings row used to sit: the tabs and their content
        // are part of THIS screen — no push, no second "Settings" title.
        _SettingsTabs(
          preferences: _preferences,
          onPick: (v) => setState(() => _preferences = v),
        ),
        const SizedBox(height: 16),
        if (_preferences) ...[
          _ThemeCard(choice: _themeChoice, onPick: _setTheme),
          const SizedBox(height: 16),
          GlassContainer(
            radius: 28,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Background responses',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: GlassColors.text)),
                const SizedBox(height: 8),
                Text(
                  'Messages you send run on YOUR VPS — the phone can die, '
                  'the app can close, the answer still completes there '
                  'and arrives as a notification when you are back.',
                  style: TextStyle(
                      fontSize: 14, height: 1.4, color: GlassColors.textDim),
                ),
              ],
            ),
          ),
        ] else ...[
          GlassContainer(
            radius: 28,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('gork v$kAppVersion',
                    key: const ValueKey('settings-version'),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: GlassColors.text)),
                const SizedBox(height: 8),
                Text(
                  'Install over any earlier version — settings, keys, '
                  'tasks and the vault are kept.',
                  style: TextStyle(
                      fontSize: 14, height: 1.4, color: GlassColors.textDim),
                ),
                const SizedBox(height: 12),
                GButton(
                  key: const ValueKey('settings-updates'),
                  label: 'Check for updates',
                  variant: ButtonVariant.secondary,
                  expands: true,
                  onPressed: () => _push(context, const UpdatesScreen()),
                ),
              ],
            ),
          ),
        ],
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

/// The two-tab header: Preferences | About — embedded in the menu itself
/// (Movement 63). Solid chips, gray & black — Movement 59/60 language, no
/// color. Same keys as the old Settings screen so tests and muscle memory
/// carry over.
class _SettingsTabs extends StatelessWidget {
  const _SettingsTabs({required this.preferences, required this.onPick});

  final bool preferences;
  final void Function(bool) onPick;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool active, VoidCallback onTap,
        {String? testKey}) {
      return Expanded(
        child: GestureDetector(
          key: testKey == null ? null : ValueKey(testKey),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: active ? GlassColors.chip : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? GlassColors.textOnChip
                          : GlassColors.textDim)),
            ),
          ),
        ),
      );
    }

    return GlassContainer(
      radius: 28,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          tab('Preferences', preferences, () => onPick(true),
              testKey: 'settings-tab-preferences'),
          const SizedBox(width: 8),
          tab('About', !preferences, () => onPick(false),
              testKey: 'settings-tab-about'),
        ],
      ),
    );
  }
}

/// The theme picker, embedded in the menu (Movement 63). Same keys, same
/// behavior: Auto (the sun decides), Light or Dark — persisted in
/// 'ui.theme' (the SAME pref every earlier version wrote).
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.choice, required this.onPick});

  final String choice;
  final void Function(String mode) onPick;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: 28,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette_outlined,
                  size: 22, color: GlassColors.text),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Theme',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: GlassColors.text)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Auto follows the sun (light by day, dark by night). Your choice '
            'wins over the sun until you switch back.',
            style: TextStyle(
                fontSize: 14, height: 1.4, color: GlassColors.textDim),
          ),
          const SizedBox(height: 12),
          GlassContainer(
            radius: 20,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                for (final (i, option) in const [
                  ('auto', 'Auto'),
                  ('light', 'Light'),
                  ('dark', 'Dark'),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      key: ValueKey('theme-${option.$1}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onPick(option.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: choice == option.$1
                              ? GlassColors.chip
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              switch (option.$1) {
                                'light' => Icons.light_mode_outlined,
                                'dark' => Icons.dark_mode_outlined,
                                _ => Icons.auto_awesome_outlined,
                              },
                              size: 16,
                              color: choice == option.$1
                                  ? GlassColors.textOnChip
                                  : GlassColors.textDim,
                              semanticLabel: 'Theme ${option.$2}',
                            ),
                            const SizedBox(width: 8),
                            Text(
                              option.$2,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: choice == option.$1
                                      ? GlassColors.textOnChip
                                      : GlassColors.textDim),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
