import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';

/// Standard screen wrapper: token-driven background, md horizontal padding,
/// safe area, optional app bar title.
class Screen extends StatelessWidget {
  final String? title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? fab;

  const Screen({super.key, this.title, required this.body, this.actions, this.fab});

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: title == null
          ? null
          : AppBar(
              backgroundColor: palette.background,
              surfaceTintColor: palette.background,
              foregroundColor: palette.textPrimary,
              elevation: 0,
              title: Text(title!, style: TypeScale.heading(color: palette.textPrimary)),
              actions: actions,
            ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: body,
        ),
      ),
    );
  }
}
