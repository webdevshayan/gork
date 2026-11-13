import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/screens/search_screen.dart';
import 'package:gork/services/history_store.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 29 — the menu Search pill opens a real chat search: hits across
/// conversations, an honest empty state, and a tap that opens the thread.

class _BlockedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient();
}

class _BlockedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in widget tests');
}

Future<Conversation> _conv(String id, String title, List<String> lines) async {
  return Conversation(
    id: id,
    title: title,
    providerId: 'none',
    updatedAt: DateTime(2026, 11, 10).millisecondsSinceEpoch,
    messages: [
      for (final line in lines)
        ChatTurn('user', line,
            time: DateTime(2026, 10, 27).millisecondsSinceEpoch),
    ],
  );
}

void main() {
  setUpAll(() => HttpOverrides.global = _BlockedOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  /// Lazy ListViews only build what is near the viewport — drag until the
  /// target exists.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 8 && target.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> bindServices() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Locator.reset();
    Locator.bind(prefs: prefs, store: InMemorySecureStore());
    await Locator.history.save(await _conv(
      'conv-1',
      'Taleem ERP: where it stands',
      ['Please check the ZIP file and recreate the demo video.'],
    ));
    await Locator.history.save(await _conv(
      'conv-2',
      'Groceries',
      ['milk, eggs, spinach'],
    ));
  }

  testWidgets('empty query shows Jump to + recent chats', (tester) async {
    await bindServices();
    await tester.pumpWidget(MaterialApp(
      home: SearchScreen(onOpenChat: (_) {}),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('search-field')), findsOneWidget);
    expect(find.text('Jump to'), findsOneWidget);
    // The recents sit below the jump rows — scroll them into view.
    await scrollTo(tester, find.text('Taleem ERP: where it stands'));
    expect(find.text('Taleem ERP: where it stands'), findsOneWidget);
    await scrollTo(tester, find.text('Groceries'));
    expect(find.text('Groceries'), findsOneWidget);
  });

  testWidgets('a query shows hits and opens the conversation', (tester) async {
    await bindServices();
    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: SearchScreen(onOpenChat: (id) => opened = id),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
        find.byKey(const ValueKey('search-field')), 'zip');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The hit card carries the conversation title and the matched snippet.
    expect(find.text('Taleem ERP: where it stands'), findsOneWidget);
    expect(find.textContaining('ZIP'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);

    await tester.tap(find.text('Taleem ERP: where it stands'));
    await tester.pump();
    expect(opened, 'conv-1');
  });

  testWidgets('no hits keeps it honest', (tester) async {
    await bindServices();
    await tester.pumpWidget(MaterialApp(
      home: SearchScreen(onOpenChat: (_) {}),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
        find.byKey(const ValueKey('search-field')), 'qqqq');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('No results'), findsOneWidget);
  });

  testWidgets('the menu Search pill opens the search surface and opens chats',
      (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore()..write('apikey.openai', 'sk-test'),
      httpClient: MockClient((request) async => http.Response('offline', 500)),
    );
    await Locator.history.save(await _conv(
      'conv-9',
      'Budget review',
      ['The numbers checked out.'],
    ));
    await tester.pumpWidget(const GorkApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Avatar → menu → Search pill (the row sits low in the menu list).
    await tester.tap(find.byKey(const ValueKey('avatar')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await scrollTo(tester, find.byKey(const ValueKey('menu-search')));
    await tester.tap(find.byKey(const ValueKey('menu-search')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SearchScreen), findsOneWidget);

    // A recent chat opens the thread in the shell's Chat tab.
    await scrollTo(tester, find.text('Budget review'));
    await tester.tap(find.text('Budget review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('The numbers checked out.'), findsOneWidget);
  });
}
