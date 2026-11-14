import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/chat_screen.dart';
import 'package:gork/screens/projects_screen.dart';
import 'package:gork/services/history_store.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/projects_store.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/widgets/ambient_backdrop.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 46 — ONE Projects UI. The pushed Projects screen (search jumps,
/// menu) renders the SAME glass folder list as the tab surface, with the
/// same counts format, and wires project chats to full-screen routes.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(prefs: await SharedPreferences.getInstance(),
        store: InMemorySecureStore());
  });

  testWidgets('the pushed Projects screen shows the glass folder list',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await Locator.projects.save(Project(
      id: 'p1',
      title: 'Trips',
      notes: '',
      files: const [],
      createdAt: now,
      updatedAt: now,
      chats: [ProjectChat('c1', 'Flight plans', now)],
    ));

    await tester.pumpWidget(MaterialApp(home: ProjectsScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(AmbientBackdrop), findsOneWidget,
        reason: 'the pushed screen keeps the sky');
    expect(find.byKey(const ValueKey('projects-folder-list')), findsOneWidget,
        reason: 'the SAME folder list the tab surface renders');
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('1 chats · 0 files · 0 images'), findsOneWidget,
        reason: 'the folder card carries the workspace counts');
    expect(find.text('No projects yet. Tap + to create your first workspace.'),
        findsNothing,
        reason: 'the legacy GCard list is gone');
  });

  testWidgets('folders on the pushed screen open chats full-screen',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await Locator.history.save(Conversation(
      id: 'pc1',
      title: 'Flight plans',
      providerId: 'openai',
      updatedAt: now,
      messages: [ChatTurn('user', 'book the trip', time: now)],
    ));
    await Locator.projects.save(Project(
      id: 'p1',
      title: 'Trips',
      notes: '',
      files: const [],
      createdAt: now,
      updatedAt: now,
      chats: [ProjectChat('pc1', 'Flight plans', now)],
    ));

    await tester.pumpWidget(MaterialApp(home: ProjectsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('folder-p1')));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectDetailScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-chat-pc1')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget,
        reason: 'project chats open as their own screens from here too');
  });
}
