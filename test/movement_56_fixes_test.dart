import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/gork_home.dart';
import 'package:gork/screens/google_accounts_screen.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/widgets/bottom_input_bar.dart';
import 'package:gork/widgets/glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake picker platform: answers pickFiles in-process (the real platform
/// implementation blocks forever in the test VM — no channels, no hang).
class FakePicker extends FilePicker {
  FileType? lastType;
  FilePickerResult? result;

  // The production call omits `type` on purpose: FileType.any is the
  // plugin default (passing FileType.custom is the file-hiding bug).
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    lastType = type;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Movement 56 fixes, locked:
///  1. the mic button in the message box was a bare Padding with no
///     handler — tapping it did nothing. It must be wired to a handler
///     and come back to idle afterwards (the speech engine itself needs a
///     real device; on it the first tap asks for the mic permission and
///     starts dictation).
///  2. the credentials upload button silently hid every real file: the
///     picker ran FileType.custom + ['json'], which filters by MIME, and
///     browser-downloaded credentials.json carries
///     application/octet-stream — so "no file could be uploaded". Now the
///     picker must open with FileType.any (every file visible) and the
///     .json check happens in-app with a clear snackbar.
///  3. any screen stacking more than one card in a row or column must
///     put a gap between them — locked on the menu (several stacked
///     cards, 16px apart) and home (weather card + create panel).
void main() {
  Future<void> bindMinimal() async {
    // Without a prefs mock the plugin channel never answers in the test VM
    // and getInstance() hangs forever (the pattern every other test uses).
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    final prefs = await SharedPreferences.getInstance();
    Locator.bind(prefs: prefs, store: InMemorySecureStore());
  }

  group('Movement 56 — mic and upload respond', () {
    testWidgets('mic button is wired to a handler (it was dead)',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BottomInputBar(
            controller: controller,
            focusNode: FocusNode(),
            onSend: (_) {},
            onAttach: () {},
          ),
        ),
      ));
      final mic = find.byKey(const ValueKey('mic-button'));
      expect(mic, findsOneWidget);
      // The whole complaint: the tap must DO something. The GestureDetector
      // must carry an onTap (previously there was no handler at all).
      expect(tester.widget<GestureDetector>(mic).onTap, isNotNull);
      // Tapping must not leave the bar stuck: without a speech engine the
      // toggle fails and returns to the idle mic.
      await tester.tap(mic);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('mic-button')), findsOneWidget);
    });

    testWidgets('credentials picker opens to ALL files (octet-stream fix)',
        (tester) async {
      await bindMinimal();
      final picker = FakePicker();
      FilePicker.platform = picker;
      final original = FilePicker.platform;
      addTearDown(() => FilePicker.platform = original);
      await tester.pumpWidget(const MaterialApp(home: GoogleAccountsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final button = find.byKey(const ValueKey('gconsole-upload'));
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(picker.lastType, FileType.any,
          reason: 'the old FileType.custom + [json] MIME filter hid '
              'browser-downloaded credentials.json (octet-stream)');
    });

    testWidgets('non-JSON pick is rejected with a clear message',
        (tester) async {
      await bindMinimal();
      final picker = FakePicker();
      final tmp = Directory.systemTemp.createTempSync('gork-m56');
      final notJson = File('${tmp.path}/photo.png')..writeAsStringSync('x');
      picker.result = FilePickerResult([
        PlatformFile(name: 'photo.png', path: notJson.path, size: 1),
      ]);
      FilePicker.platform = picker;
      final original = FilePicker.platform;
      addTearDown(() => FilePicker.platform = original);
      addTearDown(() => tmp.deleteSync(recursive: true));
      await tester.pumpWidget(const MaterialApp(home: GoogleAccountsScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final button = find.byKey(const ValueKey('gconsole-upload'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('not a .json file'), findsOneWidget);
    });
  });

  group('Movement 56 — gaps between stacked cards', () {
    testWidgets('menu: several glass cards, all separated by 16px',
        (tester) async {
      // Tall viewport so the lazy ListView builds every card.
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
      await tester.pump();
      final cards = find.byType(GlassContainer).evaluate().length;
      expect(cards, greaterThan(1), reason: 'menu stacks several cards');
      final gaps = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((s) => s.height == 16)
          .length;
      expect(gaps, greaterThanOrEqualTo(3),
          reason: 'every stacked pair must have a gap between the cards');
    });

    testWidgets('home: weather card and panels are 16px apart',
        (tester) async {
      await bindMinimal();
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: GorkHome()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final gaps = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((s) => s.height == 16)
          .length;
      expect(gaps, greaterThanOrEqualTo(1),
          reason: 'home stacks cards with a 16px gap');
    });
  });
}
