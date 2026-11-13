import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('the ambient sky is a bundled offline asset', () async {
    final data = await rootBundle.load('assets/ambient/sky.jpg');
    expect(data.lengthInBytes, greaterThan(10000));
  });

  testWidgets('backdrop paints a light gradient placeholder (never black) '
      'before/behind the image', (tester) async {
    themeSetting.value = null;
    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump();

    final placeholder = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('ambient-placeholder')),
    );
    final gradient = placeholder.decoration as BoxDecoration;
    expect(gradient.gradient, isA<LinearGradient>());
    // The first stop is a light sky tone — black startup flash is gone.
    final first =
        (gradient.gradient as LinearGradient).colors.first;
    expect(first.computeLuminance(), greaterThan(0.3));
    expect(find.byKey(const ValueKey('ambient-backdrop')), findsOneWidget);
  });

  testWidgets('light mode lays a WHITE overlay over the backdrop', (
    tester,
  ) async {
    themeSetting.value = 'Light';
    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump();

    final scrim = tester.widget<Container>(
      find.byKey(const ValueKey('theme-scrim')),
    );
    final color = scrim.color!;
    expect(color, Colors.white.withValues(alpha: 0.25));
  });

  testWidgets('dark mode dims with a black scrim', (tester) async {
    themeSetting.value = 'Dark';
    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump();

    final scrim = tester.widget<Container>(
      find.byKey(const ValueKey('theme-scrim')),
    );
    expect(scrim.color, Colors.black.withValues(alpha: 0.30));
  });

  testWidgets('Auto follows the system brightness', (tester) async {
    themeSetting.value = null; // Auto
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

  testWidgets('backdrop makes zero network calls (fully offline)', (
    tester,
  ) async {
    themeSetting.value = null;
    await tester.pumpWidget(_wrap(Brightness.light));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    // If any Image.network existed, the blocked client would have thrown.
    expect(tester.takeException(), isNull);
  });

  tearDownAll(() {
    HttpOverrides.global = null;
    themeSetting.value = null;
  });
}
