import 'dart:async';

import 'package:flutter/services.dart';

/// Movement 65 — the deep-link half of the Google sign-in.
///
/// The loopback flow (http://127.0.0.1:8636/callback) fails on phones that
/// kill the app's process while the browser is fullscreen: the listener dies
/// with the process, Google's redirect lands on nothing, and the user sits
/// on "site can't be reached" while the app shows nothing at all. The
/// deep-link flow survives that: Google redirects to
/// `dev.shayan.gork:/oauth2redirect?code=…`, Android fires an intent, and
/// the system starts (or wakes) the app with the code IN the intent — even
/// from a dead process.
///
/// Native side (MainActivity): the latest intent data is buffered with a
/// monotonically increasing id; [wait] either gets it at once or parks a
/// pending result that onNewIntent completes.
class ApplinkService {
  ApplinkService();

  static const MethodChannel _channel = MethodChannel('gork/applink');

  /// The LAST delivered link id — a later [wait] only completes on a NEWER
  /// intent, so an old code can never be consumed twice.
  int _lastSeen = 0;

  /// Resolves with the next `dev.shayan.gork:…` link after [_lastSeen].
  /// Throws [TimeoutException] when nothing arrives in [timeout].
  Future<Uri> wait({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    Map<dynamic, dynamic>? res;
    try {
      res = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('take', {
        'lastSeenId': _lastSeen,
      }).timeout(timeout);
    } on TimeoutException {
      // Release the native waiter so a retry parks a fresh one — the old
      // parked result must never answer a link a new waiter should see.
      try {
        await _channel.invokeMethod<void>('cancel');
      } catch (_) {}
      rethrow;
    }
    if (res == null || res['uri'] == null) {
      throw StateError('no sign-in redirect arrived');
    }
    _lastSeen = (res['id'] as num?)?.toInt() ?? _lastSeen;
    return Uri.parse(res['uri'].toString());
  }
}
