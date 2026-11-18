import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matcher/matcher.dart' as m;

import 'package:gork/constants/ambient.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/widgets/ambient_backdrop.dart';

class _BlockedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient();
}

class _BlockedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in widget tests');
}

Widget _wrap(Brightness brightness) => MediaQuery(
      data: MediaQueryData(platformBrightness: brightness),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(body: Stack(children: [const AmbientBackdrop()])),
      ),
    );

void main() {
  setUpAll(() {
    HttpOverrides.global = _BlockedOverrides();
  });

  setUp(() async {
    // The solar helpers read the stored location through Locator.prefs.
    SharedPreferences.setMockInitialValues({});
    Locator.bind(prefs: await SharedPreferences.getInstance());
  });

  test('the ambient backdrop carries NO bundled photo assets', () {
    // The photos were removed in Movement 57 and nothing replaced them —
    // the backdrop is a pure gradient.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('assets/ambient'), isFalse);
    expect(Directory('assets/ambient').existsSync(), isFalse);
  });

  testWidgets('light backdrop paints a soft neutral gray (never black)',
      (tester) async {
    GlassColors.brightness.value = Brightness.light;
    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump();

    final backdrop = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('ambient-backdrop-solid')),
    );
    final decoration = backdrop.decoration as BoxDecoration;
    // Movement 60 — SOLID: a flat color, no gradient.
    expect(decoration.gradient, isNull);
    final color = decoration.color!;
    // The solid is a light gray — the black startup flash stays gone.
    expect(color.computeLuminance(), greaterThan(0.5));
    expect(color.r, closeTo(color.g, 1 / 255),
        reason: 'the theme is gray and black, nothing else');
    expect(find.byKey(const ValueKey('ambient-backdrop')), findsOneWidget);
  });

  testWidgets('dark backdrop sinks to near-black neutral gray',
      (tester) async {
    GlassColors.brightness.value = Brightness.dark;
    // Clear the tree first: the backdrop rebuilds when the brightness
    // notifier fires (as the app shell does); standalone, the element is
    // reused across pumpWidget and the builder would never re-run.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump();

    final backdrop = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('ambient-backdrop-solid')),
    );
    final color = (backdrop.decoration as BoxDecoration).color!;
    expect(color.computeLuminance(), lessThan(0.05));
    expect(color.r, closeTo(color.g, 1 / 255),
        reason: 'no colored tint — gray and black only');
  });

  testWidgets('the published resolution alone flips the backdrop '
      '(the notifier drives the flat color)', (tester) async {
    GlassColors.brightness.value = Brightness.light;
    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump();
    expect(
        ((tester.widget<DecoratedBox>(
                    find.byKey(const ValueKey('ambient-backdrop-solid'))))
                .decoration as BoxDecoration)
            .color!,
        m.predicate<Color>((c) => c.computeLuminance() > 0.5));

    GlassColors.brightness.value = Brightness.dark;
    // Clear the tree first: the notifier fires but the element is reused
    // across pumpWidget and the builder would never re-run.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump();
    expect(
        ((tester.widget<DecoratedBox>(
                    find.byKey(const ValueKey('ambient-backdrop-solid'))))
                .decoration as BoxDecoration)
            .color!,
        m.predicate<Color>((c) => c.computeLuminance() < 0.05));
  });

  testWidgets('backdrop makes zero network calls and loads zero images '
      '(fully offline)', (tester) async {
    AmbientBackdrop.clock = () => DateTime(2026, 11, 14, 12, 0);
    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    // Any Image.network would throw against the blocked client; any asset
    // Image would need the (deleted) ambient entries.
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the gradient API no longer takes phases or weather', () {
    // Movement 59: gray and black, nothing else — one gradient per mode.
    expect(ambientGradient(true).length, 2);
    expect(ambientGradient(false).length, 2);
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });
}
