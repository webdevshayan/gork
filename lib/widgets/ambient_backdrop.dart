import 'package:flutter/material.dart';

import '../constants/design_tokens.dart';
import '../services/locator.dart';

/// Path of the user's chosen profile photo (null = show the person icon).
/// The photo lives on the device only — nothing networked.
final ValueNotifier<String?> avatarPath = ValueNotifier<String?>(null);

/// Restores the persisted profile photo path. Called once from main().
Future<void> initProfilePhoto() async {
  avatarPath.value = Locator.prefs.getString('profile.photoPath');
}

/// Full-screen ambient backdrop. Movement 59: the theme is GRAY and BLACK,
/// nothing else. Movement 60: SOLID — the flat palette background, no
/// gradient, no wash. It follows the resolved brightness (the shell's
/// manual-override-aware resolution).
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  /// Injectable clock — tests pin Auto's local-time behavior without
  /// waiting for the real hour of the day. The app shell also reads this
  /// for its resolution, so tests can move the sun for everything at once.
  static DateTime Function() clock = DateTime.now;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Brightness>(
      valueListenable: GlassColors.brightness,
      builder: (context, _, __) {
        final bool dark = GlassColors.brightness.value == Brightness.dark;
        return SizedBox.expand(
          key: const ValueKey('ambient-backdrop'),
          child: DecoratedBox(
            key: const ValueKey('ambient-backdrop-solid'),
            decoration: BoxDecoration(
              color: dark
                  ? const Color(0xFF060607)
                  : const Color(0xFFF1F2F3),
            ),
          ),
        );
      },
    );
  }
}
