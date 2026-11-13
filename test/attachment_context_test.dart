import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/chat_screen.dart';
import 'package:gork/services/attachment_context.dart';
import 'package:gork/services/chat_service.dart';
import 'package:gork/services/history_store.dart';
import 'package:gork/services/llm_client.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 31 — attachments speak. A text file attached to the thread
/// feeds the agent its real content when the user sends a message;
/// binaries and images stay honest markers.

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('gork-ctx');
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File file(String name, List<int> bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(bytes);

  // ---- unit level -----------------------------------------------------------

  test('a text file speaks — content lands in the block', () {
    final p = file('notes.md', utf8.encode('# Plan\n\nship it'));
    final block =
        AttachmentContext.describe(ChatAttachment('file', p.path, 'notes.md'));
    expect(block, contains('[file attached: notes.md]'));
    expect(block, contains('# Plan'));
    expect(block, contains('ship it'));
  });

  test('binary bytes stay a bare marker', () {
    final p = file('blob.bin', [
      for (var i = 0; i < 10; i++) ...[0, 1, 2, 255],
    ]);
    final block =
        AttachmentContext.describe(ChatAttachment('file', p.path, 'blob.bin'));
    expect(block, '[file attached: blob.bin]');
  });

  test('a missing file says so honestly', () {
    final block = AttachmentContext.describe(
        ChatAttachment('file', '${dir.path}/gone.txt', 'gone.txt'));
    expect(block, '[file attached: gone.txt — content unavailable]');
  });

  test('oversized text truncates with a note', () {
    final p = file('big.txt', utf8.encode('a' * 9000));
    final block =
        AttachmentContext.describe(ChatAttachment('file', p.path, 'big.txt'));
    expect(block.length, lessThan(AttachmentContext.maxChars + 200));
    expect(block, contains('truncated'));
  });

  test('images stay presence markers (vision rides later)', () {
    final p = file('shot.png', [0x89, 0x50]);
    final block = AttachmentContext
        .describe(ChatAttachment('image', p.path, 'shot.png'));
    expect(block, '[image attached: shot.png]');
  });

  test('an empty file says empty', () {
    final p = file('empty.txt', const <int>[]);
    final block =
        AttachmentContext.describe(ChatAttachment('file', p.path, 'empty.txt'));
    expect(block, '[file attached: empty.txt — empty]');
  });

  // ---- integration level ------------------------------------------------------

  testWidgets(
      'sending after attaching puts the real file content in the model request',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = InMemorySecureStore();
    await store.write('apikey.openai', 'sk-test');
    final plan = file('plan.md', utf8.encode('# Plan\n\nship the zip demo'));
    final bodies = <String>[];
    final fakeHttp = MockClient((request) async {
      bodies.add(request.body);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'mock reply'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    Locator.reset();
    Locator.bind(
      prefs: prefs,
      store: store,
      chat: ChatService(
        vault: KeyVault(store),
        client: LlmClient(client: fakeHttp),
      ),
    );

    final chatKey = GlobalKey<ChatScreenState>();
    await tester.pumpWidget(MaterialApp(home: ChatScreen(key: chatKey)));
    await tester.pumpAndSettle();

    await chatKey.currentState!.attachFile(plan.path, 'plan.md');
    await tester.pumpAndSettle();
    await chatKey.currentState!.send('explain this file');
    await tester.pumpAndSettle();

    // The outbound request carries the file's actual content.
    expect(bodies, hasLength(1));
    expect(bodies.single, contains('# Plan'));
    expect(bodies.single, contains('ship the zip demo'));
    // The thread itself still shows the file card — not raw content.
    expect(find.byKey(const ValueKey('attachment-file')), findsOneWidget);
    expect(find.text('mock reply', findRichText: true), findsOneWidget);
  });
}
