import 'package:flutter/material.dart';

import '../constants/ambient.dart';
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
/// nothing else — the backdrop is a barely-there vertical gray fade that
/// follows the auto resolution (light by day, dark by night). No photos, no
/// weather washes, no phase tints.
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
        // Inside the app the shell publishes the resolution; standalone
        // (tests, early frames) resolve from the clock directly.
        final Brightness platform =
            MediaQuery.platformBrightnessOf(context);
        final Brightness effective = resolveBrightness(
            platform, clock(),
            lat: Locator.bound ? Locator.ambientLat : null,
            lon: Locator.bound ? Locator.ambientLon : null);
        final bool dark = effective == Brightness.dark;
        return SizedBox.expand(
          key: const ValueKey('ambient-backdrop'),
          child: DecoratedBox(
            key: const ValueKey('ambient-backdrop-gradient'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: ambientGradient(dark),
              ),
            ),
          ),
        );
      },
    );
  }
}
