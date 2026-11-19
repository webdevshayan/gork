import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/google_accounts_screen.dart';
import 'package:gork/services/google_accounts.dart';
import 'package:gork/services/credential_uploader.dart';
import 'package:gork/services/integrations.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/widgets/g_button.dart';
import 'package:gork/widgets/glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 61 — "update without losing anything":
///
///   1. the Google screen gap: the Add account pill used to sit DIRECTLY on
///      the Cloud Console card (screenshot 2026-11-18) — two surfaces
///      touching read as one broken card. Locked: the list has the 16px
///      SizedBox between them, exactly like every other stacked pair.
///   2. a refused upload (an old daemon 404s the credentials endpoint) must
///      name the ONE command that fixes it — `gork daemon update` — and say
///      what is kept, instead of "make sure the daemon is up to date".
///
/// The daemon side of this movement (version on /health, the credentials
/// endpoints, the self-updater) is covered in daemon/test/.
class _EmptyStore extends GoogleAccountStore {
  _EmptyStore()
      : super(
          store: InMemorySecureStore(),
          verifier: (_) async => 'unused@example.com',
          vault: IntegrationVault(InMemorySecureStore()),
        );

  @override
  Future<List<GoogleAccount>> accounts() async => const <GoogleAccount>[];

  @override
  Future<GoogleAccount?> active() async => null;
}

class _NoVpsUploader extends GoogleCredentialsUploader {
  @override
  bool get configured => false;

  @override
  Future<bool> hasCredentials() async => false;
}

class _RefusingUploader extends GoogleCredentialsUploader {
  @override
  bool get configured => true;

  @override
  Future<bool> hasCredentials() async => false;

  @override
  Future<void> upload(String path) async {
    // What an OLD daemon (pre Movement 61) answers: 404 on the credentials
    // endpoint → the uploader throws this exact StateError.
    throw StateError('the VPS refused the upload (HTTP 404)');
  }
}

/// The picker must answer in the test VM or the flow never reaches upload().
class _FakePicker extends FilePicker {
  _FakePicker(this.path);
  final String path;

  @override
  Future<FilePickerResult?> pickFiles(
      {String? dialogTitle,
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
      bool readSequential = false}) async {
    return FilePickerResult([
      PlatformFile(name: 'credentials.json', size: 10, path: path),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _bind() async {
  SharedPreferences.setMockInitialValues({'onboarding.done': true});
  Locator.reset();
  final prefs = await SharedPreferences.getInstance();
  Locator.bind(prefs: prefs, store: InMemorySecureStore());
}

void main() {
  testWidgets('the Add account pill and the Cloud Console card keep the '
      '16px gap (the touching-cards bug)', (tester) async {
    await _bind();
    await tester.pumpWidget(MaterialApp(
        home: GoogleAccountsScreen(
            store: _EmptyStore(), uploader: _NoVpsUploader())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final children =
        (tester.widget<ListView>(find.byType(ListView)).childrenDelegate
                as SliverChildListDelegate)
            .children;
    final buttonIdx = children
        .indexWhere((w) => w.key == const ValueKey('google-add'));
    expect(buttonIdx, greaterThan(0), reason: 'the Add account pill renders');
    // Movement 64 — the Cloud Console guide sits ABOVE Connect now, and
    // every stacked pair keeps the 16px gap: card → Connect → Add → footer.
    final gapAbove = children[buttonIdx - 1];
    expect(gapAbove, isA<SizedBox>(),
        reason: 'something must separate the pill from Connect');
    expect((gapAbove as SizedBox).height, 16);
    expect(children[buttonIdx - 2], isA<GButton>(),
        reason: 'Connect with Google sits right above the pill');
    expect(children[buttonIdx - 3], isA<SizedBox>());
    expect((children[buttonIdx - 3] as SizedBox).height, 16);
    expect(children[buttonIdx - 4], isA<GlassContainer>(),
        reason: 'the Cloud Console card is what precedes Connect');
  });

  testWidgets('a refused upload names the one-command fix (gork daemon '
      'update) and says what is kept', (tester) async {
    await _bind();
    final creds = File('${Directory.systemTemp.path}/m61-creds.json')
      ..writeAsStringSync('{"installed": {"client_id": "abc"}}');
    addTearDown(() => creds.deleteSync());
    // Same precedent as movement_49: ASSIGN the picker, never read the
    // late `platform` field first (it crashes in the test VM).
    FilePicker.platform = _FakePicker(creds.path);
    await tester.pumpWidget(MaterialApp(
        home: GoogleAccountsScreen(
            store: _EmptyStore(), uploader: _RefusingUploader())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final upload = find.byKey(const ValueKey('gconsole-upload'));
    await tester.scrollUntilVisible(
      upload,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(upload, findsOneWidget);
    await tester.ensureVisible(upload);
    await tester.tap(upload);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final snack = find.textContaining('gork daemon update');
    expect(snack, findsOneWidget,
        reason: 'the user must see the exact command that fixes it');
    final text = tester.widget<Text>(snack).data ?? '';
    expect(text, contains('keys'),
        reason: 'and that nothing needs re-setup');
  });
}
