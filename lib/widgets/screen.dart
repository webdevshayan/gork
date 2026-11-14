import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import 'ambient_backdrop.dart';
import 'glass.dart';

/// The ONE pushed-screen scaffold: sky backdrop behind, glass chevron back
/// button, token-styled title. Every pushed page (Providers, Projects,
/// onboarding, wallet, ...) renders through this so the whole app shares the
/// shell's theme and the ambient image — the plain opaque Material look is
/// gone (Movement 42).
class Screen extends StatelessWidget {
  const Screen({
    super.key,
    this.title,
    required this.body,
    this.fab,
    this.actions,
  });

  final String? title;
  final Widget body;

  /// Kept for the Projects list FAB — placed by the inner Scaffold.
  final Widget? fab;

  /// Trailing widgets in the top bar (e.g. page-specific buttons).
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const AmbientBackdrop(),
        Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: true,
          floatingActionButton: fab,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      if (Navigator.of(context).canPop())
                        GlassIconButton(
                          key: const ValueKey('screen-back'),
                          icon: Icons.arrow_back_ios_new,
                          semanticLabel: 'Back',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      if (title != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title!,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: GlassColors.text,
                            ),
                          ),
                        ),
                      ],
                      ...?actions,
                    ],
                  ),
                ),
                Expanded(
                  // The horizontal gutter the old opaque Screen provided —
                  // every body relies on it (their ListViews pad vertically
                  // only).
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: Spacing.md),
                    child: body,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
