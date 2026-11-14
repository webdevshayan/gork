import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gork/services/outbox.dart';
import 'package:gork/services/secure_store.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Movement 48 — the end-to-end receipt: the REAL gork_server.py runs here
/// (Python subprocess) with a real stub provider. A message goes through the
/// app's own outbox to the VPS, is processed there, and the reply comes back
/// through the conversation-sync endpoint.
void main() {
  test('phone → VPS → provider → reply, over the real wire', () async {
    final tmpDb =
        '${Directory.systemTemp.path}/gork-it-${DateTime.now().microsecondsSinceEpoch}.sqlite3';
    final vps = await Process.start('python3', ['server/gork_server.py'], workingDirectory: Directory.current.path,
        environment: {
          'GORK_DB': tmpDb,
          'GORK_VPS_TOKEN': 'it-token',
          'GORK_PORT': '18990',
          'GORK_PROVIDER_URL': 'http://127.0.0.1:18991',
        });
    final provider = await Process.start('python3', ['server/fake_provider.py'], workingDirectory: Directory.current.path);
    vps.stderr.transform(utf8.decoder).listen((e) => stderr.writeln('[vps] $e'));
    provider.stderr
        .transform(utf8.decoder)
        .listen((e) => stderr.writeln('[provider] $e'));
    try {
      // Wait for the server to bind (retry /health).
      bool up = false;
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        try {
          final h = await http
              .get(Uri.parse('http://127.0.0.1:18990/health'))
              .timeout(const Duration(seconds: 2));
          if (h.statusCode == 200) { up = true; break; }
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
      expect(up, isTrue, reason: 'the VPS subprocess must come up');

      // Enqueue through the app's outbox (configured via prefs).
      SharedPreferences.setMockInitialValues({
        'vps.url': 'http://127.0.0.1:18990',
      });
      final prefs = await SharedPreferences.getInstance();
      final outbox = MessageOutbox(
        prefs: prefs,
        store: InMemorySecureStore()..write('vps.token', 'it-token'),
      );
      final entry =
          await outbox.enqueue('c1', 'hello from the phone', awaitAcceptance: true);
      expect(entry.jobId, isNotNull, reason: 'the VPS accepted the job');

      // Wait for the server worker to finish the job.
      String? reply;
      final replyDeadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(replyDeadline)) {
        reply = await outbox.jobResult(entry.jobId!);
        if (reply != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      expect(reply, contains('echo from the stub provider'),
          reason: 'the VPS worker called the provider and stored the reply');

      // Conversation sync: the full processed exchange is pullable — the
      // phone can come back from being dead and catch up.
      final sync = await http.get(
        Uri.parse('http://127.0.0.1:18990/v1/conversations/c1/messages'),
        headers: {'Authorization': 'Bearer it-token'},
      );
      final msgs =
          (jsonDecode(sync.body) as Map<String, dynamic>)['messages'] as List;
      expect(msgs, hasLength(2));
      expect(msgs[1]['content'], contains('echo from the stub provider'));
    } finally {
      vps.kill();
      provider.kill();
      final dbFile = File(tmpDb);
      if (await dbFile.exists()) await dbFile.delete();
    }
  }, timeout: const Timeout(Duration(seconds: 40)));
}
