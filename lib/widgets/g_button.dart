import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';

enum ButtonVariant { primary, secondary, ghost }

/// Token-driven button. Default radius md, label uses bodySmall semibold.
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
        bg = Colors.transparent;
        fg = palette.textPrimary;
        border = Border.all(color: palette.border, width: 1);
        break;
      case ButtonVariant.ghost:
        bg = Colors.transparent;
        fg = palette.primary;
        break;
    }

    final Widget content = Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(RadiusTokens.md),
        border: border,
      ),
      child: Text(
        label,
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
            borderRadius: BorderRadius.circular(RadiusTokens.md),
            onTap: onPressed,
            child: content,
          ),
        ),
      ),
    );
  }
}
