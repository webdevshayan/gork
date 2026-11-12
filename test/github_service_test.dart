import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gork/services/github_service.dart';
import 'package:gork/services/integrations.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/tool_registry.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

InMemorySecureStore storeForTest() => InMemorySecureStore();

void main() {
  group('integration vault', () {
    test('tokens are namespaced per integration', () async {
      final vault = IntegrationVault(InMemorySecureStore());
      await vault.setToken('github', 'ghp_abc');
      await vault.setToken('slack', 'xoxb-123');
      expect(await vault.token('github'), 'ghp_abc');
      expect(await vault.token('slack'), 'xoxb-123');
      await vault.clearToken('github');
      expect(await vault.token('github'), isNull);
      expect(await vault.token('slack'), 'xoxb-123');
    });

    test('integration registry has the six planned services', () {
      final ids = kIntegrations.map((i) => i.id).toSet();
      expect(
          ids,
          containsAll(
              ['github', 'slack', 'strava', 'spotify', 'gmail', 'paypal']));
      final unique = kIntegrations.map((i) => i.id).toSet();
      expect(unique.length, kIntegrations.length);
      expect(integrationById('github')!.name, 'GitHub');
      expect(integrationById('nope'), isNull);
    });

    test('isConnected reflects the vault', () async {
      final store = InMemorySecureStore();
      final integ = Integrations(store, MockClient((_) async => http.Response('{}', 200)));
      expect(await integ.isConnected('github'), isFalse);
      await integ.vault.setToken('github', 'ghp_abc');
      expect(await integ.isConnected('github'), isTrue);
    });

    test('testConnection errors when no token is saved', () async {
      final integ = Integrations(
          InMemorySecureStore(), MockClient((_) async => http.Response('{}', 200)));
      expect(await integ.testConnection('github'), 'No token saved yet');
    });
  });

  group('jsonRequest error mapping', () {
    test('401 becomes unauthorized', () async {
      final client = MockClient((_) async => http.Response('{"m":"bad"}', 401));
      await expectLater(
        jsonRequest(client, 'GET', Uri.parse('https://x.test/a')),
        throwsA(isA<IntegrationException>()
            .having((e) => e.message, 'message', contains('unauthorized'))
            .having((e) => e.status, 'status', 401)),
      );
    });

    test('429 becomes rate limited', () async {
      final client = MockClient((_) async => http.Response('', 429));
      await expectLater(
        jsonRequest(client, 'GET', Uri.parse('https://x.test/a')),
        throwsA(isA<IntegrationException>()
            .having((e) => e.message, 'message', contains('rate limited'))),
      );
    });

    test('network failure becomes a friendly error', () async {
      final client = MockClient((_) => throw Exception('boom'));
      await expectLater(
        jsonRequest(client, 'GET', Uri.parse('https://x.test/a')),
        throwsA(isA<IntegrationException>()
            .having((e) => e.message, 'message', contains('network error'))),
      );
    });
  });

  group('GitHubService', () {
    late List<String> methods;
    late Uri? lastUri;
    late Map<String, String> lastHeaders;
    late Map<String, dynamic>? lastBody;
    late int status;
    late String responseBody;

    GitHubService makeService() => GitHubService(
          client: MockClient((req) async {
            methods.add(req.method);
            lastUri = req.url;
            lastHeaders = req.headers;
            lastBody = req.body.isEmpty ? null : jsonDecode(req.body);
            return http.Response(responseBody, status,
                headers: {'content-type': 'application/json'});
          }),
          token: () async => 'ghp_test',
        );

    setUp(() {
      methods = [];
      lastUri = null;
      lastHeaders = {};
      lastBody = null;
      status = 200;
      responseBody = '{}';
    });

    test('whoAmI hits /user with bearer auth and returns login', () async {
      responseBody = jsonEncode({'login': 'webdevshayan'});
      final login = await makeService().whoAmI();
      expect(login, 'webdevshayan');
      expect(lastUri.toString(), 'https://api.github.com/user');
      expect(lastHeaders['Authorization'], 'Bearer ghp_test');
    });

    test('missing token raises a friendly error before any request', () async {
      final service = GitHubService(
          client: MockClient((_) async => http.Response('{}', 200)),
          token: () async => null);
      await expectLater(
        service.whoAmI(),
        throwsA(isA<IntegrationException>()
            .having((e) => e.message, 'message', contains('token missing'))),
      );
    });

    test('notifications describe repo and subject', () async {
      responseBody = jsonEncode([
        {
          'subject': {'title': 'Fix login flow', 'type': 'PullRequest'},
          'repository': {'full_name': 'webdevshayan/gork'},
        }
      ]);
      final lines = await makeService().notifications();
      expect(lines, ['webdevshayan/gork · PullRequest: Fix login flow']);
      expect(lastUri!.path, '/notifications');
    });

    test('openIssues filters out pull requests', () async {
      responseBody = jsonEncode([
        {'number': 12, 'title': 'Real issue'},
        {'number': 13, 'title': 'PR masquerading', 'pull_request': {}},
        {'number': 14, 'title': 'Second issue'},
      ]);
      final lines = await makeService().openIssues('webdevshayan/gork');
      expect(lines, ['#12 Real issue', '#14 Second issue']);
      expect(lastUri!.queryParameters['state'], 'open');
    });

    test('createIssue posts title and body', () async {
      responseBody = jsonEncode(
          {'number': 42, 'html_url': 'https://github.com/webdevshayan/gork/issues/42'});
      final result = await makeService()
          .createIssue('webdevshayan/gork', title: 'Bug: crash', body: 'steps…');
      expect(result, contains('#42'));
      expect(methods, ['POST']);
      expect(lastBody!['title'], 'Bug: crash');
      expect(lastUri!.path, '/repos/webdevshayan/gork/issues');
    });

    test('401 from GitHub maps to a friendly message', () async {
      status = 401;
      await expectLater(
        makeService().whoAmI(),
        throwsA(isA<IntegrationException>()
            .having((e) => e.message, 'message', contains('unauthorized'))),
      );
    });
  });

  group('ToolRegistry github tools', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      Locator.reset();
      Locator.bind(
        prefs: await SharedPreferences.getInstance(),
        store: InMemorySecureStore(),
      );
    });

    test('tools report not-connected when no token is stored', () async {
      final registry = buildAppToolRegistry();
      expect(await registry.execute('github_notifications', {}),
          contains('not connected'));
      expect(await registry.execute('github_create_issue',
          {'repo': 'a/b', 'title': 'x'}), contains('not connected'));
    });

    test('github_list_issues returns formatted lines', () async {
      Locator.bind(
        store: storeForTest(),
        httpClient: MockClient((req) async {
          expect(req.url.host, 'api.github.com');
          return http.Response(
            jsonEncode([
              {'number': 7, 'title': 'Add tests'},
              {'number': 8, 'title': 'PR', 'pull_request': {}},
            ]),
            200,
          );
        }),
      );
      await Locator.integrations.vault.setToken('github', 'ghp_x');
      final registry = buildAppToolRegistry();
      final out = await registry.execute(
          'github_list_issues', {'repo': 'webdevshayan/gork'});
      expect(out, contains('#7 Add tests'));
      expect(out, isNot(contains('PR')));
    });
  });
}
