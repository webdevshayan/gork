import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gork/screens/accounts_screen.dart';
import 'package:gork/screens/menu_screen.dart';
import 'package:gork/services/browser_service.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/tool_registry.dart';
import 'package:gork/services/vault_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 52 — the accounts screen (every website account logged into
/// from the app) and the AI's full browser with the secure paste-fill
/// protocol: the AI names a LABEL, the vault fills the field, and the
/// secret never reaches the model.

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
  setUpAll(() {
    HttpOverrides.global = _BlockedOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  Future<void> bind({http.Client? httpClient}) async {
    SharedPreferences.setMockInitialValues(
        httpClient != null ? {'vps.url': 'https://vps.example'} : {});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore()..write('vps.token', 'tok'),
      httpClient: httpClient,
    );
  }

  testWidgets('accounts screen lists VPS accounts and vault entries, '
      'never secrets', (tester) async {
    final stub = MockClient((request) async {
      if (request.url.path.endsWith('/v1/accounts')) {
        return http.Response(
            jsonEncode({
              'accounts': [
                {
                  'site': 'mail.google.com',
                  'username': 'shayanalibuilds@gmail.com',
                  'label': 'gmail-main',
                  'updated_at': 1,
                },
                {
                  'site': 'github.com',
                  'username': 'webdevshayan',
                  'label': 'gh-main',
                  'updated_at': 2,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 404);
    });
    await bind(httpClient: stub);
    await Locator.vault.save(const VaultEntry(
      id: 'v1',
      title: 'Mail login',
      username: 'shayanalibuilds@gmail.com',
      secret: 'super-secret-value',
      notes: '',
      createdAt: 1,
      aiAccess: true,
    ));

    await tester.pumpWidget(const MaterialApp(home: AccountsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('mail.google.com'), findsOneWidget);
    expect(find.text('github.com'), findsOneWidget);
    expect(find.text('webdevshayan'), findsOneWidget);
    expect(find.text('Mail login'), findsOneWidget);
    expect(find.textContaining('super-secret-value'), findsNothing,
        reason: 'no screen ever shows a secret');
    expect(find.textContaining('hunter2'), findsNothing);
  });

  testWidgets('the menu Accounts row opens the accounts screen',
      (tester) async {
    await bind();
    await tester.pumpWidget(const MaterialApp(home: MenuScreen()));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('menu-accounts')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('menu-accounts')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountsScreen), findsOneWidget);
    expect(find.text('Accounts'), findsWidgets);
  });

  test('browser tool without a VPS answers honestly', () async {
    await bind();
    final svc = BrowserService();
    final out = await svc.execute({'action': 'navigate', 'url': 'x'});
    expect(out, startsWith('error:'));
    expect(out, contains('VPS'));
  });

  test('browser ops and the secure fill ride one POST per op', () async {
    final bodies = <String>[];
    final paths = <String>[];
    final stub = MockClient((request) async {
      paths.add(request.url.path);
      bodies.add(request.body);
      return http.Response(
          jsonEncode({
            'ok': true,
            'result': {'url': 'https://example.com', 'title': 'Example'},
          }),
          200,
          headers: {'content-type': 'application/json'});
    });
    await bind(httpClient: stub);
    final svc = BrowserService();

    final out = await svc.execute({
      'action': 'navigate',
      'url': 'https://example.com',
      'session': 's9',
    });
    expect(out, contains('"url"'));

    // fill_secret: the label rides the request; the response carries no value.
    final fill = await svc.fillSecret('gmail-login', session: 's9');
    expect(fill, isNotNull);

    expect(paths, ['/v1/browser/op', '/v1/browser/op']);
    final fillBody = jsonDecode(bodies.last) as Map<String, dynamic>;
    expect(fillBody['action'], 'fill_secret');
    expect(fillBody['label'], 'gmail-login');
    expect(fillBody['session'], 's9');
    expect(jsonEncode(fill), isNot(contains('password')));
  });

  test('the registry exposes the browser tool with the secure-fill rule',
      () async {
    await bind();
    final registry = ToolRegistry(
      memory: Locator.memory,
      projects: Locator.projects,
      tasks: Locator.tasks,
      panels: Locator.panels,
      vault: Locator.vault,
      weather: Locator.weather,
      browser: BrowserService(),
    );
    expect(
        registry.defs.any((d) =>
            d.name == 'browser' &&
            d.description.contains('fill_secret') &&
            d.description.contains('NEVER type its value')),
        isTrue,
        reason: 'the model must learn the secure protocol from the tool');
    expect(registry.defs.any((d) => d.name == 'memory_op'), isTrue);
  });
}
