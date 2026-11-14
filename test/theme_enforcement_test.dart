import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/screens/onboarding_screen.dart';
import 'package:gork/screens/providers_screen.dart';
import 'package:gork/screens/projects_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/widgets/ambient_backdrop.dart';
import 'package:gork/widgets/glass.dart';
import 'package:gork/widgets/screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 42 — one theme, one backdrop, everywhere. Every pushed screen
/// uses the same glass system and the sky image as the shell; back buttons
/// are chevrons; sheets are glass; the menu has no gork wordmark card; the
/// nav pill slides and the active label is black.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(prefs: await SharedPreferences.getInstance());
  });

  group('Movement 42 — the sky reaches every pushed screen', () {
    Widget host(Widget child) => MaterialApp(
          home: Builder(builder: (context) {
            // A base route below so back buttons can pop.
            return GestureDetector(onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => child),
              );
            }, child: const Scaffold(body: SizedBox()));
          }),
        );

    Future<void> pushAndCheck(WidgetTester tester, Widget screen) async {
      await tester.pumpWidget(host(screen));
      await tester.tap(find.byType(GestureDetector));
      await tester.pumpAndSettle();
    }

    testWidgets('Providers screen has the sky backdrop', (tester) async {
      await pushAndCheck(tester, const ProvidersScreen());
      expect(find.byType(AmbientBackdrop), findsOneWidget);
    });

    testWidgets('Projects screen has the sky backdrop', (tester) async {
      await pushAndCheck(tester, const ProjectsScreen());
      expect(find.byType(AmbientBackdrop), findsOneWidget);
    });

    testWidgets('Onboarding has the sky backdrop', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(onFinished: () {}),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AmbientBackdrop), findsOneWidget);
    });

    testWidgets('Screen renders a chevron back button, not the arrow',
        (tester) async {
      await pushAndCheck(
        tester,
        const Screen(title: 'Chevron check', body: SizedBox()),
      );
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });
  });

  group('Movement 42 — sheets and cards follow the glass tokens', () {
    test('no bottom sheet is painted an opaque color', () {
      // Source guard: every showModalBottomSheet in the screens must be
      // transparent so the glass container inside provides the surface.
      const files = [
        'lib/screens/chat_screen.dart',
        'lib/screens/providers_screen.dart',
        'lib/screens/projects_screen.dart',
        'lib/screens/projects_surface.dart',
      ];
      final offenders = <String>[];
      for (final path in files) {
        final src = File(path).readAsStringSync();
        var idx = src.indexOf('showModalBottomSheet');
        while (idx != -1) {
          final chunk = src.substring(idx, (idx + 220).clamp(0, src.length));
          if (chunk.contains('backgroundColor: Colors.white') ||
              chunk.contains('backgroundColor: palette.surface')) {
            offenders.add(path);
            break;
          }
          idx = src.indexOf('showModalBottomSheet', idx + 1);
        }
      }
      expect(offenders, isEmpty,
          reason: 'opaque sheets break the glass theme: $offenders');
    });

    test('search hit cards and project folder cards use GlassColors', () {
      final offenders = <String>[];
      for (final path in const [
        'lib/screens/search_screen.dart',
        'lib/screens/projects_surface.dart',
      ]) {
        final src = File(path).readAsStringSync();
        if (src.contains('Colors.white.withValues') ||
            src.contains('color: Colors.white')) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'light-only hard-coded cards wash out in dark mode: '
              '$offenders');
    });
  });

  group('Movement 42 — menu and top bar', () {
    testWidgets('the menu screen has no gork wordmark card', (tester) async {
      GlassColors.brightness.value = Brightness.light;
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
      await tester.pumpAndSettle();
      expect(find.text('gork'), findsNothing,
          reason: 'the branding card is removed — the menu starts with rows');
    });

    test('the active nav label reads black in light mode', () {
      GlassColors.brightness.value = Brightness.light;
      final color = GlassColors.textOnChip;
      expect(color.computeLuminance(), lessThan(0.2),
          reason: 'active tab label must be black in light mode');
      GlassColors.brightness.value = Brightness.dark;
      expect(GlassColors.textOnChip.computeLuminance(), lessThan(0.2),
          reason: 'the chip is near-white in dark mode, so the label is '
              'black there too');
    });
  });
}
