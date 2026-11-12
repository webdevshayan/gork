import 'dart:ui';

import 'package:flutter/material.dart';

/// Hark-style glass primitives — every floating surface in the shell is built
/// from these. Spec: ClipRRect + BackdropFilter(blur 10) + white 0.3–0.4 fill
/// + thin white 0.5 border. Cards use radius 16, pills and input bars use 30.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.radius = 16,
    this.opacity = 0.3,
    this.sigma = 10,
    this.padding = EdgeInsets.zero,
    this.width,
    this.height,
  });

  final Widget child;
  final double radius;
  final double opacity;
  final double sigma;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Circular glass button used in the top bar (menu / back).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: 30,
      width: 44,
      height: 44,
      opacity: 0.35,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(child: Icon(icon, size: 20, color: Colors.black87)),
      ),
    );
  }
}

/// The black action chip from the spec: green check + white label.
class GlassActionChip extends StatelessWidget {
  const GlassActionChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 16, color: Color(0xFF34C759)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Menu row used across the profile/menu surface and the theme page:
/// icon + label + optional trailing widget, tap = whole row.
class GlassMenuRow extends StatelessWidget {
  const GlassMenuRow({
    super.key,
    required this.label,
    this.icon,
    this.trailing,
    this.onTap,
  });

  final IconData? icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 22, color: Colors.black87),
              const SizedBox(width: 16),
            ],
            Text(
              label,
              style: const TextStyle(fontSize: 17, color: Colors.black87),
            ),
            const Spacer(),
            trailing ??
                const Icon(Icons.chevron_right, size: 20, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}

/// The round radio from the theme page: outlined circle, selected = dark
/// ring with a solid black dot.
class GlassRadio extends StatelessWidget {
  const GlassRadio({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? Colors.black87 : Colors.black38,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.black87,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

/// Floating circular glass button with a chevron — the scroll-to-bottom
/// control from the chat screenshots.
class GlassScrollButton extends StatelessWidget {
  const GlassScrollButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      radius: 26,
      width: 52,
      height: 52,
      opacity: 0.55,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const Center(
          child: Icon(Icons.keyboard_arrow_down, size: 26, color: Colors.black54),
        ),
      ),
    );
  }
}
