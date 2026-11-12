import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gork/services/integrations.dart';
import 'package:gork/services/locator.dart';
import 'package:gork/services/secure_store.dart';
import 'package:gork/services/slack_service.dart';
import 'package:gork/services/spotify_service.dart';
import 'package:gork/services/strava_service.dart';
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
  group('SlackService', () {
    test('whoAmI returns user and team', () async {
      final c = _CapturingClient((req) => http.Response(
          jsonEncode({'ok': true, 'user': 'gork-bot', 'team': 'Shayan HQ'}),
          200));
      final s = SlackService(client: c, token: () async => 'xoxb-t');
      expect(await s.whoAmI(), 'gork-bot in Shayan HQ');
      expect(c.sent.single.url.toString(), 'https://slack.com/api/auth.test');
      expect(c.sent.single.headers['Authorization'], 'Bearer xoxb-t');
    });

    test('postMessage sends channel and text', () async {
      final c = _CapturingClient((req) =>
          http.Response(jsonEncode({'ok': true, 'ts': '1710000000.1'}), 200));
      final s = SlackService(client: c, token: () async => 'xoxb-t');
      final out = await s.postMessage(channel: '#general', text: 'hello');
      expect(out, contains('#general'));
      expect(c.sent.single.url.path, '/api/chat.postMessage');
      final body = jsonDecode(c.sent.single.body) as Map<String, dynamic>;
      expect(body['channel'], '#general');
      expect(body['text'], 'hello');
    });

    test('Slack ok:false becomes IntegrationException', () async {
      final c = _CapturingClient((req) =>
          http.Response(jsonEncode({'ok': false, 'error': 'channel_not_found'}), 200));
      final s = SlackService(client: c, token: () async => 'xoxb-t');
      await expectLater(
        s.postMessage(channel: '#nope', text: 'x'),
        throwsA(isA<IntegrationException>()
            .having((e) => e.message, 'message', contains('channel_not_found'))),
      );
    });

    test('channels returns #names', () async {
      final c = _CapturingClient((req) => http.Response(
          jsonEncode({
            'ok': true,
            'channels': [
              {'name': 'general'},
              {'name': 'random'}
            ]
          }),
          200));
      final s = SlackService(client: c, token: () async => 'xoxb-t');
      expect(await s.channels(), ['#general', '#random']);
    });
  });

  group('StravaService', () {
    test('whoAmI returns the athlete name', () async {
      final c = _CapturingClient((req) => http.Response(
          jsonEncode({'firstname': 'Shayan', 'lastname': 'K', 'id': 9}),
          200));
      final s = StravaService(client: c, token: () async => 'tok');
      expect(await s.whoAmI(), 'Shayan K');
      expect(c.sent.single.url.toString(), 'https://www.strava.com/api/v3/athlete');
    });

    test('recentActivities formats distance and time', () async {
      final c = _CapturingClient((req) => http.Response(
          jsonEncode([
            {'name': 'Morning Run', 'distance': 5240, 'moving_time': 1800}
          ]),
          200));
      final s = StravaService(client: c, token: () async => 'tok');
      final lines = await s.recentActivities();
      expect(lines.single, 'Morning Run — 5.2 km in 30m');
    });
  });

  group('SpotifyService', () {
    test('whoAmI returns display name', () async {
      final c = _CapturingClient(
          (req) => http.Response(jsonEncode({'display_name': 'Shayan'}), 200));
      final s = SpotifyService(client: c, token: () async => 'tok');
      expect(await s.whoAmI(), 'Shayan');
      expect(c.sent.single.url.toString(), 'https://api.spotify.com/v1/me');
    });

    test('nowPlaying describes the track', () async {
      final c = _CapturingClient((req) => http.Response(
          jsonEncode({
            'is_playing': true,
            'item': {
              'name': 'Naya Din',
              'artists': [
                {'name': 'A'}
              ]
            }
          }),
          200));
      final s = SpotifyService(client: c, token: () async => 'tok');
      final out = await s.nowPlaying();
      expect(out, 'Naya Din — A (playing)');
    });

    test('playPause pauses when playing, plays when paused', () async {
      final c = _CapturingClient((req) {
        if (req.url.path.endsWith('/me/player')) {
          return http.Response(jsonEncode({'is_playing': true}), 200);
        }
        return http.Response('', 204);
      });
      final s = SpotifyService(client: c, token: () async => 'tok');
      expect(await s.playPause(), 'paused');
      expect(c.sent.last.url.path, '/v1/me/player/pause');

      final c2 = _CapturingClient((req) {
        if (req.url.path.endsWith('/me/player')) {
          return http.Response(jsonEncode({'is_playing': false}), 200);
        }
        return http.Response('', 204);
      });
      final s2 = SpotifyService(client: c2, token: () async => 'tok');
      expect(await s2.playPause(), 'playing');
      expect(c2.sent.last.url.path, '/v1/me/player/play');
    });
  });

  group('Integration tools end to end', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      Locator.reset();
      Locator.bind(
        prefs: await SharedPreferences.getInstance(),
        store: InMemorySecureStore(),
      );
    });

    test('slack tools report not-connected without a token', () async {
      final registry = buildAppToolRegistry();
      expect(await registry.execute('slack_post_message',
          {'channel': '#x', 'text': 'y'}), contains('not connected'));
      expect(await registry.execute('spotify_now_playing', {}),
          contains('not connected'));
      expect(await registry.execute('strava_recent_activities', {}),
          contains('not connected'));
    });

    test('slack_post_message posts through the connected service',
        () async {
      Locator.bind(
        httpClient: _CapturingClient((req) =>
            http.Response(jsonEncode({'ok': true, 'ts': '1'}), 200)),
      );
      await Locator.integrations.vault.setToken('slack', 'xoxb-t');
      final registry = buildAppToolRegistry();
      final out = await registry
          .execute('slack_post_message', {'channel': '#gork', 'text': 'hi'});
      expect(out, contains('#gork'));
    });

    test('strava tool formats activities through the registry', () async {
      Locator.bind(
        httpClient: _CapturingClient((req) => http.Response(
            jsonEncode([
              {'name': 'Evening Ride', 'distance': 21000, 'moving_time': 3900}
            ]),
            200)),
      );
      await Locator.integrations.vault.setToken('strava', 'tok');
      final registry = buildAppToolRegistry();
      final out = await registry.execute('strava_recent_activities', {});
      expect(out, contains('Evening Ride — 21.0 km in 1h 5m'));
    });

    test('test connection covers slack, strava and spotify', () async {
      Locator.bind(
        httpClient: _CapturingClient((req) {
          if (req.url.host == 'slack.com') {
            return http.Response(jsonEncode({'ok': true, 'user': 'u'}), 200);
          }
          if (req.url.host == 'www.strava.com') {
            return http.Response(
                jsonEncode({'firstname': 'S', 'lastname': 'K'}), 200);
          }
          return http.Response(jsonEncode({'display_name': 'D'}), 200);
        }),
      );
      for (final id in ['slack', 'strava', 'spotify']) {
        await Locator.integrations.vault.setToken(id, 'tok');
        expect(await Locator.integrations.testConnection(id), isNull,
            reason: '$id should test OK');
      }
    });
  });
}
