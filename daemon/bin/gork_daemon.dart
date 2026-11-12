import 'package:gork_daemon/server.dart' as server;

/// Real entrypoint of the gork daemon.
///
/// `dart run bin/gork_daemon.dart` (systemd unit, Termux service,
/// gork-daemonctl) — the server logic lives in lib/server.dart so tests can
/// drive the handler directly.
Future<void> main(List<String> args) => server.main(args);
