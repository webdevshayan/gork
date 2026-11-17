import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gork/screens/security_screen.dart';
import 'package:gork/services/browser_service.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';

/// The Security screen must tell the truth about BOTH vaults: the one on
/// this phone and the sealed one on the VPS agent — by label, never by
/// value, with an honest state when the agent cannot be reached.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Locator.reset();
    Locator.bind(
      prefs: await SharedPreferences.getInstance(),
      store: InMemorySecureStore(),
    );
  });

  /// A BrowserService pointed at a configured agent (vps.url + token), with
  /// the HTTP layer faked by [fn].
  Future<BrowserService> vpsService(
      Future<http.Response> Function(http.Request) fn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vps.url', 'http://vps.test:8787');
    await Locator.store.write('vps.token', 'agent-secret');
    return BrowserService(client: MockClient(fn));
  }

  testWidgets('the agent vault lists its labels — and a leaked value is '
      'never rendered', (tester) async {
    final browser = await vpsService((request) async {
      expect(request.url.path, '/v1/vault');
      expect(request.headers['authorization'], 'Bearer agent-secret');
      return http.Response(
        jsonEncode({
          'entries': [
            // A well-behaved daemon never sends 'value'; the UI must not
            // render one even if a rogue server did.
            {'label': 'gmail-login', 'value': 'hunter2-leak'},
            {'label': 'github-token'},
          ],
          'count': 2,
        }),
        200,
      );
    });
    await tester.pumpWidget(
        MaterialApp(home: SecurityScreen(browser: browser)));
    await tester.pumpAndSettle();

    expect(find.text('gmail-login'), findsOneWidget);
    expect(find.text('github-token'), findsOneWidget);
    expect(find.text('hunter2-leak'), findsNothing,
        reason: 'values are never rendered, from any source');
    expect(find.text('ON YOUR VPS AGENT'), findsOneWidget);
    // The two sources coexist: the phone half keeps its own empty state.
    expect(find.textContaining('Nothing saved yet'), findsOneWidget);
  });

  testWidgets('an unreachable agent says so — it never fakes empty',
      (tester) async {
    final browser = await vpsService(
        (request) async => http.Response('boom', 500));
    await tester.pumpWidget(
        MaterialApp(home: SecurityScreen(browser: browser)));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't reach the VPS agent"),
        findsOneWidget);
    expect(find.textContaining('gork vault set'), findsNothing,
        reason: 'the add-a-secret hint is for a reachable, empty vault');
  });

  testWidgets('a reachable but empty agent vault explains how to add one',
      (tester) async {
    final browser = await vpsService(
        (request) async =>
            http.Response(jsonEncode({'entries': [], 'count': 0}), 200));
    await tester.pumpWidget(
        MaterialApp(home: SecurityScreen(browser: browser)));
    await tester.pumpAndSettle();

    expect(find.textContaining('gork vault set'), findsOneWidget);
  });

  testWidgets('without a configured agent there is no fetch and a hint '
      'instead', (tester) async {
    final browser = BrowserService(client: MockClient((request) async {
      fail('must not touch the network when no agent is configured');
    }));
    await tester.pumpWidget(
        MaterialApp(home: SecurityScreen(browser: browser)));
    await tester.pumpAndSettle();

    expect(find.text('ON YOUR VPS AGENT'), findsNothing);
    expect(find.textContaining('Connect one in Cloud Computer'),
        findsOneWidget);
  });
}
