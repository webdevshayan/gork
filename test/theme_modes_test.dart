// Movement 39 — the theme modes become real.
//
// What the user asked for, verbatim:
//   * light mode uses LIGHT backgrounds, borders and the like (the
//     Movement 34 "everything is dark" lock is overridden on demand);
//   * dark mode stays as it is;
//   * System follows the OS theme;
//   * Auto follows the LOCAL TIME, not the OS.
//
// Before this movement the app hardcoded ThemeMode.dark, the glass colors
// were compile-time dark constants, and "Auto" and "System" both meant
// "whatever the OS says" — Auto never looked at the clock.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/constants/ambient.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/screens/theme_page.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/widgets/ambient_backdrop.dart';
import 'package:gork/widgets/glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    // Every test starts from the app's shipping default: dark glass.
    GlassColors.brightness.value = Brightness.dark;
    AmbientBackdrop.clock = DateTime.now;
    themeSetting.value = null;
    themeModeSetting.value = 'System';
  });

  group('resolveBrightness — the mode table', () {
    final noon = DateTime(2026, 11, 14, 12, 0);
    final night = DateTime(2026, 11, 14, 22, 30);
    final deep = DateTime(2026, 11, 14, 3, 0);
    final dawn = DateTime(2026, 11, 14, 6, 30);

    test('Light and Dark are explicit overrides', () {
      expect(resolveBrightness('Light', Brightness.dark, night),
          Brightness.light);
      expect(resolveBrightness('Dark', Brightness.light, noon),
          Brightness.dark);
    });

    test('System follows the OS — even at midnight', () {
      expect(resolveBrightness('System', Brightness.dark, noon),
          Brightness.dark);
      expect(resolveBrightness('System', Brightness.light, noon),
          Brightness.light);
    });

    test('Auto follows the local clock, not the OS', () {
      // Midday: light, even if the OS says dark.
      expect(resolveBrightness('Auto', Brightness.dark, noon),
          Brightness.light);
      // 17:00+ and before 05:00: dark, even if the OS says light.
      expect(resolveBrightness('Auto', Brightness.light, night),
          Brightness.dark);
      expect(resolveBrightness('Auto', Brightness.light, deep),
          Brightness.dark);
      // Dawn (05:00–08:00) belongs to the day.
      expect(resolveBrightness('Auto', Brightness.dark, dawn),
          Brightness.light);
    });

    test('an unknown mode falls back to Auto', () {
      expect(resolveBrightness(null, Brightness.dark, noon),
          Brightness.light);
      expect(resolveBrightness('nonsense', Brightness.light, night),
          Brightness.dark);
    });
  });

  group('GlassColors — the glass switches with the resolved brightness', () {
    test('dark stays the Movement 34 glass exactly', () {
      GlassColors.brightness.value = Brightness.dark;
      expect(GlassColors.fill.computeLuminance(), lessThan(0.2));
      expect(GlassColors.text, const Color(0xFFF2F4F7));
      expect(GlassColors.fill, const Color(0xB312141A));
      expect(GlassColors.fillStrong, const Color(0xCC12141A));
    });

    test('light mode gets light fills, light borders, dark text', () {
      GlassColors.brightness.value = Brightness.light;
      // Light glass: a bright white fill over the sky backdrop.
      expect(GlassColors.fill.computeLuminance(), greaterThan(0.7));
      // Stronger chrome is more opaque, not more luminous — white
      // luminance is capped at 1.0.
      expect(GlassColors.fillStrong.alpha, greaterThan(GlassColors.fill.alpha));
      // Text tokens are the light palette's — readable on white glass.
      expect(GlassColors.text, Palette.light.textPrimary);
      expect(GlassColors.textDim, Palette.light.textSecondary);
      expect(GlassColors.textFaint, Palette.light.textTertiary);
      // Borders and dividers are quiet dark hairlines in light mode.
      expect(GlassColors.border.computeLuminance(), lessThan(0.5));
      expect(GlassColors.divider.computeLuminance(), lessThan(0.5));
    });
  });

  group('paletteOf — every paletteOf consumer follows the resolution', () {
    testWidgets('resolves the light palette when the app resolves light',
        (tester) async {
      GlassColors.brightness.value = Brightness.light;
      late Palette captured;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          captured = paletteOf(context);
          return const SizedBox();
        }),
      ));
      expect(captured.background, Palette.light.background);
      expect(captured.surface, Palette.light.surface);
    });

    testWidgets('resolves dark again when the app resolves dark',
        (tester) async {
      GlassColors.brightness.value = Brightness.dark;
      late Palette captured;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          captured = paletteOf(context);
          return const SizedBox();
        }),
      ));
      expect(captured.background, Palette.dark.background);
    });
  });

  group('the Theme page persists the chosen mode', () {
    testWidgets('tapping Auto persists ui.theme and notifies the app',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Locator.bind(prefs: prefs);
      await tester.pumpWidget(const MaterialApp(home: ThemePage()));

      await tester.tap(find.byKey(const ValueKey('theme-auto')));
      await tester.pump();

      expect(prefs.getString('ui.theme'), 'Auto');
      expect(themeModeSetting.value, 'Auto');

      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pump();
      expect(prefs.getString('ui.theme'), 'Dark');
      expect(themeModeSetting.value, 'Dark');
    });
  });

  group('initTheme — the persisted mode drives the app on startup', () {
    test('reads ui.theme into the mode notifier', () async {
      SharedPreferences.setMockInitialValues({'ui.theme': 'Dark'});
      Locator.bind(prefs: await SharedPreferences.getInstance());
      themeModeSetting.value = 'System';
      initTheme();
      expect(themeModeSetting.value, 'Dark');
    });

    test('defaults to System when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      Locator.bind(prefs: await SharedPreferences.getInstance());
      themeModeSetting.value = 'Dark';
      initTheme();
      expect(themeModeSetting.value, 'System');
    });
  });

  group('backdrop — Auto is the local clock, System is the OS', () {
    testWidgets('Auto at 22:30 dims dark even on a light platform',
        (tester) async {
      AmbientBackdrop.clock =
          () => DateTime(2026, 11, 14, 22, 30);
      themeSetting.value = 'Auto';
      await tester.pumpWidget(_wrap(Brightness.light));
      await tester.pump();
      expect(
        tester
            .widget<Container>(find.byKey(const ValueKey('theme-scrim')))
            .color,
        Colors.black.withValues(alpha: 0.30),
      );
    });

    testWidgets('Auto at noon stays light even on a dark platform',
        (tester) async {
      AmbientBackdrop.clock = () => DateTime(2026, 11, 14, 12, 0);
      themeSetting.value = 'Auto';
      await tester.pumpWidget(_wrap(Brightness.dark));
      await tester.pump();
      expect(
        tester
            .widget<Container>(find.byKey(const ValueKey('theme-scrim')))
            .color,
        Colors.white.withValues(alpha: 0.25),
      );
    });

    testWidgets('System follows the platform brightness', (tester) async {
      themeSetting.value = 'System';
      await tester.pumpWidget(_wrap(Brightness.dark));
      await tester.pump();
      expect(
        tester
            .widget<Container>(find.byKey(const ValueKey('theme-scrim')))
            .color,
        Colors.black.withValues(alpha: 0.30),
      );
      await tester.pumpWidget(_wrap(Brightness.light));
      await tester.pump();
      expect(
        tester
            .widget<Container>(find.byKey(const ValueKey('theme-scrim')))
            .color,
        Colors.white.withValues(alpha: 0.25),
      );
    });
  });
}

Widget _wrap(Brightness platform) {
  return MediaQuery(
    data: MediaQueryData(platformBrightness: platform),
    child: const MaterialApp(home: AmbientBackdrop()),
  );
}
