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
import 'integrations_screen.dart';
import 'panels_screen.dart';
import 'profile_edit_screen.dart';
import 'providers_screen.dart';
import 'search_screen.dart';
import 'security_screen.dart';
import 'skills_screen.dart';
import 'tasks_screen.dart';
import 'theme_preferences_screen.dart';
import 'updates_screen.dart';

/// Movement 69 — the menu is ONE flat list with a STICKY search on top:
/// Profile, Scheduled Tasks, Connections, Skills, Panels, Cloud Computer,
/// Theme — then Security, Sync to daemon, Updates and the Search surface.
/// The duplicates are gone: Accounts, Integrations and Google folded into
/// Connections (ChatGPT-style, one-tap connect); Inbox removed from
/// settings (it is a notification surface, not a setting). The search digs
/// DEEP — it matches every screen and the things inside them (dark mode,
/// Gmail, OpenAI keys, study widgets…) and jumps straight there.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, this.onBack, this.onOpenChat});

  final VoidCallback? onBack;

  /// Hands a conversation id to the shell (opened from the Search surface).
  final ValueChanged<String>? onOpenChat;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

/// One deep-search destination: a screen (or an action inside one) with
/// every word a person might type to find it.
class _Destination {
  const _Destination(this.title, this.detail, this.icon, this.keywords,
      this.builder);
  final String title;
  final String detail;
  final IconData icon;
  final String keywords;
  final WidgetBuilder builder;
}

class _MenuScreenState extends State<MenuScreen> {
  String? _query;
  final TextEditingController _searchCtrl = TextEditingController();

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

  /// Movement 69 — the deep index: EVERY settings surface AND the things
  /// inside them. Matching is instant (a static list, no I/O) and covers
  /// any role: a student finds "dark mode", a farmer finds "weather", a
  /// developer finds "OpenAI key" — all jump straight to the screen.
  List<_Destination> get _destinations => [
        _Destination('Profile', 'Your name, photo and email', Icons.person_outline,
            'profile name email photo avatar identity who am i',
            (_) => const ProfileEditScreen()),
        _Destination('Scheduled Tasks', 'Things gork does on a schedule',
            Icons.schedule_outlined, 'tasks schedule reminders cron routine '
            'alarm daily weekly automation',
            (_) => const TasksScreen()),
        _Destination('Connections', 'Google, GitHub, Slack, Strava, Spotify, '
            'PayPal — one-tap connect', Icons.link_rounded,
            'connections accounts integrations google gmail docs youtube '
            'github slack strava spotify paypal sign in login oauth tokens '
            'website accounts browser logins',
            (_) => const ConnectionsScreen()),
        _Destination('Skills', 'How-to notes gork follows and learns',
            Icons.auto_stories_outlined,
            'skills learn teach how to instructions markdown steps memory',
            (_) => const SkillsScreen()),
        _Destination('Panels', 'AI-built widgets on your home feed',
            Icons.grid_view_outlined,
            'panels widgets dashboard graphs stats streaks customize feed '
            'weather topics study prs role student developer farmer',
            (_) => const PanelsScreen()),
        _Destination('Cloud Computer', 'Your VPS — the 24/7 machine',
            Icons.cloud_outlined,
            'cloud vps server daemon setup install host terminal ssh',
            (_) => const CloudComputerScreen()),
        _Destination('Theme', 'Auto (light by day, dark by night), light, dark',
            Icons.palette_outlined,
            'theme dark light appearance mode auto night day colors radio '
            'switch toggle',
            (_) => const ThemePreferencesScreen()),
        _Destination('Security', 'Keys, secrets and the vault',
            Icons.shield_outlined,
            'security vault secrets keys passcode lock safe encryption '
            'privacy',
            (_) => const SecurityScreen()),
        _Destination('AI Providers', 'OpenAI, Gemini, Anthropic, OpenRouter '
            'or your own endpoint', Icons.key_outlined,
            'providers api key openai gemini anthropic openrouter claude '
            'gpt custom endpoint base url model',
            (_) => const ProvidersScreen()),
        _Destination('Google setup', 'Connect Gmail, Google Docs and YouTube',
            Icons.account_circle_outlined,
            'google connect gmail docs youtube oauth android client '
            'credentials one tap',
            (_) => const GoogleAccountsScreen()),
        _Destination('Website accounts', 'What gork signed into for you',
            Icons.public, 'accounts website browser logins sessions '
            'logged in sites',
            (_) => const AccountsScreen()),
        _Destination('Sync to daemon', 'Push your config to the VPS',
            Icons.sync_outlined, 'sync daemon config push backup vps',
            (_) => const CloudComputerScreen()),
        _Destination('Updates', 'Version and update checks',
            Icons.system_update_outlined, 'updates version upgrade check '
            'new release install',
            (_) => const UpdatesScreen()),
        _Destination('Search everything', 'Chats, projects and screens',
            Icons.search, 'search find chat history messages projects',
            (context) => SearchScreen(onOpenChat: widget.onOpenChat ?? (_) {})),
      ];

  List<_Destination> _searchHits(String q) {
    final query = q.toLowerCase().trim();
    if (query.isEmpty) return [];
    return [
      for (final d in _destinations)
        if (d.title.toLowerCase().contains(query) ||
            d.detail.toLowerCase().contains(query) ||
            d.keywords.contains(query))
          d,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: profileName,
      builder: (context, name, _) => ValueListenableBuilder<String>(
        valueListenable: profileEmail,
        builder: (context, email, _) {
          return CustomScrollView(
            // Movement 55: clip — scrolled rows must not paint behind the nav
            // pill. Movement 69: the search bar is a PINNED sliver — it stays
            // at the top while the list slides under it.
            clipBehavior: Clip.hardEdge,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Text(name,
                      style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w600,
                          color: GlassColors.text)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Text(email,
                      style: TextStyle(
                          fontSize: 16, color: GlassColors.textDim)),
                ),
              ),
              // The sticky search header.
              SliverPersistentHeader(
                pinned: true,
                delegate: _SearchHeaderDelegate(
                  controller: _searchCtrl,
                  onChanged: (v) =>
                      setState(() => _query = v.isEmpty ? null : v),
                ),
              ),
              if (_query != null && _query!.isNotEmpty)
                _searchResultsSliver(_query!)
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: GlassContainer(
                      radius: 28,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          GlassMenuRow(
                            key: const ValueKey('menu-profile'),
                            icon: Icons.person_outline,
                            label: 'Profile',
                            onTap: () =>
                                _push(context, const ProfileEditScreen()),
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
                            key: const ValueKey('menu-connections'),
                            icon: Icons.link_rounded,
                            label: 'Connections',
                            // Movement 69 — Accounts + Integrations + Google
                            // are ONE surface now: one-tap connect, ChatGPT
                            // style. No duplicate Google/Accounts rows.
                            onTap: () =>
                                _push(context, const ConnectionsScreen()),
                          ),
                          Divider(color: GlassColors.divider, height: 1),
                          GlassMenuRow(
                            key: const ValueKey('menu-skills'),
                            icon: Icons.auto_stories_outlined,
                            label: 'Skills',
                            onTap: () => _push(context, const SkillsScreen()),
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
                            onTap: () =>
                                _push(context, const CloudComputerScreen()),
                          ),
                          Divider(color: GlassColors.divider, height: 1),
                          GlassMenuRow(
                            key: const ValueKey('menu-theme'),
                            icon: Icons.palette_outlined,
                            label: 'Theme',
                            onTap: () =>
                                _push(context, const ThemePreferencesScreen()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: GlassContainer(
                      radius: 28,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: GlassMenuRow(
                        key: const ValueKey('menu-security'),
                        icon: Icons.shield_outlined,
                        label: 'Security',
                        onTap: () => _push(context, const SecurityScreen()),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: GlassContainer(
                      radius: 28,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: GlassMenuRow(
                        key: const ValueKey('menu-sync'),
                        icon: Icons.sync_outlined,
                        label: 'Sync to daemon',
                        onTap: () => _syncToDaemon(context),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  sliver: SliverToBoxAdapter(
                    child: GlassContainer(
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
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _searchResultsSliver(String query) {
    final hits = _searchHits(query);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      sliver: SliverToBoxAdapter(
        child: GlassContainer(
          radius: 28,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              if (hits.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Nothing in settings matches "$query". Try "dark", '
                    '"gmail", "api key", "widgets"…',
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.45,
                        color: GlassColors.textDim),
                  ),
                )
              else
                for (final (i, d) in hits.indexed) ...[
                  if (i > 0) Divider(color: GlassColors.divider, height: 1),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _query = null);
                      _push(context, d.builder(context));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Row(
                        children: [
                          Icon(d.icon, size: 24, color: GlassColors.text),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.title,
                                    style: TextStyle(
                                        fontSize: 18,
                                        color: GlassColors.text)),
                                const SizedBox(height: 2),
                                Text(d.detail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: GlassColors.textFaint)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.chevron_right,
                              size: 24, color: GlassColors.textDim),
                        ],
                      ),
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The pinned search header: a solid pill that stays at the top of the
/// menu while the list scrolls under it.
class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SearchHeaderDelegate({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  static const double _kExtent = 72;

  @override
  double get minExtent => _kExtent;

  @override
  double get maxExtent => _kExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      color: GlassColors.fill,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      // The menu renders on the shell's surface (no Scaffold Material in
      // every host): wrap the field in its own transparent Material.
      child: Material(
        type: MaterialType.transparency,
        child: TextField(
          key: const ValueKey('menu-settings-search'),
          controller: controller,
          onChanged: onChanged,
          style: TextStyle(fontSize: 16, color: GlassColors.text),
          decoration: InputDecoration(
            hintText: 'Search settings — "dark", "gmail", "api key"…',
            prefixIcon:
                Icon(Icons.search, size: 22, color: GlassColors.textDim),
            isDense: true,
            filled: true,
            fillColor: GlassColors.fillStrong,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide(color: GlassColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide(color: GlassColors.border),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_SearchHeaderDelegate old) => old.controller != controller;
}
