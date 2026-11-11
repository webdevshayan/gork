import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../widgets/g_card.dart';
import '../widgets/screen.dart';
import 'providers_screen.dart';

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
            icon: Icons.settings_outlined,
            label: 'Providers',
            subtitle: 'Bring your own API keys (stored only on this phone)',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProvidersScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
