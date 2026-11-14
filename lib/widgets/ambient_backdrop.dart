import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/ambient.dart';
import '../services/locator.dart';

/// Theme override chosen on the Theme page (Auto/System/Light/Dark).
/// 'Dark' swaps the backdrop to the night sky and dims it; the other modes
/// leave the day sky untouched.
final ValueNotifier<String?> themeSetting = ValueNotifier<String?>(null);

/// The raw mode chosen on the Theme page ('Auto' / 'System' / 'Light' /
/// 'Dark'), persisted at 'ui.theme'. The app shell resolves it (Movement 39)
/// and publishes the result through [themeSetting] — the backdrop and every
/// GlassColors consumer follow that single resolution.
final ValueNotifier<String> themeModeSetting = ValueNotifier<String>('System');

/// Loads the persisted theme mode. Called once from main(), before runApp —
/// the very first frame already has the right mode.
void initTheme() {
  try {
    themeModeSetting.value = Locator.prefs.getString('ui.theme') ?? 'System';
  } catch (_) {
    // Locator unbound (widget tests) — 'System' stays.
  }
}

/// Path of the user's chosen profile photo (null = show the person icon).
/// The photo lives on the device only — nothing networked.
final ValueNotifier<String?> avatarPath = ValueNotifier<String?>(null);

/// Restores the persisted profile photo path. Called once from main().
Future<void> initProfilePhoto() async {
  avatarPath.value = Locator.prefs.getString('profile.photoPath');
}

/// Full-screen ambient backdrop. Both photos are bundled assets — the app is
/// fully offline. The image is painted absolutely (Positioned.fill + cover)
/// over a matching gradient so there is never a flash while it decodes:
/// a light sky gradient in light mode, a deep night gradient in dark mode.
///
/// Overlays (contrast pass):
///   * Light mode gets a white wash over the day sky.
///   * Dark mode gets the moon + night-sky photo under a soft black scrim.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  static const String _dayAsset = 'assets/ambient/sky.jpg';
  static const String _nightAsset = 'assets/ambient/night.jpg';

  static const Color _lightScrim = Colors.white;
  static const Color _darkScrim = Colors.black;

  /// Injectable clock — tests pin Auto's local-time behavior without
  /// waiting for the real hour of the day.
  static DateTime Function() clock = DateTime.now;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: themeSetting,
      builder: (context, mode, _) {
        final Brightness platform =
            MediaQuery.platformBrightnessOf(context);
        // The shell publishes the RESOLVED mode here ('Light'/'Dark');
        // 'Auto'/'System'/null resolve locally so the backdrop stays
        // correct even when used standalone (tests, early frames).
        final Brightness effective = resolveBrightness(mode, platform, clock());
        final bool dark = effective == Brightness.dark;
        return SizedBox.expand(
          key: const ValueKey('ambient-backdrop'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Always painted first: no jarring background while the asset
              // decodes (cold start included).
              DecoratedBox(
                key: const ValueKey('ambient-placeholder'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: dark
                        ? const [
                            Color(0xFF0B1026),
                            Color(0xFF05070F),
                            Color(0xFF0A0F1E),
                          ]
                        : const [
                            Color(0xFF8FC0E8),
                            Color(0xFFC9E2F2),
                            Color(0xFFF7ECD4),
                          ],
                  ),
                ),
              ),
              // Absolute cover: the photo fills the screen no matter the
              // aspect ratio, behind everything.
              Positioned.fill(
                // RepaintBoundary: holding an overscroll repaints the glass
                // BackdropFilters every frame — the sky's raster must NOT be
                // re-filtered with them or the blur visibly collapses.
                child: RepaintBoundary(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Image.asset(
                      key: ValueKey(dark ? 'ambient-night' : 'ambient-day'),
                      dark ? _nightAsset : _dayAsset,
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                ),
              ),
              Container(
                key: const ValueKey('theme-scrim'),
                color: dark
                    ? _darkScrim.withValues(alpha: 0.30)
                    : _lightScrim.withValues(alpha: 0.25),
              ),
            ],
          ),
        );
      },
    );
  }
}
