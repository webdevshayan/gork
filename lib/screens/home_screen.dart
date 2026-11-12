import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';
import 'chat_screen.dart';
import 'cloud_computer_screen.dart';
import 'inbox_screen.dart';
import 'integrations_screen.dart';
import 'panels_screen.dart';
import 'projects_screen.dart';
import 'providers_screen.dart';
import 'tasks_screen.dart';
import 'vault_screen.dart';

/// One feature card on the home grid.
class FeatureTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const FeatureTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return GCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(RadiusTokens.lg),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(RadiusTokens.md),
              ),
              child: Icon(icon, color: palette.primary, size: 24),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TypeScale.heading(color: palette.textPrimary)),
                  const SizedBox(height: Spacing.xs),
                  Text(subtitle,
                      style: TypeScale.caption(color: palette.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: palette.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Home: greeting + grid of features (grows as features land).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Screen(
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        children: [
          GCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('gork', style: TypeScale.display(color: palette.textPrimary)),
                const SizedBox(height: Spacing.xs),
                Text(
                  'gork: your personal AI assistant',
                  style: TypeScale.body(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          FeatureTile(
            icon: Icons.chat_bubble_outline,
            label: 'Chat',
            subtitle: 'Talk to your own AI provider (BYOK)',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatScreen()),
            ),
          ),
          FeatureTile(
            icon: Icons.settings_outlined,
            label: 'Providers',
            subtitle: 'Bring your own API keys (stored only on this phone)',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProvidersScreen()),
            ),
          ),
          FeatureTile(
            icon: Icons.folder_outlined,
            label: 'Projects',
            subtitle: 'Workspaces with notes and files',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProjectsScreen()),
            ),
          ),
          FeatureTile(
            icon: Icons.lock_outline,
            label: 'Vault',
            subtitle: 'Encrypted passwords and secrets on this device',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VaultScreen()),
            ),
          ),
          FeatureTile(
            icon: Icons.schedule_outlined,
            label: 'Tasks',
            subtitle: 'Timed jobs the AI runs for you',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TasksScreen()),
            ),
          ),
          FeatureTile(
            icon: Icons.dns_outlined,
            label: 'Cloud Computer',
            subtitle: 'Self-hosted or free-tier browser agent backend',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CloudComputerScreen()),
            ),
          ),
          FeatureTile(
            icon: Icons.dashboard_outlined,
            label: 'Panels',
            subtitle: 'Mini-dashboards, starting with live weather',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PanelsScreen()),
            ),
          ),
          FeatureTile(
            icon: Icons.inbox_outlined,
            label: 'Inbox',
            subtitle: 'Proactive suggestions with one-tap actions',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InboxScreen()),
            ),
          ),
          FeatureTile(
            icon: Icons.extension_outlined,
            label: 'Integrations',
            subtitle: 'GitHub, Slack, Strava, Spotify, Gmail, PayPal — your tokens',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IntegrationsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
