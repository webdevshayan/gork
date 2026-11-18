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
    final gap = children[buttonIdx + 1];
    expect(gap, isA<SizedBox>(),
        reason: 'something must separate the pill from the next card');
    expect((gap as SizedBox).height, 16);
    expect(children[buttonIdx + 2], isA<GlassContainer>(),
        reason: 'the Cloud Console card is what follows');
  });

  testWidgets('a refused upload names the one-command fix (gork daemon '
      'update) and says what is kept', (tester) async {
    await _bind();
    await tester.pumpWidget(MaterialApp(
        home: GoogleAccountsScreen(
            store: _EmptyStore(), uploader: _RefusingUploader())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final upload = find.byKey(const ValueKey('gconsole-upload'));
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
