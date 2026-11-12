import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gork/services/gmail_service.dart';
import 'package:gork/services/integrations.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/paypal_service.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/tool_registry.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _CapturingClient extends http.BaseClient {
  final http.Response Function(http.Request request) handler;
  final List<http.Request> sent = [];

  _CapturingClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sent.add(request as http.Request);
    final res = handler(request);
    return http.StreamedResponse(
        Stream.value(res.bodyBytes), res.statusCode,
        headers: res.headers);
  }
}

void main() {
  group('GmailService', () {
    test('whoAmI returns the mailbox address', () async {
      final c = _CapturingClient((req) =>
          http.Response(jsonEncode({'emailAddress': 'me@gmail.com'}), 200));
      final g = GmailService(client: c, token: () async => 'oauth-tok');
      expect(await g.whoAmI(), 'me@gmail.com');
      expect(c.sent.single.url.host, 'gmail.googleapis.com');
      expect(c.sent.single.headers['Authorization'], 'Bearer oauth-tok');
    });

    test('unread fetches each message and formats From — Subject',
        () async {
      final c = _CapturingClient((req) {
        if (req.url.path.endsWith('/messages')) {
          return http.Response(
              jsonEncode({
                'messages': [
                  {'id': 'a1'},
                  {'id': 'b2'},
                ]
              }),
              200);
        }
        final id = req.url.pathSegments.last;
        return http.Response(
            jsonEncode({
              'id': id,
              'payload': {
                'headers': [
                  {'name': 'From', 'value': 'Ali Raza <ali@corp.com>'},
                  {'name': 'Subject', 'value': 'Invoice #12'},
                  {'name': 'Date', 'value': 'today'},
                ]
              }
            }),
            200);
      });
      final g = GmailService(client: c, token: () async => 'oauth-tok');
      final lines = await g.unread();
      expect(lines, ['ali@corp.com — Invoice #12', 'ali@corp.com — Invoice #12']);
      expect(c.sent.length, 3); // 1 list + 2 gets
    });

    test('missing token raises before any request', () async {
      final g = GmailService(
          client: _CapturingClient(
              (req) => http.Response('{}', 200)),
          token: () async => null);
      await expectLater(g.whoAmI(),
          throwsA(isA<IntegrationException>()));
    });
  });

  group('PayPalService', () {
    test('token exchange uses basic auth and form body (live)', () async {
      final c = _CapturingClient((req) {
        if (req.url.path.endsWith('/oauth2/token')) {
          return http.Response(jsonEncode({'access_token': 'PP-1'}), 200);
        }
        return http.Response(jsonEncode({'transaction_details': []}), 200);
      });
      final p = PayPalService(client: c, token: () async => 'cid:secret');
      expect(await p.whoAmI(), 'connected (live)');
      final tokenReq = c.sent.first;
      expect(tokenReq.url.host, 'api-m.paypal.com');
      final expected = base64Encode(utf8.encode('cid:secret'));
      expect(tokenReq.headers['Authorization'], 'Basic $expected');
      expect(tokenReq.body, 'grant_type=client_credentials');
    });

    test('sandbox: prefix switches host and label', () async {
      final c = _CapturingClient((req) {
        if (req.url.path.endsWith('/oauth2/token')) {
          return http.Response(jsonEncode({'access_token': 'PP-1'}), 200);
        }
        return http.Response(jsonEncode({'transaction_details': []}), 200);
      });
      final p =
          PayPalService(client: c, token: () async => 'sandbox:cid:secret');
      expect(await p.whoAmI(), 'connected (sandbox)');
      expect(c.sent.first.url.host, 'api-m.sandbox.paypal.com');
    });

    test('malformed token gives a friendly error', () async {
      final p = PayPalService(
          client: _CapturingClient((req) => http.Response('{}', 200)),
          token: () async => 'just-a-client-id');
      await expectLater(
        p.whoAmI(),
        throwsA(isA<IntegrationException>()
            .having((e) => e.message, 'message', contains('client_id:secret'))),
      );
    });

    test('transactions format amount, status and note', () async {
      final c = _CapturingClient((req) {
        if (req.url.path.endsWith('/oauth2/token')) {
          return http.Response(jsonEncode({'access_token': 'PP-1'}), 200);
        }
        return http.Response(
            jsonEncode({
              'transaction_details': [
                {
                  'transaction_info': {
                    'transaction_amount': {'currency_code': 'USD', 'value': '25.00'},
                    'transaction_status': 'C',
                    'transaction_subject': 'Coffee beans',
                  }
                }
              ]
            }),
            200);
      });
      final p = PayPalService(client: c, token: () async => 'cid:secret');
      final lines = await p.transactions(days: 3);
      expect(lines.single, contains('USD 25.00'));
      expect(lines.single, contains('Coffee beans'));
      final txReq = c.sent.last;
      expect(txReq.url.path, '/v1/reporting/transactions');
      expect(txReq.url.queryParameters['fields'], 'transaction_info');
      expect(txReq.headers['Authorization'], 'Bearer PP-1');
    });
  });

  group('Gmail/PayPal tools', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      Locator.reset();
      Locator.bind(
        prefs: await SharedPreferences.getInstance(),
        store: InMemorySecureStore(),
      );
    });

    test('not-connected tools return friendly errors', () async {
      final registry = buildAppToolRegistry();
      expect(await registry.execute('gmail_unread', {}),
          contains('not connected'));
      expect(await registry.execute('paypal_recent_transactions', {}),
          contains('not connected'));
    });

    test('gmail_unread flows through the registry', () async {
      Locator.bind(
        httpClient: _CapturingClient((req) {
          if (req.url.host == 'gmail.googleapis.com') {
            if (req.url.path.endsWith('/messages')) {
              return http.Response(
                  jsonEncode({
                    'messages': [
                      {'id': 'x'}
                    ]
                  }),
                  200);
            }
            return http.Response(
                jsonEncode({
                  'payload': {
                    'headers': [
                      {'name': 'From', 'value': 'boss@corp.com'},
                      {'name': 'Subject', 'value': 'Standup notes'},
                    ]
                  }
                }),
                200);
          }
          return http.Response('{}', 200);
        }),
      );
      await Locator.integrations.vault.setToken('gmail', 'tok');
      final registry = buildAppToolRegistry();
      final out = await registry.execute('gmail_unread', {});
      expect(out, contains('boss@corp.com — Standup notes'));
    });

    test('paypal tool returns no-transactions text', () async {
      Locator.bind(
        httpClient: _CapturingClient((req) {
          if (req.url.path.endsWith('/oauth2/token')) {
            return http.Response(jsonEncode({'access_token': 'PP-1'}), 200);
          }
          return http.Response(jsonEncode({'transaction_details': []}), 200);
        }),
      );
      await Locator.integrations.vault.setToken('paypal', 'cid:secret');
      final registry = buildAppToolRegistry();
      final out = await registry.execute('paypal_recent_transactions', {});
      expect(out, contains('no transactions'));
    });
  });
}
