import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/weather_service.dart';
import 'package:gork/screens/gork_shell.dart';
import 'package:gork/widgets/bottom_input_bar.dart';
import 'package:gork/widgets/ambient_backdrop.dart';
import 'package:gork/widgets/glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 34: one glass theme everywhere. Movement 59: that theme is
/// GRAY and BLACK only, resolved by the clock alone — the backdrop is the
/// gradient, the message-box buttons stay pinned to the bottom-right no
/// matter how tall the text grows.
void main() {
  setUp(() async {
    // The solar helpers read the stored location through Locator.prefs.
    SharedPreferences.setMockInitialValues({});
    Locator.bind(prefs: await SharedPreferences.getInstance());
    AmbientBackdrop.clock = DateTime.now;
    GlassColors.brightness.value = Brightness.dark;
  });

  testWidgets('paletteOf resolves the dark palette even on a light platform',
      (tester) async {
    late Palette captured;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Builder(builder: (context) {
        captured = paletteOf(context);
        return const SizedBox();
      }),
    ));
    expect(captured.background, Palette.dark.background);
    expect(captured.surface, Palette.dark.surface);
    expect(captured.textPrimary, Palette.dark.textPrimary);
    // Movement 59: the dark palette is achromatic — no blue tint.
    expect(captured.background.r, closeTo(captured.background.g, 1 / 255));
    expect(captured.surface.b, closeTo(captured.surface.g, 1 / 255));
  });

  testWidgets('GlassContainer fills dark with a subtle border — never white',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(body: GlassContainer(child: SizedBox())),
    ));
    final container = tester.widget<Container>(find.descendant(
      of: find.byType(GlassContainer),
      matching: find.byType(Container),
    ).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, GlassColors.fill);
    expect((decoration.border as Border).top.color, GlassColors.border);
    expect(decoration.color!.computeLuminance(), lessThan(0.2));
  });

  testWidgets('input bar: attach and send sit at the bottom-right even when '
      'the message box grows tall', (tester) async {
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
    await tester.pump();

    Rect barRect(String key) =>
        tester.getRect(find.byKey(ValueKey(key)));
    final attach1 = barRect('attach-button');
    final bar1 = barRect('input-bar');
    // single line: already bottom-right, not vertically centered
    expect(attach1.bottom, greaterThan(bar1.center.dy));
    expect(bar1.bottom - attach1.bottom, lessThan(24));
    expect(attach1.right, greaterThan(bar1.center.dx));

    // four lines of text: the bar grows, the buttons must stay pinned
    controller.text = 'line one\nline two\nline three\nline four';
    await tester.pump();
    final attach2 = barRect('attach-button');
    final bar2 = barRect('input-bar');
    expect(bar2.height, greaterThan(bar1.height));
    expect(attach2.bottom, greaterThan(bar2.center.dy));
    expect(bar2.bottom - attach2.bottom, lessThan(24));
    expect(attach2.right, greaterThan(bar2.center.dx));
  });

  testWidgets('backdrop paints the near-black neutral gradient in dark mode',
      (tester) async {
    final DateTime sunset = sunsetFor(
        Locator.ambientLat, Locator.ambientLon, DateTime.utc(2026, 11, 14));
    AmbientBackdrop.clock = () => sunset.add(const Duration(hours: 3));
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(platformBrightness: Brightness.light),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(body: AmbientBackdrop()),
      ),
    ));
    await tester.pump();
    // No photo layers at all — the gradient IS the backdrop.
    expect(find.byType(Image), findsNothing);
    final gradient = _gradientOf(tester);
    expect(gradient.colors.first.computeLuminance(), lessThan(0.05));
    for (final c in gradient.colors) {
      expect(c.r, closeTo(c.g, 1 / 255),
          reason: 'gray and black, nothing else');
    }
  });

  testWidgets('backdrop keeps the light neutral gradient in light mode',
      (tester) async {
    // Mid-morning at the stored location (sun-relative — a wall-clock hour
    // means different things per longitude).
    final DateTime sunrise = sunriseFor(
        Locator.ambientLat, Locator.ambientLon, DateTime.utc(2026, 11, 14));
    AmbientBackdrop.clock = () => sunrise.add(const Duration(hours: 2));
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(platformBrightness: Brightness.light),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(body: AmbientBackdrop()),
      ),
    ));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(_gradientOf(tester).colors.first.computeLuminance(),
        greaterThan(0.5));
  });

  test('the ambient photos are gone from pubspec and disk', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('assets/ambient'), isFalse);
    expect(Directory('assets/ambient').existsSync(), isFalse);
  });

  testWidgets('dark gradient — never a white startup flash in dark mode',
      (tester) async {
    final DateTime sunset = sunsetFor(
        Locator.ambientLat, Locator.ambientLon, DateTime.utc(2026, 11, 14));
    AmbientBackdrop.clock = () => sunset.add(const Duration(hours: 3));
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(platformBrightness: Brightness.light),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(body: AmbientBackdrop()),
      ),
    ));
    await tester.pump();
    expect(_gradientOf(tester).colors.first.computeLuminance(), lessThan(0.05));
  });

  testWidgets('Movement 59 — the attach menu can never clip off the right '
      'screen edge (screenshot bug)', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.bind(prefs: await SharedPreferences.getInstance());
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attach-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('attach-menu')), findsOneWidget);
    final menuRect = tester.getRect(find.byKey(const ValueKey('attach-menu')));
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(menuRect.right, lessThanOrEqualTo(screenWidth),
        reason: 'the menu right edge must stay on screen');
    expect(menuRect.left, greaterThanOrEqualTo(0));
  });
}

LinearGradient _gradientOf(WidgetTester tester) =>
    ((tester.widget<DecoratedBox>(
                find.byKey(const ValueKey('ambient-backdrop-gradient'))))
            .decoration as BoxDecoration)
        .gradient as LinearGradient;
