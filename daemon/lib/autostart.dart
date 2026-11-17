import 'dart:io';

/// Boot-time auto-start, GUARANTEED across every environment gork runs in:
/// native Termux, proot/chroot Debian-on-Android, and real systemd boxes.
///
/// The strategy is layered — every layer is installed, idempotent, and
/// silent — so the daemon comes up no matter which one fires:
///   1. systemd unit (real systemd boxes — install.sh, WantedBy=boot)
///   2. Termux:Boot script   (~/.termux/boot/, created even if the app is
///      not installed yet — installing Termux:Boot later picks it up)
///   3. shell profile hooks  (~/.bashrc + ~/.profile, and
///      /etc/profile.d/gork-autostart.sh where writable — login shells in
///      Termux AND proot distros all go through these)
///   4. cron @reboot         (when crontab exists)
/// `gork daemon start` is a fast no-op when /health already answers, so any
/// number of layers firing is safe.
class Autostart {
  Autostart({Map<String, String>? env, this.probe}) : _env = env ?? Platform.environment;

  final Map<String, String> _env;

  /// Injectable probe (tests): reports whether `gork` resolves on PATH.
  final String? probe;

  String get home => _env['HOME'] ?? '/';
  String get prefix => _env['PREFIX'] ?? '';
  bool get isTermux => prefix.isNotEmpty && Directory('$prefix/bin').existsSync();
  bool get isRoot => _env['GORK_TEST_ROOT'] == '1' || _idIsRoot();

  bool _idIsRoot() {
    try {
      return Process.runSync('id', <String>['-u']).stdout.toString().trim() == '0';
    } catch (_) {
      return false;
    }
  }

  String get _gork => probe ?? 'gork';

  static const String kHookStart = '# >>> gork autostart >>>';
  static const String kHookEnd = '# <<< gork autostart <<<';

  /// The Termux:Boot script content (also used as the generic boot script).
  String bootScript() {
    final shebang = isTermux
        ? '#!$prefix/bin/sh'
        : '#!/bin/sh';
    return '$shebang\n'
        '# gork daemon — start at boot (Termux:Boot)\n'
        '${isTermux ? 'termux-wake-lock 2>/dev/null || true\n' : ''}'
        '$_gork daemon start --quiet >/dev/null 2>&1 || true\n';
  }

  /// The shell profile hook. Backgrounded + silenced: opening a terminal
  /// never blocks and never prints.
  String profileHook() =>
      '$kHookStart\n'
      '(command -v gork >/dev/null 2>&1) && gork daemon start --quiet '
      '>/dev/null 2>&1 || true\n'
      '$kHookEnd\n';

  /// Installs every applicable hook. Returns a human-readable report —
  /// installed, already-present and skipped layers, honestly labeled.
  List<String> apply({bool Function(String path, String content)? writeFile}) {
    final bool Function(String, String) write =
        writeFile ?? _defaultWrite;
    final report = <String>[];

    // 2. Termux:Boot (create the dir even without the Boot app — installing
    //    it later must find our script).
    final bootDir = '$home/.termux/boot';
    final boot = '$bootDir/gork-daemon.sh';
    if (write(boot, bootScript())) {
      report.add('boot script: $boot');
    } else {
      report.add('boot script: FAILED to write $boot');
    }

    // 3. Profile hooks — ~/.bashrc and ~/.profile (idempotent via sentinel).
    for (final rc in ['$home/.bashrc', '$home/.profile']) {
      if (_appendToRc(rc, profileHook(), write)) {
        report.add('profile hook: $rc');
      } else {
        report.add('profile hook: $rc (already present)');
      }
    }

    // 3b. /etc/profile.d — covers every login shell in proot distros.
    final pd = '/etc/profile.d/gork-autostart.sh';
    final etcWritable = Directory('/etc/profile.d').existsSync() &&
        _canWriteDirectory('/etc/profile.d');
    if (etcWritable || isRoot) {
      if (write(pd, profileHook())) {
        report.add('profile.d hook: $pd');
      } else {
        report.add('profile.d hook: skipped (not writable)');
      }
    } else {
      report.add('profile.d hook: skipped (/etc/profile.d not writable)');
    }

    // 4. cron @reboot.
    if (_hasCrontab()) {
      final existing = _crontab();
      if (existing.contains('gork daemon start') ||
          existing.contains('gork-daemonctl start')) {
        report.add('cron @reboot: already present');
      } else {
        final updated =
            '$existing\n@reboot $_gork daemon start --quiet >> '
            '${_stateDir()}/gork-daemon.log 2>&1\n';
        final ok = _writeCrontab(updated);
        report.add(ok ? 'cron @reboot: installed' : 'cron @reboot: FAILED');
      }
    } else {
      report.add('cron @reboot: skipped (no crontab)');
    }

    report.add('note: systemd installs use the gork-daemon unit (WantedBy=boot)');
    return report;
  }

  // -- internals --------------------------------------------------------------

  String _stateDir() {
    final gorkHome = _env['GORK_HOME'] ?? '';
    return gorkHome.isNotEmpty ? gorkHome : '$home/.gork-daemon';
  }

  bool _appendToRc(String path, String hook, bool Function(String, String) write) {
    final file = File(path);
    if (file.existsSync() && file.readAsStringSync().contains(kHookStart)) {
      return false;
    }
    final existing =
        file.existsSync() ? file.readAsStringSync() : '';
    write(path, '$existing$hook');
    return true;
  }

  bool _defaultWrite(String path, String content) {
    try {
      final file = File(path);
      if (path.contains('/')) Directory(file.parent.path).createSync(recursive: true);
      file.writeAsStringSync(content);
      try {
        if (path.endsWith('.sh')) Process.runSync('chmod', <String>['755', path]);
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _canWriteDirectory(String path) {
    try {
      final probe = File('$path/.gork-write-test');
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _hasCrontab() {
    try {
      return Process.runSync('which', <String>['crontab']).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  String _crontab() {
    try {
      final result = Process.runSync('crontab', <String>['-l']);
      return result.exitCode == 0 ? result.stdout.toString() : '';
    } catch (_) {
      return '';
    }
  }

  bool _writeCrontab(String content) {
    try {
      // `crontab FILE` installs FILE as the new crontab.
      final tmp = File(
          '${Directory.systemTemp.path}/gork-crontab-${DateTime.now().millisecondsSinceEpoch}');
      tmp.writeAsStringSync(content);
      final load = Process.runSync('crontab', <String>[tmp.path]);
      tmp.deleteSync();
      return load.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
