import 'package:flutter/material.dart';

import '../constants/version.dart';
import '../widgets/glass.dart';
import 'integrations_screen.dart';
import 'providers_screen.dart';
import 'search_screen.dart';
import 'tasks_screen.dart';
import 'theme_page.dart';
import 'updates_screen.dart';
import 'vault_screen.dart';

/// The profile/menu surface (opened from the avatar), pixel-matched to the
/// reference: big identity header, the "gork pro" plan card, a card of rows
/// (Profile / Scheduled Tasks / Accounts / Wallet), a Security card, and the
/// Search pill that opens the chat search. No tab is selected here.
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
                      color: Colors.black45,
                    ),
                  ),
            onTap: () => _push(context, const UpdatesScreen()),
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
            onTap: () => _push(
              context,
              SearchScreen(onOpenChat: onOpenChat ?? (_) {}),
            ),
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
          'free & open source — your keys, your data',
          style: TextStyle(fontSize: 12, color: Colors.black38),
          textAlign: TextAlign.center,
        ),
      ],
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
