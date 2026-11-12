import 'package:flutter/material.dart';

import '../widgets/glass.dart';
import 'cloud_computer_screen.dart';
import 'inbox_screen.dart';
import 'integrations_screen.dart';
import 'panels_screen.dart';
import 'projects_screen.dart';
import 'providers_screen.dart';
import 'tasks_screen.dart';
import 'theme_page.dart';
import 'vault_screen.dart';

/// The profile/menu surface (opened with ☰), pixel-matched to the reference:
/// big identity header, the "gork pro" plan card, a card of rows
/// (Profile / Scheduled Tasks / Accounts / Wallet), a Security card, and the
/// Search pill that opens a feature palette. No tab is selected here.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key, this.onBack});

  final VoidCallback? onBack;

  static const String _kName = 'Shayan Ali Jalb';
  static const String _kEmail = 'shayanalibuilds@gmail.com';

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
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
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          _kEmail,
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
        const SizedBox(height: 24),
        _ProCard(onUpgrade: () => _push(context, const ProvidersScreen())),
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
              const Divider(color: Colors.black12, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-tasks'),
                icon: Icons.schedule_outlined,
                label: 'Scheduled Tasks',
                onTap: () => _push(context, const TasksScreen()),
              ),
              const Divider(color: Colors.black12, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-accounts'),
                icon: Icons.link,
                label: 'Accounts',
                onTap: () => _push(context, const IntegrationsScreen()),
              ),
              const Divider(color: Colors.black12, height: 1),
              GlassMenuRow(
                key: const ValueKey('menu-wallet'),
                icon: Icons.account_balance_wallet_outlined,
                label: 'Wallet',
                onTap: () => _push(context, const VaultScreen()),
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
            onTap: () => _push(context, const VaultScreen()),
          ),
        ),
        const SizedBox(height: 24),
        GlassContainer(
          radius: 30,
          opacity: 0.35,
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: GestureDetector(
            key: const ValueKey('menu-search'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _openFeaturePalette(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.search, size: 20, color: Colors.black54),
                  SizedBox(width: 12),
                  Text(
                    'Search',
                    style: TextStyle(fontSize: 17, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'gork v1.2.0 · free & open source',
          style: TextStyle(fontSize: 12, color: Colors.black38),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _openFeaturePalette(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => const _FeaturePalette(),
    );
  }
}

/// The plan card: wordmark + Upgrade (goes to BYOK providers), honest free
/// messaging in the reference's orange accent, and usage rows.
class _ProCard extends StatelessWidget {
  const _ProCard({required this.onUpgrade});

  final VoidCallback onUpgrade;

  static const Color kOrange = Color(0xFFEA580C);

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      key: const ValueKey('pro-card'),
      radius: 28,
      opacity: 0.45,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'gork',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'pro',
                style: TextStyle(
                  fontSize: 28,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w400,
                  color: Colors.black54,
                ),
              ),
              const Spacer(),
              GestureDetector(
                key: const ValueKey('upgrade-button'),
                behavior: HitTestBehavior.opaque,
                onTap: onUpgrade,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    'Upgrade',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            "Free and open source. Bring your own key — no monthly limits.",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: kOrange,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: kOrange,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Text(
                'Resets',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              Spacer(),
              Text(
                'Never — your keys, your limits',
                style: TextStyle(fontSize: 15, color: Colors.black54),
              ),
            ],
          ),
          const Divider(color: Colors.black12, height: 24),
          GlassMenuRow(
            key: const ValueKey('menu-usage'),
            icon: Icons.data_usage_outlined,
            label: 'Usage and plan',
            onTap: onUpgrade,
          ),
        ],
      ),
    );
  }
}

/// The Search pill opens this palette: every feature screen in the app,
/// filtered live as you type.
class _FeaturePalette extends StatefulWidget {
  const _FeaturePalette();

  @override
  State<_FeaturePalette> createState() => _FeaturePaletteState();
}

class _FeaturePaletteState extends State<_FeaturePalette> {
  String _query = '';

  static const List<_PaletteEntry> _entries = [
    _PaletteEntry('Inbox', Icons.inbox_outlined, 'inbox'),
    _PaletteEntry('Panels', Icons.dashboard_outlined, 'panels'),
    _PaletteEntry('Projects', Icons.folder_outlined, 'projects'),
    _PaletteEntry('Vault', Icons.lock_outline, 'vault'),
    _PaletteEntry('Cloud Computer', Icons.dns_outlined, 'cloud'),
    _PaletteEntry('Integrations', Icons.extension_outlined, 'integrations'),
    _PaletteEntry('Scheduled Tasks', Icons.schedule_outlined, 'tasks'),
    _PaletteEntry('Providers', Icons.key_outlined, 'providers'),
    _PaletteEntry('Theme', Icons.palette_outlined, 'theme'),
  ];

  @override
  Widget build(BuildContext context) {
    final hits = _entries
        .where((e) => e.label.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassContainer(
        radius: 28,
        opacity: 0.75,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                onChanged: (q) => setState(() => _query = q),
                style: const TextStyle(fontSize: 16, color: Colors.black87),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, color: Colors.black54),
                  hintText: 'Search gork',
                  hintStyle: TextStyle(color: Colors.black54),
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in hits)
                      GlassMenuRow(
                        icon: e.icon,
                        label: e.label,
                        onTap: () {
                          Navigator.of(context).pop();
                          _navigate(context, e.route);
                        },
                      ),
                    if (hits.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Nothing found.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigate(BuildContext context, String route) {
    final screens = {
      'inbox': const InboxScreen(),
      'panels': const PanelsScreen(),
      'projects': const ProjectsScreen(),
      'vault': const VaultScreen(),
      'cloud': const CloudComputerScreen(),
      'integrations': const IntegrationsScreen(),
      'tasks': const TasksScreen(),
      'providers': const ProvidersScreen(),
      'theme': const ThemePage(),
    };
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screens[route]!),
    );
  }
}

class _PaletteEntry {
  const _PaletteEntry(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}
