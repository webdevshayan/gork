import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';

/// Hark-style glass primitives — every floating surface in the shell is built
/// from these. Spec: ClipRRect + BackdropFilter(blur 10) + dark glass fill
/// + thin light border. Cards use radius 16, pills and input bars use 30.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.radius = 16,
    this.opacity = 0.3,
    this.sigma = 10,
    this.padding = EdgeInsets.zero,
    this.margin,
    this.width,
    this.height,
    this.strong = false,
  });

  final Widget child;
  final double radius;
  final double opacity;
  final double sigma;
  final EdgeInsetsGeometry padding;

  /// Outer margin — wraps the whole container so callers keep one widget.
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  /// More opaque dark chrome (input bar, top bar pills).
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final Widget body = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: strong ? GlassColors.fillStrong : GlassColors.fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: GlassColors.border,
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
    if (margin != null) {
      return Padding(padding: margin!, child: body);
    }
    return body;
  }
}

/// Circular glass button used in the top bar (menu / back).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// TalkBack name for icon-only buttons (a11y guard tests require it).
  final String? semanticLabel;

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
        child: Center(
          child: Icon(icon, size: 20, color: GlassColors.text,
              semanticLabel: semanticLabel),
        ),
      ),
    );
  }
}

/// The reusable back affordance: a glass chevron with a TalkBack label.
/// Every screen-level back control uses THIS so navigation looks and sounds
/// identical everywhere (Movement 44).
class GlassBackButton extends StatelessWidget {
  const GlassBackButton({
    super.key,
    this.label = 'Back',
    this.onTap,
  });

  /// The TalkBack name — 'Back', 'Back to workspace', 'Close search', ...
  final String label;

  /// Defaults to popping the navigator; pass null and handle taps outside.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      icon: Icons.arrow_back_ios_new,
      semanticLabel: label,
      onTap: onTap ?? () => Navigator.of(context).pop(),
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
              Icon(icon, size: 22, color: GlassColors.text),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, color: GlassColors.text),
              ),
            ),
            const SizedBox(width: 12),
            trailing ??
                Icon(Icons.chevron_right, size: 20, color: GlassColors.textDim),
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
          color: selected ? GlassColors.text : GlassColors.textFaint,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: GlassColors.text,
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
        child: Center(
          child: Icon(Icons.keyboard_arrow_down, size: 26, color: GlassColors.textDim),
        ),
      ),
    );
  }
}
