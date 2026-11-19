import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/google_accounts_screen.dart';
import 'package:gork/services/credential_uploader.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 49 — Cloud Console credentials go to the VPS vault once, sealed,
/// never read back. The app validates, uploads, and shows a status boolean.
void main() {
  late Directory tmp;
  late List<String> bodies;
  late Map<String, String> headersSeen;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gork-m49');
    bodies = [];
    headersSeen = {};
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  GoogleCredentialsUploader uploaderFor() => GoogleCredentialsUploader(
        client: MockClient((request) async {
          headersSeen.addAll(request.headers);
          if (request.method == 'POST' &&
              request.url.path == '/v1/credentials/google') {
            bodies.add(request.body);
            return http.Response(
                jsonEncode({'stored': true, 'sealed_with': 'fernet'}), 201);
          }
          if (request.method == 'GET' &&
              request.url.path == '/v1/credentials/google/status') {
            return http.Response(
                jsonEncode({
                  'has_client_json': bodies.isNotEmpty,
                  'scopes_expected': ['gmail.send'],
                }),
                200);
          }
          return http.Response('nope', 404);
        }),
        store: InMemorySecureStore()..write('vps.token', 'vps-secret'),
      );

  File writeCreds(Map<String, dynamic> json) {
    final f = File('${tmp.path}/credentials.json')..writeAsStringSync(jsonEncode(json));
    return f;
  }

  Future<void> bindVps() async {
    final prefs = await SharedPreferences.getInstance();
    Locator.bind(prefs: prefs, store: InMemorySecureStore());
    await prefs.setString('vps.url', 'http://vps.test');
  }

  test('a valid OAuth client JSON uploads with the shared secret', () async {
    await bindVps();
    final uploader = uploaderFor();
    final file = writeCreds({
      'installed': {
        'client_id': 'abc.apps.googleusercontent.com',
        'client_secret': 'GOCSPX-supersecret',
        'redirect_uris': ['urn:ietf:wgc:oauth:2.0:oob'],
      }
    });

    await uploader.upload(file.path);

    expect(bodies, hasLength(1));
    final sent = jsonDecode(bodies.first) as Map<String, dynamic>;
    expect((sent['client_json'] as Map)['installed']['client_secret'],
        'GOCSPX-supersecret',
        reason: 'the full object travels (the VPS seals it)');
    expect(headersSeen['X-Gork-Secret'], 'vps-secret');
    expect(headersSeen['Authorization'], isNull);
    expect(await uploader.hasCredentials(), isTrue);
  });

  test('a service-account JSON is accepted too', () async {
    await bindVps();
    final uploader = uploaderFor();
    final file = writeCreds({
      'type': 'service_account',
      'private_key': '-----BEGIN PRIVATE KEY-----',
      'client_email': 'bot@project.iam.gserviceaccount.com',
    });
    await uploader.upload(file.path);
    expect(bodies, hasLength(1));
  });

  test('junk files are rejected client-side with a helpful message', () async {
    await bindVps();
    final uploader = uploaderFor();
    final f1 = File('${tmp.path}/notes.txt')..writeAsStringSync('not json');
    expect(() => uploader.upload(f1.path), throwsArgumentError);
    final f2 = File('${tmp.path}/random.json')
      ..writeAsStringSync(jsonEncode({'hello': 'world'}));
    expect(() => uploader.upload(f2.path), throwsArgumentError);
    expect(bodies, isEmpty, reason: 'nothing invalid reaches the VPS');
  });

  testWidgets('the Google screen shows the upload flow and status',
      (tester) async {
    await bindVps();
    final uploader = uploaderFor();
    // Inject the uploader via a patched platform file picker.
    FilePicker.platform = _FakeFilePicker(writeCreds({
      'installed': {'client_id': 'abc', 'client_secret': 'GOCSPX-x'}
    }).path);
    // Build the screen with the recorded fake uploader — the default one
    // would dial the fake vps.test address with a real socket.
    await tester.pumpWidget(
        MaterialApp(home: GoogleAccountsScreen(uploader: uploader)));
    await tester.pumpAndSettle();

    // Movement 64 — the guide card grew; scroll the upload button into
    // the lazy viewport first.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('gconsole-upload')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gconsole-upload')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gconsole-upload')));
    await tester.pumpAndSettle();

    final status = tester.widget<Text>(
        find.byKey(const ValueKey('gconsole-status')));
    expect(status.data, contains('sealed on the VPS'),
        reason: 'the outcome is honest and mentions the vault');
  });
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.path);
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
      PlatformFile(name: 'credentials.json', size: 100, path: path),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
