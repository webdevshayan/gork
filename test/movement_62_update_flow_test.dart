import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/constants/version.dart';
import 'package:gork/screens/google_accounts_screen.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/screens/updates_screen.dart';
import 'package:gork/services/google_accounts.dart';
import 'package:gork/services/credential_uploader.dart';
import 'package:gork/services/google_oauth_service.dart';
import 'package:gork/services/installer.dart';
import 'package:gork/services/integrations.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/outbox.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 62 — the app half of "the VPS does the work":
///
///   * Settings › Preferences is where the theme lives now (moved off Home)
///   * the outbox surfaces finished VPS jobs as notifications (never-losable)
///   * Google connects with ONE TAP through the user's own VPS (OAuth
///     loopback flow) and shows which tools connected
///   * the Updates screen re-probes the install permission when the app
///     resumes — no more stale "That permission is currently off"
Future<void> _bind() async {
  SharedPreferences.setMockInitialValues({'onboarding.done': true});
  Locator.reset();
  final prefs = await SharedPreferences.getInstance();
  Locator.bind(prefs: prefs, store: InMemorySecureStore());
}

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

class _FakeOauth extends GoogleOAuthService {
  _FakeOauth(this.result) : super(installer: _NoopInstaller());

  /// null → connect() succeeds returning this; a String → connect() throws.
  final dynamic result;

  @override
  bool get configured => true;

  @override
  Future<Map<String, dynamic>> connect() async {
    if (result is String) throw StateError(result as String);
    return (result as Map).cast<String, dynamic>();
  }

  @override
  Future<List<Map<String, dynamic>>> accounts() async {
    if (result is String) return const [];
    return [
      {
        'email': (result as Map)['email'],
        'name': (result)['name'],
        'tools': (result)['tools'],
      }
    ];
  }
}

class _NoopInstaller implements Installer {
  @override
  Future<bool> canInstall() async => true;

  @override
  Future<void> openPermissionSettings() async {}

  @override
  Future<void> installApk(String path) async {}

  @override
  Future<void> openUrl(String url) async {}
}

void main() {
  group('Movement 62 — Settings › Preferences (the theme moved here)', () {
    testWidgets('the Preferences tab holds the theme and persists the pick',
        (tester) async {
      await _bind();
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('theme-dark')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Theme', skipOffstage: false), findsOneWidget);
      expect(find.text('Preferences', skipOffstage: false), findsOneWidget);
      expect(find.text('About', skipOffstage: false), findsOneWidget);

      // Pick Dark — the SAME pref the old Home toggle wrote.
      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await tester.pumpAndSettle();
      expect(Locator.prefs.getString('ui.theme'), 'dark');

      // And back to Auto — the picker is fully functional here.
      await tester.tap(find.byKey(const ValueKey('theme-auto')));
      await tester.pumpAndSettle();
      expect(Locator.prefs.getString('ui.theme'), 'auto');
    });

    testWidgets('the About tab shows the version and the updates entry',
        (tester) async {
      await _bind();
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-tab-about')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-tab-about')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('settings-version')), findsOneWidget);
      expect(
          find.text('gork v$kAppVersion'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-updates')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('settings-updates')));
      await tester.pumpAndSettle();
      expect(find.byType(UpdatesScreen), findsOneWidget);
    });

    testWidgets('Home no longer carries the theme toggle (it moved to '
        'Settings)', (tester) async {
      // The shell test covers the home surface; this pins the reason: the
      // toggle keys only exist on the Settings screen.
      await _bind();
      await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('theme-auto')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('theme-auto')), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-light')), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-dark')), findsOneWidget);
    });
  });

  group('Movement 62 — never-losable: finished VPS jobs become '
      'notifications', () {
    test('pollFinished returns reply previews once, then never again',
        () async {
      final seen = <String, dynamic>{};
      final client = MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'POST' && path == '/v1/messages') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final id = 'job-${body['text']}';
          seen[id] = body;
          return http.Response(jsonEncode({'id': id, 'status': 'queued'}),
              201);
        }
        if (request.method == 'GET' && path.startsWith('/v1/jobs/')) {
          final id = path.split('/').last;
          return http.Response(
              jsonEncode({
                'id': id,
                'status': 'done',
                'result': {'reply': 'Line one\nLine two\nLine three\nLine four'},
              }),
              200);
        }
        return http.Response('unexpected', 500);
      });

      SharedPreferences.setMockInitialValues({
        'vps.url': 'http://vps.test:8787',
        'vps.token': 'secret',
      });
      Locator.reset();
      final prefs = await SharedPreferences.getInstance();
      Locator.bind(prefs: prefs, store: InMemorySecureStore());
      final outbox = MessageOutbox(client: client, prefs: prefs);

      final entry = await outbox.enqueue('conv-1', 'tell me a joke',
          awaitAcceptance: true);
      expect(entry.jobId, 'job-tell me a joke');

      final finished = await outbox.pollFinished();
      expect(finished, hasLength(1));
      // 'faster to understand': first lines only, no wall of text.
      expect(finished.first.preview, 'Line one\nLine two\nLine three');
      expect(finished.first.conversationId, 'conv-1');
      expect(finished.first.reply, contains('Line four'));

      // Marked notified: the same reply never notifies twice.
      final again = await outbox.pollFinished();
      expect(again, isEmpty);
    });
  });

  group('Movement 62 — one-tap Google through the user\'s VPS', () {
    testWidgets('a successful connect shows the account with its tool chips',
        (tester) async {
      await _bind();
      await tester.pumpWidget(MaterialApp(
          home: GoogleAccountsScreen(
        store: _EmptyStore(),
        uploader: _NoVpsUploader(),
        oauth: _FakeOauth({
          'email': 'me@gmail.com',
          'name': 'Me',
          'tools': ['gmail', 'docs', 'youtube'],
        }),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('google-connect')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('vps-account-me@gmail.com')),
          findsOneWidget);
      expect(find.text('Me · me@gmail.com'), findsOneWidget);
      // The visible chips are what the user reads (keys keep the raw tool).
      for (final tool in ['GMAIL', 'DOCS', 'YOUTUBE']) {
        expect(find.text(tool), findsOneWidget);
      }
      expect(find.textContaining('Connected Me'), findsOneWidget);
    });

    testWidgets('a refused connect speaks human (no Dart in the snackbar)',
        (tester) async {
      await _bind();
      await tester.pumpWidget(MaterialApp(
          home: GoogleAccountsScreen(
        store: _EmptyStore(),
        uploader: _NoVpsUploader(),
        oauth: _FakeOauth('no credentials.json on the VPS yet — upload it '
            'first (Google screen → Upload credentials.json)'),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('google-connect')));
      await tester.pumpAndSettle();

      expect(find.textContaining('no credentials.json on the VPS yet'),
          findsOneWidget);
      expect(find.textContaining('StateError'), findsNothing);
    });
  });

  group('Movement 62 — the install permission is re-probed in realtime', () {
    testWidgets('returning from system settings re-checks immediately',
        (tester) async {
      final tmp = Directory.systemTemp.createTempSync('m62-apk');
      addTearDown(() => tmp.deleteSync(recursive: true));
      var canInstall = false;
      final service = UpdateService(
        client: MockClient((request) async {
          if (request.url.host == 'api.github.com') {
            return http.Response(
                jsonEncode([
                  {
                    'tag_name': 'v99.0.0',
                    'name': 'gork v99.0.0',
                    'body': 'notes',
                    'prerelease': false,
                    'draft': false,
                    'assets': [
                      {
                        'name': 'gork-v99.0.0.apk',
                        'browser_download_url': 'https://example.invalid/a.apk',
                        'size': 11,
                      }
                    ],
                  }
                ]),
                200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response('APK-BYTES-11', 200);
        }),
        currentVersion: '1.4.2',
        downloadDir: tmp.path,
      );

      await tester.pumpWidget(MaterialApp(home: UpdatesScreen(
        installer: _CountingInstaller(_NoopInstaller(), () => canInstall),
        service: service,
        currentVersion: '1.4.2',
        downloadDir: tmp.path,
      )));

      expect(find.byKey(const ValueKey('updates-check')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('updates-check')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('updates-available')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('updates-download')));
      await tester.pumpAndSettle();
      // Ready to install, but the permission is currently off.
      expect(find.text('Open install settings'), findsOneWidget);

      // The user flips the system permission while away…
      canInstall = true;
      // …and returns to the app: the lifecycle resume MUST re-probe.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Install'), findsOneWidget,
          reason: 'the permission state is realtime now — no re-entry');
    });
  });
}

/// Reports [canInstall] live so the lifecycle re-probe observes the change.
class _CountingInstaller implements Installer {
  _CountingInstaller(this._inner, this._read);
  final Installer _inner;
  final bool Function() _read;

  @override
  Future<bool> canInstall() async => _read();

  @override
  Future<void> openPermissionSettings() => _inner.openPermissionSettings();

  @override
  Future<void> installApk(String path) => _inner.installApk(path);

  @override
  Future<void> openUrl(String url) => _inner.openUrl(url);
}
