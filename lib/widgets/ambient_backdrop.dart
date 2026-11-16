import 'package:flutter/material.dart';

import '../constants/ambient.dart';
import '../constants/design_tokens.dart';
import '../services/locator.dart';

/// Theme override chosen on the Theme page (Auto/System/Light/Dark).
/// The app shell publishes the RESOLVED mode here every cycle.
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

/// Full-screen ambient gradient (Movement 57). The old photo assets are
/// gone — the backdrop IS the theme now: a phase + weather gradient
/// (gruvbox-inspired) painted behind every glass surface. No decoding, no
/// flash, fully offline, and it shifts with the sun and the sky outside.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  /// Injectable clock — tests pin Auto's local-time behavior without
  /// waiting for the real hour of the day. The app shell also reads this
  /// for its resolution, so tests can move the sun for everything at once.
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
        final Brightness effective = resolveBrightness(mode, platform,
            clock(),
            lat: Locator.bound ? Locator.ambientLat : null,
            lon: Locator.bound ? Locator.ambientLon : null);
        final bool dark = effective == Brightness.dark;
        // Inside the app the shell publishes the (solar) phase via the
        // scope; standalone — read the clock directly.
        final scope = context
            .dependOnInheritedWidgetOfExactType<AmbientScope>();
        final AmbientPhase phase =
            scope?.phase ?? phaseFor(clock());
        final AmbientWeather weather =
            scope?.weather ?? ambient.weather;
        return SizedBox.expand(
          key: const ValueKey('ambient-backdrop'),
          child: DecoratedBox(
            key: const ValueKey('ambient-backdrop-gradient'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: ambientGradient(phase, dark, weather: weather),
              ),
            ),
          ),
        );
      },
    );
  }
}
