import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/screens/chat_screen.dart';
import 'package:gork/screens/hark_shell.dart';
import 'package:gork/screens/projects_screen.dart';
import 'package:gork/screens/search_screen.dart';
import 'package:gork/services/history_store.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/projects_store.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/widgets/ambient_backdrop.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 43 — separate screens + a scoped search system.
///
/// The top-left button is a SEARCH button on every tab (scope follows the
/// tab); the search overlay slides up from the bottom; a chat inside a
/// project opens as its own pushed full-screen route (never collapses back
/// into the shell's Chat tab).
void main() {
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

  group('Movement 43 — top-left is search, everywhere', () {
    testWidgets('the shell left button is a search icon on all tabs',
        (tester) async {
      await pumpShell(tester);

      IconData leftIcon() => tester
          .widget<Icon>(find.descendant(
            of: find.byKey(const ValueKey('left-button')),
            matching: find.byType(Icon),
          ))
          .icon!;

      expect(leftIcon(), Icons.search,
          reason: 'home: the top-left button is search');
      await openTab(tester, 'chat');
      expect(leftIcon(), Icons.search, reason: 'chat: still search');
      await openTab(tester, 'projects');
      expect(leftIcon(), Icons.search, reason: 'projects: still search');
    });

    testWidgets('tapping it opens the search overlay', (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byKey(const ValueKey('left-button')));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('the scope follows the entry tab', (tester) async {
      await pumpShell(tester);
      final now = DateTime.now().millisecondsSinceEpoch;
      await Locator.history.save(Conversation(
        id: 'active1',
        title: 'Active thread',
        providerId: 'openai',
        updatedAt: now,
        messages: [ChatTurn('user', 'hello', time: now)],
      ));

      // From home: everything.
      await tester.tap(find.byKey(const ValueKey('left-button')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SearchScreen>(find.byType(SearchScreen)).initialScope,
        SearchScope.all,
      );
      // Close via the overlay's glass chevron (no Material page back bar).
      await tester.tap(find.descendant(
        of: find.byType(SearchScreen),
        matching: find.byIcon(Icons.arrow_back_ios_new),
      ));
      await tester.pumpAndSettle();

      // From the chat tab: the active conversation.
      await openTab(tester, 'chat');
      await tester.tap(find.byKey(const ValueKey('left-button')));
      await tester.pumpAndSettle();
      final fromChat =
          tester.widget<SearchScreen>(find.byType(SearchScreen));
      expect(fromChat.initialScope, SearchScope.chat);
      expect(fromChat.conversationId, isNotNull,
          reason: 'the chat tab searches the active conversation');
      await tester.tap(find.descendant(
        of: find.byType(SearchScreen),
        matching: find.byIcon(Icons.arrow_back_ios_new),
      ));
      await tester.pumpAndSettle();

      // From projects: projects only.
      await openTab(tester, 'projects');
      await tester.tap(find.byKey(const ValueKey('left-button')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SearchScreen>(find.byType(SearchScreen)).initialScope,
        SearchScope.projects,
      );
    });
  });

  group('Movement 43 — project chats are their own screens', () {
    testWidgets('a chat inside a project pushes a full-screen route',
        (tester) async {
      await pumpShell(tester);
      final now = DateTime.now().millisecondsSinceEpoch;
      await Locator.history.save(Conversation(
        id: 'pc1',
        title: 'Flight plans',
        providerId: 'openai',
        updatedAt: now,
        messages: [ChatTurn('user', 'book the trip', time: now)],
      ));
      await Locator.projects.save(Project(
        id: 'proj9',
        title: 'Trips',
        notes: '',
        files: const [],
        createdAt: now,
        updatedAt: now,
        chats: [ProjectChat('pc1', 'Flight plans', now)],
      ));

      await openTab(tester, 'projects');
      await tester.tap(find.byKey(const ValueKey('folder-proj9')));
      await tester.pumpAndSettle();
      expect(find.byType(ProjectDetailScreen), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('open-chat-pc1')));
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget,
          reason: 'the project chat is its own screen');
      expect(
          find.byType(ProjectDetailScreen, skipOffstage: false),
          findsOneWidget,
          reason: 'pushed on top of the workspace — NOT collapsed into the '
              'shell chat tab');
      expect(find.text('Flight plans'), findsWidgets,
          reason: 'the pushed chat screen carries the thread title');
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget,
          reason: 'a chevron back control returns to the workspace');
    });
  });

  group('Movement 43 — overlay motion and backdrop safety', () {
    testWidgets('the search overlay slides up from the bottom',
        (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byKey(const ValueKey('left-button')));
      // First pump installs the route (controller at 0 — fully below), the
      // second advances it: mid-transition the overlay is still rising.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final Finder overlay = find.byType(SearchScreen, skipOffstage: false);
      expect(overlay, findsOneWidget,
          reason: 'the overlay route exists mid-transition');
      final double dy = tester.getTopLeft(overlay).dy;
      expect(dy, greaterThan(8),
          reason: 'the overlay animates from the bottom of the screen');
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(SearchScreen)).dy, 0);
    });

    testWidgets('the backdrop image layers are repaint-isolated',
        (tester) async {
      await pumpShell(tester);
      // Holding an overscroll repaints glass BackdropFilters; the backdrop's
      // image layers must sit inside RepaintBoundaries so the blur never
      // collapses mid-scroll.
      expect(
        find.descendant(
          of: find.byType(AmbientBackdrop),
          matching: find.byType(RepaintBoundary),
        ),
        findsAtLeastNWidgets(1),
      );
    });
  });
}
