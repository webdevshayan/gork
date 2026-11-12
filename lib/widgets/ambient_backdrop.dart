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

/// Full-screen blurred ambient sky/ocean photo. Every glass surface blurs
/// whatever is behind it, so this sits at the bottom of the shell Stack.
/// Offline (or in tests) it falls back to a sky gradient.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({super.key});

  static const String _skyUrl =
      'https://images.unsplash.com/photo-1505118380757-91f5f5632de0'
      '?auto=format&fit=crop&w=1200&q=80';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: themeSetting,
      builder: (context, mode, _) {
        final bool dark = mode == 'Dark';
        return SizedBox.expand(
          key: const ValueKey('ambient-backdrop'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Image.network(
                  _skyUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) => const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF7FB4DC),
                          Color(0xFFBFDCEF),
                          Color(0xFFF6E7C8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (dark)
                Container(
                  key: const ValueKey('theme-scrim'),
                  color: Colors.black.withValues(alpha: 0.45),
                ),
            ],
          ),
        );
      },
    );
  }
}
