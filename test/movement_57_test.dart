import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/screens/gork_shell.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/profile_info.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/widgets/ambient_backdrop.dart';
import 'package:gork/widgets/attach_menu.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Blocks raw Image.network calls.
class _BlockedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient();
}

class _BlockedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in widget tests');
}

/// Fake picker platform: hands back a real file, no method-channel codec.
class _MockPickerPlatform extends ImagePickerPlatform {
  _MockPickerPlatform(this.file);
  final File file;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile(file.path);
}

Color _navLabelColor(WidgetTester tester, String label) => DefaultTextStyle.of(
      tester.element(find.text(label)),
    ).style.color!;

void main() {
  setUpAll(() {
    HttpOverrides.global = _BlockedOverrides();
    // path_provider mock: the avatar flow writes under the support dir.
    TestWidgetsFlutterBinding.ensureInitialized();
    Directory('/tmp/gork-test-support').createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '/tmp/gork-test-support',
    );
  });

  tearDownAll(() {
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
      httpClient: MockClient((request) async => http.Response('offline', 500)),
    );
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();
  }

  group('Movement 57 — system back is reversible', () {
    testWidgets('back on the Chat tab returns to Home', (tester) async {
      await pumpShell(tester);
      // Movement 62 — the shell LANDS on chat; back from the landing tab
      // still goes to Home (reversible), and back on Home exits.
      expect(_navLabelColor(tester, 'Chat'), GlassColors.textOnChip);

      await tester.tap(find.byKey(const ValueKey('tab-home')));
      await tester.pumpAndSettle();
      expect(_navLabelColor(tester, 'Home'), GlassColors.textOnChip);

      await tester.tap(find.byKey(const ValueKey('tab-chat')));
      await tester.pumpAndSettle();
      expect(_navLabelColor(tester, 'Chat'), GlassColors.textOnChip);

      // The system back affordance (three-button nav / gesture).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_navLabelColor(tester, 'Home'), GlassColors.textOnChip,
          reason: 'back from Chat must land on Home, not exit');
    });

    testWidgets('back on Projects returns to Home, then back again exits',
        (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byKey(const ValueKey('tab-projects')));
      await tester.pumpAndSettle();
      expect(_navLabelColor(tester, 'Projects'), GlassColors.textOnChip);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_navLabelColor(tester, 'Home'), GlassColors.textOnChip);
    });

    testWidgets('back closes the settings surface to the last core tab',
        (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byKey(const ValueKey('tab-chat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('avatar')));
      await tester.pumpAndSettle();
      expect(find.text(kDefaultName), findsOneWidget,
          reason: 'the settings surface shows the identity header');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(kDefaultName), findsNothing,
          reason: 'back closed the settings surface');
      expect(_navLabelColor(tester, 'Chat'), GlassColors.textOnChip,
          reason: 'and returned to the tab the user came from');
    });

    testWidgets('back with the attach menu open dismisses the menu first',
        (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byKey(const ValueKey('tab-home')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attach-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attach-menu')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attach-menu')), findsNothing);
      // Still on Home — the app did NOT exit.
      expect(_navLabelColor(tester, 'Home'), GlassColors.textOnChip);
    });
  });

  group('Movement 57 — the dropdown anchors to its trigger', () {
    testWidgets('attach menu sits on top of the input row, content-sized, '
        'never off-screen (Movement 59 screenshot fix)', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byKey(const ValueKey('attach-button')));
      await tester.pumpAndSettle();

      final menu =
          tester.getRect(find.byKey(const ValueKey('attach-menu')));
      final plus =
          tester.getRect(find.byKey(const ValueKey('attach-button')));
      final bar =
          tester.getRect(find.byKey(const ValueKey('input-bar')));
      final screen = tester.getSize(find.byType(MaterialApp));

      // Content-sized: the fixed 220dp card, never stretched to the screen.
      expect(menu.width, 220);
      expect(menu.width, lessThan(screen.width));

      // Flush to the TOP of the input bar: the menu's bottom edge is 8dp
      // above the row's top edge (Movement 59 anchors to the ROW, whose
      // right edge is structurally inside the screen).
      expect(menu.bottom, lessThan(bar.top));
      expect(bar.top - menu.bottom, lessThan(20));

      // Right-aligned with the row's right edge — near the + and, crucially,
      // INSIDE the screen on every device (the screenshot bug had the
      // chevrons clipped off the right edge).
      expect((menu.right - bar.right).abs(), lessThan(8));
      expect(menu.right, lessThan(screen.width));
    });

    testWidgets('tapping away dismisses the dropdown', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byKey(const ValueKey('attach-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attach-menu')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('attach-scrim')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attach-menu')), findsNothing);
    });

    testWidgets('the pushed-chat attach sheet still offers the same menu',
        (tester) async {
      // AttachMenu.show is a modal bottom sheet ABOVE the input area —
      // content-sized, at the bottom of the screen (Movement 57 contract).
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          captured = context;
          return const Scaffold(body: SizedBox());
        }),
      ));
      final Future<AttachKind?> shown = AttachMenu.show(captured);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attach-menu')), findsOneWidget);
      final menu = tester.getRect(find.byKey(const ValueKey('attach-menu')));
      expect(menu.width, 220);
      Navigator.of(captured).pop();
      await tester.pumpAndSettle();
      expect(await shown, isNull);
    });
  });

  group('Movement 57 — real-time state', () {
    testWidgets('the menu identity follows the profile notifiers live',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
      await tester.pump();
      expect(find.text(kDefaultName), findsOneWidget);

      profileName.value = 'Ada Test';
      profileEmail.value = 'ada@example.com';
      await tester.pump();

      expect(find.text('Ada Test'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget,
          reason: 'saved profile edits land immediately — no stale surface');
    });

    testWidgets('avatar re-upload writes a NEW file and updates everywhere',
        (tester) async {
      final photo = File('/tmp/gork-test-avatar.jpg')
        ..writeAsBytesSync(List.generate(64, (i) => i % 255));
      final originalPicker = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = _MockPickerPlatform(photo);
      addTearDown(() => ImagePickerPlatform.instance = originalPicker);

      await pumpShell(tester);
      // Avatar tap 1: opens the settings surface. Tap 2 (on surface): sheet.
      // The upload does REAL file I/O — wrap the flow in runAsync so the
      // futures flush, and pump() explicitly because runAsync does NOT pump
      // frames on its own.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('avatar')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.tap(find.byKey(const ValueKey('avatar')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(const ValueKey('choose-photo')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();

      final prefs = Locator.prefs;
      final firstPath = prefs.getString('profile.photoPath');
      expect(firstPath, isNotNull);
      expect(firstPath!.contains('gork-avatar-'), isTrue,
          reason: 'unique per-upload filename busts the ImageCache');
      expect(avatarPath.value, firstPath);

      // Second upload: the path must CHANGE (the re-upload bug fix).
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('avatar')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(const ValueKey('choose-photo')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();

      final secondPath = prefs.getString('profile.photoPath');
      expect(secondPath, isNotNull);
      expect(secondPath, isNot(firstPath),
          reason: 'each upload gets its own file — the cache never serves '
              'the old photo again');
      expect(avatarPath.value, secondPath);
      expect(File(firstPath).existsSync(), isFalse,
          reason: 'the previous avatar file is cleaned up');
    });
  });
}
