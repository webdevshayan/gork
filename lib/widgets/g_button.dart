import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';

enum ButtonVariant { primary, secondary, ghost }

/// Token-driven button. Capsule-rounded (radius full), label bodySmall semibold.
/// Movement 50: black & white only — primary is ink/near-white, never blue.
class GButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final bool expands;

  const GButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.expands = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    Color bg;
    Color fg;
    Border? border;

    switch (variant) {
      case ButtonVariant.primary:
        bg = palette.primary;
        fg = palette.onPrimary;
        break;
      case ButtonVariant.secondary:
        // Movement 60 — solid fill, no transparency on any button.
        bg = palette.surfaceElevated;
        fg = palette.textPrimary;
        border = Border.all(color: palette.border, width: 1);
        break;
      case ButtonVariant.ghost:
        // Solid too — quieter than secondary, still opaque.
        bg = palette.surface;
        fg = palette.primary;
        break;
    }

    final Widget content = Container(
      // Movement 68 — 48dp, not 44: the smallest comfortable target for
      // any finger, any age (Material accessibility guidance).
      height: 48,
      // Movement 67 — the label used to touch the pill's edge (screenshots
      // 2026-11-19: "New chat"/"Add file"/"Add image" looked clipped on the
      // project screen). Real horizontal padding, like every other chip.
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(RadiusTokens.full),
        border: border,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TypeScale.bodySmall(color: fg).copyWith(fontWeight: FontWeight.w600),
      ),
    );

    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: expands ? double.infinity : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(RadiusTokens.full),
            onTap: onPressed,
            child: content,
          ),
        ),
      ),
    );
  }
}
