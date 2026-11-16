import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/screens/gork_shell.dart';
import 'package:gork/widgets/bottom_input_bar.dart';
import 'package:gork/widgets/ambient_backdrop.dart';
import 'package:gork/widgets/glass.dart';

/// Movement 34: one dark glass theme everywhere. Blur surfaces and borders go
/// dark (no more white translucent fills), the backdrop image is absolutely
/// positioned and swaps to the moon/night-sky asset in dark mode, and the
/// message-box buttons stay pinned to the bottom-right no matter how tall
/// the text grows.
void main() {
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

  testWidgets('backdrop swaps to the dark gruvbox gradient in dark mode',
      (tester) async {
    themeSetting.value = 'Dark';
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(platformBrightness: Brightness.light),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(body: AmbientBackdrop()),
      ),
    ));
    await tester.pump();
    // Movement 57: no photo layers at all — the gradient IS the backdrop.
    expect(find.byType(Image), findsNothing);
    final gradient = _gradientOf(tester);
    expect(gradient.colors.first.computeLuminance(), lessThan(0.2));
  });

  testWidgets('backdrop keeps the light gruvbox gradient in light mode',
      (tester) async {
    themeSetting.value = 'Light';
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
        greaterThan(0.3));
  });

  test('the ambient photos are gone from pubspec and disk', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('assets/ambient'), isFalse);
    expect(Directory('assets/ambient').existsSync(), isFalse);
  });

  testWidgets('dark gradient — never a white startup flash in dark mode',
      (tester) async {
    themeSetting.value = 'Dark';
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(platformBrightness: Brightness.light),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Scaffold(body: AmbientBackdrop()),
      ),
    ));
    await tester.pump();
    expect(_gradientOf(tester).colors.first.computeLuminance(), lessThan(0.2));
  });
}

LinearGradient _gradientOf(WidgetTester tester) =>
    ((tester.widget<DecoratedBox>(
                find.byKey(const ValueKey('ambient-backdrop-gradient'))))
            .decoration as BoxDecoration)
        .gradient as LinearGradient;
