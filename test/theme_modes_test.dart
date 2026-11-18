// Movement 59 — the theme system is GONE. One mode remains: auto.
//
// What the user asked for, verbatim:
//   * the theme is gray / grey with different variants and black — and
//     NOTHING else;
//   * remove the theme system (the Light/Dark/System/Auto picker page);
//   * just use the auto: dark mode after some time, light mode after some
//     time — the sun decides, nobody taps anything.
//
// These tests pin the new reality: the palette is achromatic, the picker
// no longer exists, any 'ui.theme' saved by older installs is ignored,
// and a clock change alone flips the whole app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/constants/ambient.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/services/weather_service.dart';
import 'package:gork/screens/gork_shell.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/widgets/bottom_input_bar.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/widgets/ambient_backdrop.dart';
import 'package:gork/widgets/glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    // Every test starts from the app's shipping default: dark glass.
    GlassColors.brightness.value = Brightness.dark;
    AmbientBackdrop.clock = DateTime.now;
  });

  group('resolveBrightness — auto only, no modes left', () {
    final noon = DateTime(2026, 11, 14, 12, 0);
    final night = DateTime(2026, 11, 14, 22, 30);
    final deep = DateTime(2026, 11, 14, 3, 0);
    final dawn = DateTime(2026, 11, 14, 6, 30);

    test('midday is light — even if the OS says dark', () {
      expect(resolveBrightness(Brightness.dark, noon), Brightness.light);
    });

    test('evening and deep night are dark — even if the OS says light', () {
      expect(resolveBrightness(Brightness.light, night), Brightness.dark);
      expect(resolveBrightness(Brightness.light, deep), Brightness.dark);
    });

    test('dawn belongs to the day', () {
      expect(resolveBrightness(Brightness.dark, dawn), Brightness.light);
    });

    test('with a location the real sun decides, not the wall clock', () {
      const double lat = 26.4195, lon = 67.8622;
      final DateTime sunrise =
          sunriseFor(lat, lon, DateTime.utc(2026, 11, 14));
      final DateTime sunset =
          sunsetFor(lat, lon, DateTime.utc(2026, 11, 14));
      expect(
          resolveBrightness(Brightness.dark,
              sunrise.add(const Duration(hours: 2)),
              lat: lat, lon: lon),
          Brightness.light);
      expect(
          resolveBrightness(Brightness.light,
              sunset.add(const Duration(hours: 1)),
              lat: lat, lon: lon),
          Brightness.dark);
    });
  });

  group('GlassColors — solid surfaces that follow the resolved brightness', () {
    test('dark: fills are the SOLID dark surfaces (no alpha, Movement 60)',
        () {
      GlassColors.brightness.value = Brightness.dark;
      expect(GlassColors.fill.computeLuminance(), lessThan(0.2));
      expect(GlassColors.text, const Color(0xFFF2F2F2));
      expect(GlassColors.fill, resolvedPalette.value.surface);
      expect(GlassColors.fill.opacity, 1.0,
          reason: 'solid background — no translucency anywhere');
      expect(GlassColors.fillStrong, resolvedPalette.value.surfaceElevated);
    });

    test('light mode gets light solid fills, light borders, dark text', () {
      GlassColors.brightness.value = Brightness.light;
      // Light solid fill: the white surface.
      expect(GlassColors.fill.computeLuminance(), greaterThan(0.7));
      expect(GlassColors.fill, Palette.light.surface);
      expect(GlassColors.fillStrong, Palette.light.surfaceElevated);
      // Text tokens are the light palette's — readable on white glass.
      expect(GlassColors.text, Palette.light.textPrimary);
      expect(GlassColors.textDim, Palette.light.textSecondary);
      expect(GlassColors.textFaint, Palette.light.textTertiary);
      // Borders and dividers derive from the palette border, translucent.
      expect(GlassColors.border,
          resolvedPalette.value.border.withValues(alpha: 0.85));
      expect(GlassColors.divider,
          resolvedPalette.value.border.withValues(alpha: 0.70));
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

  group('the theme system is gone', () {
    testWidgets('the menu no longer offers a Theme entry', (tester) async {
      SharedPreferences.setMockInitialValues({});
      Locator.bind(prefs: await SharedPreferences.getInstance());
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsNothing,
          reason: 'the picker page was removed — auto is the only mode');
    });
  });

  group('a saved ui.theme from older installs is ignored', () {
    testWidgets('ui.theme=Dark does NOT pin dark at noon', (tester) async {
      SharedPreferences.setMockInitialValues(
          {'onboarding.done': true, 'ui.theme': 'Dark'});
      Locator.bind(prefs: await SharedPreferences.getInstance());
      // Mid-morning at the stored location: the auto answer is LIGHT
      // (sun-relative — wall-clock hours mean different things per zone).
      final DateTime sunrise = sunriseFor(Locator.ambientLat,
          Locator.ambientLon, DateTime.utc(2026, 11, 14));
      AmbientBackdrop.clock =
          () => sunrise.add(const Duration(hours: 2));
      await tester.pumpWidget(const GorkApp());
      await tester.pumpAndSettle();
      expect(GlassColors.brightness.value, Brightness.light,
          reason: 'the manual override was removed — auto always wins');
      expect(resolvedPalette.value.background, Palette.light.background);
    });
  });

  group('backdrop — the clock alone decides', () {
    testWidgets('deep local night dims dark on a light platform',
        (tester) async {
      // Sun-relative clock: 3 hours past sunset at the stored location —
      // night, no matter which timezone the test box runs in.
      final DateTime sunset = sunsetFor(
          Locator.ambientLat, Locator.ambientLon, DateTime.utc(2026, 11, 14));
      AmbientBackdrop.clock = () => sunset.add(const Duration(hours: 3));
      await tester.pumpWidget(_wrap(Brightness.light));
      await tester.pump();
      expect(_gradientOf(tester).colors.first.computeLuminance(),
          lessThan(0.1),
          reason: 'the dark gradient sinks to near-black');
    });

    testWidgets('local morning stays light on a dark platform',
        (tester) async {
      // 2 hours past sunrise at the stored location — full daylight.
      final DateTime sunrise = sunriseFor(
          Locator.ambientLat, Locator.ambientLon, DateTime.utc(2026, 11, 14));
      AmbientBackdrop.clock = () => sunrise.add(const Duration(hours: 2));
      await tester.pumpWidget(_wrap(Brightness.dark));
      await tester.pump();
      expect(_gradientOf(tester).colors.first.computeLuminance(),
          greaterThan(0.5));
    });

    testWidgets('the backdrop gradient is achromatic in both modes',
        (tester) async {
      await tester.pumpWidget(_wrap(Brightness.dark));
      await tester.pump();
      final darkColors = _gradientOf(tester).colors;
      for (final c in darkColors) {
        expect(c.r, closeTo(c.g, 1 / 255), reason: 'dark backdrop is gray');
      }
      await tester.pumpWidget(_wrap(Brightness.light));
      await tester.pump();
      final lightColors = _gradientOf(tester).colors;
      for (final c in lightColors) {
        expect(c.r, closeTo(c.g, 1 / 255), reason: 'light backdrop is gray');
      }
    });
  });

  group('the auto flip repaints every glass consumer', () {
    testWidgets('the ambient nudge flips the whole shell (no const '
        'short-circuit)', (tester) async {
      SharedPreferences.setMockInitialValues({'onboarding.done': true});
      Locator.bind(prefs: await SharedPreferences.getInstance());
      // Start mid-morning at the stored location — the shell resolves
      // LIGHT.
      final DateTime sunrise = sunriseFor(Locator.ambientLat,
          Locator.ambientLon, DateTime.utc(2026, 11, 14));
      AmbientBackdrop.clock =
          () => sunrise.add(const Duration(hours: 2));
      await tester.pumpWidget(const GorkApp());
      await tester.pumpAndSettle();
      expect(GlassColors.brightness.value, Brightness.light);

      // Open the menu so its glass rows are on stage.
      await tester.tap(find.byKey(const ValueKey('avatar')));
      await tester.pumpAndSettle();

      // Time passes — the sun sets. Only the clock changes; the nudge
      // (ambient.refresh) re-resolves, and the glass must follow.
      final DateTime sunset = sunsetFor(
          Locator.ambientLat, Locator.ambientLon, DateTime.utc(2026, 11, 14));
      AmbientBackdrop.clock = () => sunset.add(const Duration(hours: 3));
      ambient.refresh();
      await tester.pumpAndSettle();

      expect(GlassColors.brightness.value, Brightness.dark,
          reason: 'dark mode arrives after some time, with no user action');
      final container = tester.widget<Container>(find.descendant(
        of: find.byType(GlassContainer),
        matching: find.byType(Container),
      ).first);
      final fill = (container.decoration as BoxDecoration).color!;
      expect(fill.computeLuminance(), lessThan(0.2),
          reason: 'glass must follow the resolved theme immediately — a '
              'const OnboardingGate would short-circuit the rebuild '
              '(the v1.7.0 screenshot bug)');
    });
  });

  group('input bar alignment', () {
    testWidgets('the attach icon centers with the mic icon', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BottomInputBar(
              controller: controller,
              focusNode: FocusNode(),
              onSend: (_) {},
              onAttach: () {},
            ),
          ),
        ),
      ));

      final double plusDy = tester.getCenter(find.byIcon(Icons.add)).dy;
      final double micDy = tester.getCenter(find.byIcon(Icons.mic_none)).dy;
      expect((plusDy - micDy).abs(), lessThan(1.0),
          reason: 'bottom-aligned boxes of different heights make the + '
              'ride ~4dp lower than the mic on a single line');
    });
  });
}

DecoratedBox _backdropOf(WidgetTester tester) => tester.widget<DecoratedBox>(
    find.byKey(const ValueKey('ambient-backdrop-gradient')));

LinearGradient _gradientOf(WidgetTester tester) =>
    (_backdropOf(tester).decoration as BoxDecoration).gradient
        as LinearGradient;

Widget _wrap(Brightness platform) {
  return MediaQuery(
    data: MediaQueryData(platformBrightness: platform),
    child: const MaterialApp(home: AmbientBackdrop()),
  );
}
