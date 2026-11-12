import 'package:http/http.dart' as http;

import 'integrations.dart';

/// Spotify Web API with an OAuth access token.
/// Playback control needs Spotify Premium; reading needs user-read scopes.
class SpotifyService {
  static const String base = 'https://api.spotify.com/v1';

  final http.Client client;
  final Future<String?> Function() token;

  SpotifyService({required this.client, required this.token});

  Future<dynamic> _call(String method, String path,
      {Map<String, dynamic>? body}) async {
    final t = await token();
    if (t == null || t.isEmpty) {
      throw const IntegrationException('Spotify token missing — connect it in Integrations');
    }
    final uri = Uri.parse('$base$path');
    return jsonRequest(client, method, uri,
        headers: {'Authorization': 'Bearer $t'}, body: body);
  }

  /// Test connection: display name of the token owner.
  Future<String> whoAmI() async {
    final data = await _call('GET', '/me') as Map<String, dynamic>;
    return data['display_name'] as String? ?? 'spotify user';
  }

  /// What is playing right now, or a friendly "nothing".
  Future<String> nowPlaying() async {
    final data = await _call('GET', '/me/player/currently-playing')
        as Map<String, dynamic>;
    final item = data['item'] as Map<String, dynamic>?;
    if (item == null) return 'Nothing is playing right now';
    final name = item['name'] as String? ?? 'unknown track';
    final artists = [
      for (final a in (item['artists'] as List? ?? []))
        (a as Map<String, dynamic>)['name'] ?? ''
    ].where((s) => s.isNotEmpty).join(', ');
    final playing = data['is_playing'] == true;
    return '$name — $artists (${playing ? "playing" : "paused"})';
  }

  /// Toggle play/pause on the active device. Returns the new state.
  Future<String> playPause() async {
    final player = await _call('GET', '/me/player') as Map<String, dynamic>;
    final playing = player['is_playing'] == true;
    if (playing) {
      await _call('PUT', '/me/player/pause');
      return 'paused';
    }
    await _call('PUT', '/me/player/play');
    return 'playing';
  }
}
