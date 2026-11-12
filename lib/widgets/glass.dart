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
