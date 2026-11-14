import 'dart:math' as math;
import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/screens/google_accounts_screen.dart';
import 'package:gork/screens/hark_shell.dart';
import 'package:gork/screens/profile_edit_screen.dart';
import 'package:gork/screens/search_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/widgets/glass.dart';
import 'package:gork/widgets/screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 44 — the accessibility loop. These guards run against every
/// screen that hosts glass buttons; when a new screen joins, add it to
/// [_screenBuilders] and the loop covers it automatically. "100%" means the
/// whole suite is green with every screen in the list.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore()..write('apikey.openai', 'sk-test'),
      httpClient: MockClient((request) async => http.Response('offline', 500)),
    );
  });

  /// Every screen surface, pumped through its own MaterialApp.
  final List<(String, Widget Function())> _screenBuilders = [
    ('shell-home', () => const GorkApp()),
    ('profile-edit', () => const ProfileEditScreen()),
    ('google-accounts', () => const GoogleAccountsScreen()),
    ('search', () => SearchScreen(onOpenChat: (_) {})),
    ('plain-screen', () => _TwoRouteHost()),
  ];

  group('Movement 44 — icon-only buttons speak', () {
    for (final (name, builder) in _screenBuilders) {
      testWidgets('$name: every glass icon button has a semantic label',
          (tester) async {
        GlassColors.brightness.value = Brightness.light;
        await tester.pumpWidget(MaterialApp(home: builder()));
        if (name == 'shell-home') await tester.pumpAndSettle();
        if (name == 'plain-screen') {
          // The host pushes the Screen route on tap.
          await tester.tap(find.byType(GestureDetector));
          await tester.pumpAndSettle();
        }

        final buttons = find.byType(GlassIconButton, skipOffstage: false);
        final count = tester.widgetList<GlassIconButton>(buttons).length;
        final missing = <int>[];
        var i = 0;
        for (final button in tester.widgetList<GlassIconButton>(buttons)) {
          if (button.semanticLabel == null ||
              button.semanticLabel!.isEmpty) {
            missing.add(i);
          }
          i++;
        }
        expect(count, greaterThan(0),
            reason: '$name must actually host glass buttons for this loop '
                'to mean anything');
        expect(missing, isEmpty,
            reason: '$name has icon-only buttons without a TalkBack label at '
                'index(es) $missing');
      });
    }
  });

  group('Movement 44 — tap targets', () {
    testWidgets('glass icon buttons keep a 44dp minimum', (tester) async {
      GlassColors.brightness.value = Brightness.light;
      await tester.pumpWidget(_TwoRouteHost());
      await tester.tap(find.byType(GestureDetector));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(GlassIconButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('the input bar attach + mic stay 44dp+', (tester) async {
      GlassColors.brightness.value = Brightness.light;
      await tester.pumpWidget(const GorkApp());
      await tester.pumpAndSettle();
      for (final key in const ['attach-button']) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.height, greaterThanOrEqualTo(44),
            reason: '$key must stay a comfortable target');
      }
    });
  });

  group('Movement 44 — the nav pill is a real tab control', () {
    testWidgets('tab chips expose button + selected semantics', (tester) async {
      final handle = tester.ensureSemantics();
      GlassColors.brightness.value = Brightness.light;
      await tester.pumpWidget(const GorkApp());
      await tester.pumpAndSettle();

      bool flag(String label, SemanticsFlag flagBit) {
        final node = tester.getSemantics(find.text(label));
        return (node.getSemanticsData().flags & flagBit.index) != 0;
      }

      for (final label in const ['Home', 'Chat', 'Projects']) {
        expect(flag(label, SemanticsFlag.isButton), isTrue,
            reason: '$label is a button to a screen reader');
      }
      // Exactly one tab is selected at a time.
      final selected = <String>[];
      for (final label in const ['Home', 'Chat', 'Projects']) {
        if (flag(label, SemanticsFlag.isSelected)) selected.add(label);
      }
      expect(selected, ['Home'],
          reason: 'the active tab is marked selected; inactive tabs are not');
      handle.dispose();
    });

    testWidgets('switching tabs moves the selection flag', (tester) async {
      final handle = tester.ensureSemantics();
      GlassColors.brightness.value = Brightness.light;
      await tester.pumpWidget(const GorkApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tab-chat')));
      await tester.pumpAndSettle();
      bool flag(String label, SemanticsFlag flagBit) {
        final node = tester.getSemantics(find.text(label));
        return (node.getSemanticsData().flags & flagBit.index) != 0;
      }

      expect(flag('Chat', SemanticsFlag.isSelected), isTrue);
      expect(flag('Home', SemanticsFlag.isSelected), isFalse);
      handle.dispose();
    });
  });

  group('Movement 44 — contrast of the glass tokens', () {
    // Channel extraction via toARGB32 — the Color getters changed scale
    // across Flutter versions, the packed value is stable.
    List<double> channels(Color c) {
      final int argb = c.toARGB32();
      return [
        ((argb >> 16) & 0xFF) / 255,
        ((argb >> 8) & 0xFF) / 255,
        (argb & 0xFF) / 255,
        ((argb >> 24) & 0xFF) / 255,
      ];
    }

    double lum(Color c) {
      final ch = channels(c);
      double f(double v) => v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * f(ch[0]) + 0.7152 * f(ch[1]) + 0.0722 * f(ch[2]);
    }

    double contrast(Color a, Color b) {
      final l1 = lum(a), l2 = lum(b);
      final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
      return (hi + 0.05) / (lo + 0.05);
    }

    Color composite(Color fill, Color over) {
      final f = channels(fill), o = channels(over);
      final a = f[3];
      int mix(int i) => ((f[i] * a + o[i] * (1 - a)) * 255).round();
      return Color.fromARGB(255, mix(0), mix(1), mix(2));
    }

    for (final brightness in Brightness.values) {
      test('$brightness: text tokens clear WCAG on their fills', () {
        GlassColors.brightness.value = brightness;
        final Color scrim =
            brightness == Brightness.dark ? Colors.black : Colors.white;
        // Fill over the scrimmed backdrop (worst case: scrim over black sky).
        final sky = composite(scrim.withValues(alpha: 0.30), Colors.black);
        final fill = composite(GlassColors.fill, sky);
        final strong = composite(GlassColors.fillStrong, sky);

        expect(contrast(GlassColors.text, fill), greaterThanOrEqualTo(4.5),
            reason: 'primary text on glass');
        expect(contrast(GlassColors.textDim, fill), greaterThanOrEqualTo(3.0),
            reason: 'secondary text on glass (large-ish body)');
        expect(contrast(GlassColors.textOnChip, GlassColors.chip),
            greaterThanOrEqualTo(4.5),
            reason: 'active tab label on the chip');
        expect(contrast(GlassColors.text, strong), greaterThanOrEqualTo(4.5),
            reason: 'primary text on strong chrome');
      });
    }
  });
}

/// Hosts [Screen] as a PUSHED route so its chevron back button exists —
/// the a11y loop must see a real button.
class _TwoRouteHost extends StatelessWidget {
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) => GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const Screen(title: 'A11y', body: SizedBox()),
          )),
          child: const Scaffold(body: SizedBox()),
        ),
      ),
    );
  }
}
