import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/locator.dart';

/// Theme override chosen on the Theme page (Auto/System/Light/Dark).
/// 'Dark' dims the ambient backdrop; the other modes leave it untouched.
final ValueNotifier<String?> themeSetting = ValueNotifier<String?>(null);

/// Path of the user's chosen profile photo (null = show the person icon).
/// The photo lives on the device only — nothing networked.
final ValueNotifier<String?> avatarPath = ValueNotifier<String?>(null);

/// Restores the persisted profile photo path. Called once from main().
Future<void> initProfilePhoto() async {
  avatarPath.value = Locator.prefs.getString('profile.photoPath');
}

/// Full-screen blurred ambient sky. The photo is a bundled asset — the app
/// is fully offline — and a light sky gradient is always painted underneath
/// it, so there is never a black flash while the image decodes.
///
/// Overlays (contrast pass):
///   * Light surfaces get a WHITE wash over the photo, so black87 text and
///     glass read cleanly.
///   * Dark dims with a black scrim.
///   * Auto/System follow the platform brightness.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  static const String _skyAsset = 'assets/ambient/sky.jpg';

  static const Color _lightScrim = Colors.white;
  static const Color _darkScrim = Colors.black;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: themeSetting,
      builder: (context, mode, _) {
        final Brightness platform =
            MediaQuery.platformBrightnessOf(context);
        final bool dark =
            mode == 'Dark' ||
            ((mode == null || mode == 'Auto' || mode == 'System') &&
                platform == Brightness.dark);
        return SizedBox.expand(
          key: const ValueKey('ambient-backdrop'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Always painted first: no black background while the asset
              // decodes (cold start included).
              const DecoratedBox(
                key: ValueKey('ambient-placeholder'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF8FC0E8),
                      Color(0xFFC9E2F2),
                      Color(0xFFF7ECD4),
                    ],
                  ),
                ),
              ),
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Image.asset(
                  _skyAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
              Container(
                key: const ValueKey('theme-scrim'),
                color: dark
                    ? _darkScrim.withValues(alpha: 0.45)
                    : _lightScrim.withValues(alpha: 0.35),
              ),
            ],
          ),
        );
      },
    );
  }
}
