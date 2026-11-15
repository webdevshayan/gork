import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/app.dart';
import 'package:gork/constants/design_tokens.dart';
import 'package:gork/screens/chat_page.dart';
import 'package:gork/services/chat_service.dart';
import 'package:gork/services/history_store.dart';
import 'package:gork/services/llm_client.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/widgets/g_button.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 50 — screenshot-driven fixes:
///  1. the + in a SPECIFIC chat opens the attach dropdown first, never the
///     explorer directly (parity with the shell's + menu);
///  2. Wallet is gone everywhere (menu row, Security no longer opens it,
///     search jumps) — the feature is removed for now;
///  3. black & white only: no blue primary, buttons monochrome and pill
///     rounded; corners are never edgy (sm/md/lg/xl all >= 10/14/20/24).

class _BlockedOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedClient();
}

class _BlockedClient implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('network disabled in widget tests');
}

/// Fake picker platform that counts how many times the explorer/gallery was
/// actually invoked — the dropdown must gate it.
class _CountingPickerPlatform extends ImagePickerPlatform {
  int calls = 0;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    calls++;
    return null; // user cancels — no attachment lands, no network.
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _BlockedOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
    // The button test flips the static brightness — restore the shipped
    // dark-glass default so nothing downstream sees a stale value.
    GlassColors.brightness.value = Brightness.dark;
  });

  Future<void> pumpShell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    Locator.reset();
    final fakeHttp = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'choices': [
            {'message': {'content': 'mock reply'}},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore()..write('apikey.openai', 'sk-test'),
      chat: ChatService(
        vault: KeyVault(InMemorySecureStore()..write('apikey.openai', 'sk-test')),
        client: LlmClient(client: fakeHttp),
      ),
      httpClient: MockClient((request) async => http.Response('offline', 500)),
    );
    await tester.pumpWidget(const GorkApp());
    await tester.pumpAndSettle();
  }

  Future<void> seedThreads() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await Locator.history.save(Conversation(
      id: 'th1',
      title: 'Flight plans',
      providerId: 'openai',
      updatedAt: now,
      messages: [
        ChatTurn('user', 'book the trip to Karachi', time: now),
        ChatTurn('assistant', 'looking at fares', time: now + 60000),
      ],
    ));
  }

  Future<void> openThread(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('tab-chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('thread-th1')));
    await tester.pumpAndSettle();
  }

  testWidgets('the + inside a specific chat opens the dropdown first, '
      'not the explorer', (tester) async {
    final picker = _CountingPickerPlatform();
    ImagePickerPlatform.instance = picker;
    await pumpShell(tester);
    await seedThreads();
    await tester.pumpAndSettle();
    await openThread(tester);

    // The ChatPage owns its own input bar; tap ITS + button.
    final plusInChat = find.descendant(
      of: find.byType(ChatPage),
      matching: find.byKey(const ValueKey('attach-button')),
    );
    expect(plusInChat, findsOneWidget);
    await tester.tap(plusInChat);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('attach-menu')), findsOneWidget,
        reason: 'the dropdown shows Camera / Photos / Files first');
    expect(picker.calls, 0,
        reason: 'the explorer must NOT open before a menu row is chosen');

    // Choosing Photos is what opens the picker.
    await tester.tap(find.descendant(
      of: find.byKey(const ValueKey('attach-menu')),
      matching: find.text('Photos'),
    ));
    await tester.pumpAndSettle();
    expect(picker.calls, 1, reason: 'the picker opens only after Photos');
    expect(find.byKey(const ValueKey('attach-menu')), findsNothing,
        reason: 'the dropdown dismisses after the pick');
  });

  testWidgets('Wallet is removed from the menu and Security has its own '
      'screen', (tester) async {
    await pumpShell(tester);
    // Open the menu surface (avatar at top-right).
    await tester.tap(find.byKey(const ValueKey('avatar')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('menu-wallet'), skipOffstage: false),
        findsNothing,
        reason: 'the Wallet row is removed for now');
    expect(find.text('Wallet', skipOffstage: false), findsNothing);

    final security = find.byKey(const ValueKey('menu-security'),
        skipOffstage: false);
    expect(security, findsOneWidget);
    await tester.scrollUntilVisible(
      security,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(security);
    await tester.pumpAndSettle();

    expect(find.textContaining('Wallet', skipOffstage: false), findsNothing,
        reason: 'Security no longer opens the wallet screen');
  });

  testWidgets('no Wallet jump in search', (tester) async {
    await pumpShell(tester);
    // Search lives in the menu surface's search pill.
    await tester.tap(find.byKey(const ValueKey('avatar')));
    await tester.pumpAndSettle();
    final searchPill = find.byKey(const ValueKey('menu-search'),
        skipOffstage: false);
    await tester.scrollUntilVisible(
      searchPill,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(searchPill);
    await tester.pumpAndSettle();

    expect(find.text('Wallet', skipOffstage: false), findsNothing,
        reason: 'the wallet jump entry is gone');
  });

  testWidgets('primary buttons are black & white, never blue', (tester) async {
    // Light mode: primary = black background, white label.
    GlassColors.brightness.value = Brightness.light;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GButton(
              key: const ValueKey('bw-1'),
              label: 'Go',
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    var box = tester.renderObject<RenderDecoratedBox>(find.descendant(
      of: find.byKey(const ValueKey('bw-1')),
      matching: find.byType(DecoratedBox),
    ).first);
    var bg = (box.decoration as BoxDecoration).color!;
    expect(bg, const Color(0xFF111418),
        reason: 'light mode primary button is black');

    // Dark mode: primary = near-white background, black label. The static
    // brightness notifier doesn't rebuild a bare MaterialApp — re-pump so
    // paletteOf(context) resolves fresh.
    GlassColors.brightness.value = Brightness.dark;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GButton(
              key: const ValueKey('bw-1'),
              label: 'Go',
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    box = tester.renderObject<RenderDecoratedBox>(find.descendant(
      of: find.byKey(const ValueKey('bw-1')),
      matching: find.byType(DecoratedBox),
    ).first);
    bg = (box.decoration as BoxDecoration).color!;
    expect(bg, const Color(0xFFF2F4F7),
        reason: 'dark mode primary button is white');
    expect(bg, isNot(const Color(0xFF6EA8FE)), reason: 'no blue buttons');
  });

  testWidgets('corners are never edgy — radius tokens stay round',
      (tester) async {
    expect(RadiusTokens.sm, greaterThanOrEqualTo(10),
        reason: '4px corners read as edgy');
    expect(RadiusTokens.md, greaterThanOrEqualTo(14));
    expect(RadiusTokens.lg, greaterThanOrEqualTo(20));
    expect(RadiusTokens.xl, greaterThanOrEqualTo(24));
  });
}
