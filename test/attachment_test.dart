import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/screens/chat_screen.dart';
import 'package:gork/services/history_store.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/projects_store.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 27 — the + menu is real: Camera / Photos / Files pick content,
/// the attachment lands in the conversation as a bubble, and a project chat
/// mirrors it into its folder (projects host resources at the project level).

class _BlockedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient();
}

class _BlockedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in widget tests');
}

/// A 1x1 transparent PNG, so Image.file really decodes in tests.
const String _pngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

/// Sync IO — real async IO inside the test's FakeAsync zone can stall.
File _tempPng() {
  final dir = Directory.systemTemp.createTempSync('gork-test');
  final file = File('${dir.path}/shot.png');
  file.writeAsBytesSync(base64Decode(_pngB64));
  return file;
}

File _tempText() {
  final dir = Directory.systemTemp.createTempSync('gork-test');
  final file = File('${dir.path}/notes.md');
  file.writeAsStringSync('# Plan\n\nship it');
  return file;
}

/// pumpAndSettle spins forever when something keeps scheduling frames; two
/// explicit pumps (rebuild + animations) are deterministic instead.
Future<void> pumpThrough(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
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

void main() {
  setUpAll(() => HttpOverrides.global = _BlockedOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  // ---- store level -----------------------------------------------------------

  test('ChatTurn round-trips an attachment', () {
    const turn = ChatTurn(
      'user',
      '',
      time: 42,
      attachment: ChatAttachment('image', '/tmp/shot.png', 'shot.png'),
    );
    final restored = ChatTurn.fromJson(turn.toJson());
    expect(restored.attachment, isNotNull);
    expect(restored.attachment!.kind, 'image');
    expect(restored.attachment!.path, '/tmp/shot.png');
    expect(restored.attachment!.name, 'shot.png');
  });

  test('legacy turns without attachments still parse', () {
    final turn = ChatTurn.fromJson({'role': 'user', 'content': 'hi'});
    expect(turn.attachment, isNull);
  });

  test('projectOfChat maps a conversation to its folder', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Locator.reset();
    Locator.bind(prefs: prefs, store: InMemorySecureStore());
    final store = Locator.projects;
    await store.save(Project(
      id: 'p1',
      title: 'Taleem ERP',
      notes: '',
      chats: [ProjectChat('conv-9', 'audit', 1)],
      files: [],
      images: [],
      createdAt: 1,
      updatedAt: 1,
    ));
    expect(store.projectOfChat('conv-9')?.id, 'p1');
    expect(store.projectOfChat('missing'), isNull);
  });

  // ---- chat screen level -------------------------------------------------------

  testWidgets('attachImage lands an image bubble in the thread',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
    );
    final png = _tempPng();
    final key = GlobalKey<ChatScreenState>();
    await tester.pumpWidget(MaterialApp(home: ChatScreen(key: key)));
    await pumpThrough(tester);

    await key.currentState!.attachImage(png.path, name: 'shot.png');
    await pumpThrough(tester);

    expect(find.byKey(const ValueKey('attachment-image')), findsOneWidget);
    // The attachment persists with the conversation.
    final saved = Locator.history.latest!;
    expect(saved.messages.last.attachment, isNotNull);
    expect(saved.messages.last.attachment!.name, 'shot.png');
  });

  testWidgets('a broken image shows the reference Error panel', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
    );
    final key = GlobalKey<ChatScreenState>();
    await tester.pumpWidget(MaterialApp(home: ChatScreen(key: key)));
    await pumpThrough(tester);

    await key.currentState!.attachImage('/nonexistent/shot.png', name: 'x.png');
    await pumpThrough(tester);
    // The decode failure arrives through the real event loop — step outside
    // FakeAsync briefly so the error can land, then pump again.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await pumpThrough(tester);

    expect(find.byKey(const ValueKey('attachment-error')), findsOneWidget);
  });

  testWidgets('attachFile lands a file card that previews its content',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
    );
    final text = _tempText();
    final key = GlobalKey<ChatScreenState>();
    await tester.pumpWidget(MaterialApp(home: ChatScreen(key: key)));
    await pumpThrough(tester);

    await key.currentState!.attachFile(text.path, 'notes.md');
    await pumpThrough(tester);

    expect(find.byKey(const ValueKey('attachment-file')), findsOneWidget);
    expect(find.text('notes.md'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('attachment-file')));
    await pumpThrough(tester);
    expect(find.byKey(const ValueKey('file-preview')), findsOneWidget);
    expect(find.text('# Plan\n\nship it'), findsOneWidget);
  });

  testWidgets('attachments in a project chat mirror into the folder',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Locator.reset();
    Locator.bind(prefs: prefs, store: InMemorySecureStore());
    await Locator.projects.save(Project(
      id: 'p2',
      title: 'Demo',
      notes: '',
      chats: [ProjectChat('conv-a', 'New chat', 1)],
      files: [],
      images: [],
      createdAt: 1,
      updatedAt: 1,
    ));
    final png = _tempPng();
    final key = GlobalKey<ChatScreenState>();
    await tester.pumpWidget(MaterialApp(
      home: ChatScreen(key: key, conversationId: 'conv-a'),
    ));
    await pumpThrough(tester);

    await key.currentState!.attachImage(png.path, name: 'shot.png');
    await pumpThrough(tester);

    final project = Locator.projects.byId('p2')!;
    expect(project.images.length, 1);
    expect(project.images.first.path, png.path);
    // The file variant mirrors into files.
    final text = _tempText();
    await key.currentState!.attachFile(text.path, 'notes.md');
    await pumpThrough(tester);
    expect(Locator.projects.byId('p2')!.files.length, 1);
    expect(Locator.projects.byId('p2')!.files.first.name, 'notes.md');
  });

  // ---- shell level -------------------------------------------------------------

  testWidgets('the + menu opens Camera / Photos / Files and Photos attaches',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore()..write('apikey.openai', 'sk-test'),
      httpClient: MockClient((request) async => http.Response('offline', 500)),
    );

    // Mock the picker platform itself (channel mocks lose their type
    // through the codec and break image_picker's casts).
    final png = _tempPng();
    ImagePickerPlatform.instance = _MockPickerPlatform(png);

    await tester.pumpWidget(const GorkApp());
    await pumpThrough(tester);

    await tester.tap(find.byKey(const ValueKey('attach-button')));
    await pumpThrough(tester);
    expect(find.byKey(const ValueKey('attach-menu')), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);

    await tester.tap(find.text('Photos'));
    await pumpThrough(tester);

    // The attachment bubble is on the chat surface now.
    expect(find.byKey(const ValueKey('attachment-image')), findsOneWidget);
  });
}
