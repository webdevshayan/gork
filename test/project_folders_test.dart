import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/screens/projects_screen.dart';
import 'package:gork/services/history_store.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/projects_store.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BlockedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient();
}

class _BlockedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in widget tests');
}

void main() {
  setUpAll(() => HttpOverrides.global = _BlockedOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  Future<void> pumpShell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore()..write('apikey.openai', 'sk-test'),
      httpClient: MockClient((request) async => http.Response('offline', 500)),
    );
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey('tab-$tab')));
    await tester.pumpAndSettle();
  }

  test('project store keeps chats + images (and loads legacy JSON)', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final project = Project(
      id: 'p1',
      title: 'School Project',
      notes: 'bio notes',
      files: const [ProjectFile('outline.md', '# Outline')],
      images: const [ProjectImage('photo.jpg', '/tmp/photo.jpg')],
      chats: const [ProjectChat('c1', 'First chat', 123)],
      createdAt: now,
      updatedAt: now,
    );
    final restored = Project.fromJson(project.toJson());
    expect(restored.chats.length, 1);
    expect(restored.chats.first.id, 'c1');
    expect(restored.images.first.path, '/tmp/photo.jpg');
    expect(restored.files.first.name, 'outline.md');

    // Legacy JSON (before chats/images existed) still loads.
    final legacy = Project.fromJson({
      'id': 'p2',
      'title': 'Old',
      'notes': '',
      'files': [],
      'createdAt': now,
      'updatedAt': now,
    });
    expect(legacy.chats, isEmpty);
    expect(legacy.images, isEmpty);
  });

  testWidgets('projects are folders: list -> detail -> new chat -> chat tab',
      (tester) async {
    await pumpShell(tester);

    final now = DateTime.now().millisecondsSinceEpoch;
    await Locator.projects.save(Project(
      id: 'proj1',
      title: 'School Project',
      notes: 'everything for school',
      files: const [],
      createdAt: now,
      updatedAt: now,
    ));

    await openTab(tester, 'projects');
    expect(find.byKey(const ValueKey('projects-folder-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('folder-proj1')), findsOneWidget);
    expect(find.textContaining('0 chats'), findsOneWidget);

    // Open the folder -> detail with chats section.
    await tester.tap(find.byKey(const ValueKey('folder-proj1')));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('No chats in this folder yet.'), findsOneWidget);

    // New chat -> shell switches to the Chat tab with the new conversation.
    await tester.tap(find.byKey(const ValueKey('new-project-chat')));
    await tester.pumpAndSettle();
    expect(find.text("Hey Shayan, I'm gork.", findRichText: true), findsOneWidget,
        reason: 'the chat tab opened an empty project chat');

    // The message lands in the PROJECT chat, not the global latest.
    await tester.enterText(find.byKey(const ValueKey('input-bar')), 'hi there');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('send-circle')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final stored = Locator.projects.byId('proj1')!.chats;
    expect(stored.length, 1);
    final conversation = Locator.history.byId(stored.first.id);
    expect(conversation, isNotNull);
    expect(conversation!.messages.first.content, 'hi there');
    expect(conversation.messages.first.role, 'user');
  });

  testWidgets('opening an existing project chat restores its own thread', (
    tester,
  ) async {
    await pumpShell(tester);

    final now = DateTime.now().millisecondsSinceEpoch;
    await Locator.history.save(Conversation(
      id: 'projchat-1',
      title: 'Essay draft',
      providerId: 'openai',
      updatedAt: now,
      messages: [
        ChatTurn('user', 'help me outline my essay', time: now),
        ChatTurn('assistant', 'Sure — here is an outline.', time: now),
      ],
    ));
    await Locator.projects.save(Project(
      id: 'proj2',
      title: 'Writing',
      notes: '',
      files: const [],
      chats: [ProjectChat('projchat-1', 'Essay draft', now)],
      createdAt: now,
      updatedAt: now,
    ));

    await openTab(tester, 'projects');
    await tester.tap(find.byKey(const ValueKey('folder-proj2')));
    await tester.pumpAndSettle();
    expect(find.text('Essay draft'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-chat-projchat-1')));
    await tester.pumpAndSettle();
    expect(find.text('help me outline my essay'), findsOneWidget);
    expect(find.text('Sure — here is an outline.', findRichText: true), findsOneWidget);
    // And the global latest thread did NOT leak in.
    expect(find.text("Hey Shayan, I'm gork.", findRichText: true), findsNothing);
  });

  testWidgets('workspace detail has its own back affordance', (tester) async {
    await pumpShell(tester);

    final now = DateTime.now().millisecondsSinceEpoch;
    await Locator.projects.save(Project(
      id: 'proj3',
      title: 'Trips',
      notes: '',
      files: const [],
      createdAt: now,
      updatedAt: now,
    ));

    await openTab(tester, 'projects');
    await tester.tap(find.byKey(const ValueKey('folder-proj3')));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    // The pushed detail carries its own back control (the shell's back
    // button sits under the opaque route).
    expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget,
        reason: 'the detail screen back control is a chevron');
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectDetailScreen), findsNothing);
    expect(find.byKey(const ValueKey('projects-folder-list')), findsOneWidget);
  });
}
