import 'dart:ui';

import 'package:flutter/material.dart';

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
    return SizedBox.expand(
      key: const ValueKey('ambient-backdrop'),
      child: ImageFiltered(
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
    );
  }
}
