import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';

/// Token-driven card: surface background, radius lg, md padding.
/// Level 1 elevation via shadow in light mode; lighter surface in dark mode.
class GCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const GCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: isDark ? palette.surfaceElevated : palette.surface,
        borderRadius: BorderRadius.circular(RadiusTokens.lg),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: Elevation.level1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: child,
    );
  }
}
