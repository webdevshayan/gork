import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gork/constants/ambient.dart';
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

  test('the ambient backdrop carries NO bundled photo assets (Movement 57)',
      () {
    // The photos were removed — the backdrop is pure theme now. The pubspec
    // must not reference them and the files must not exist.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('assets/ambient'), isFalse);
    expect(Directory('assets/ambient').existsSync(), isFalse);
  });

  testWidgets('backdrop paints a light gruvbox gradient (never black)',
      (tester) async {
    themeSetting.value = 'Light';
    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump();

    final backdrop = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('ambient-backdrop-gradient')),
    );
    final gradient = backdrop.decoration as BoxDecoration;
    expect(gradient.gradient, isA<LinearGradient>());
    // The first stop is a cream gruvbox tone — black startup flash is gone.
    final first = (gradient.gradient as LinearGradient).colors.first;
    expect(first.computeLuminance(), greaterThan(0.3));
    expect(find.byKey(const ValueKey('ambient-backdrop')), findsOneWidget);
  });

  testWidgets('dark mode paints the deep gruvbox dark gradient',
      (tester) async {
    themeSetting.value = 'Dark';
    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump();

    final backdrop = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('ambient-backdrop-gradient')),
    );
    final colors =
        (backdrop.decoration as BoxDecoration).gradient as LinearGradient;
    expect(colors.colors.first.computeLuminance(), lessThan(0.2));
  });

  testWidgets('System follows the system brightness', (tester) async {
    themeSetting.value = 'System'; // Movement 39: System = the OS
    await tester.pumpWidget(_wrap(Brightness.dark));
    await tester.pump();
    final darkColors =
        ((tester.widget<DecoratedBox>(
                    find.byKey(const ValueKey('ambient-backdrop-gradient'))))
                .decoration as BoxDecoration)
            .gradient as LinearGradient;
    expect(darkColors.colors.first.computeLuminance(), lessThan(0.2));

    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump();
    final lightColors =
        ((tester.widget<DecoratedBox>(
                    find.byKey(const ValueKey('ambient-backdrop-gradient'))))
                .decoration as BoxDecoration)
            .gradient as LinearGradient;
    expect(lightColors.colors.first.computeLuminance(), greaterThan(0.3));
  });

  testWidgets('backdrop makes zero network calls and loads zero images '
      '(fully offline)', (tester) async {
    themeSetting.value = 'Light';
    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    // Any Image.network would throw against the blocked client; any asset
    // Image would need the (deleted) ambient entries.
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('the sunset window is the warm gruvbox gradient', () {
    final sunset = ambientGradient(AmbientPhase.evening, true);
    // Ember top over the gruvbox dark floor: warm red channel dominates.
    expect(sunset.first.r, greaterThan(sunset.first.b));
    expect(sunset.last, const Color(0xFF1D2021));
  });

  tearDownAll(() {
    HttpOverrides.global = null;
    themeSetting.value = null;
  });
}
