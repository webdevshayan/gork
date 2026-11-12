import 'dart:io';

import 'package:gork_daemon/cli_support.dart';

/// gork — configure and operate the daemon entirely from the terminal.
///
///   gork llm set openai && gork config set GORK_API_KEY sk-... && gork llm test
///   gork tasks add "Morning brief" "summarize my inbox" 60
///   gork status
///
/// Configuration is written to $GORK_HOME/config.env (default
/// ~/.gork-daemon/config.env) — no file editing, ever.
Future<void> main(List<String> args) async {
  final config = ConfigStore(configPath());
  try {
    // Pairing secret exists by default so phone connections are safe.
    await config.ensureSecret();
  } catch (_) {
    // Read-only filesystems still allow read-only commands.
  }
  final code = await runCli(
    args,
    config: config,
    out: (line) => stdout.writeln(line),
  );
  exit(code);
}
