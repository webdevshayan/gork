import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../constants/version.dart';
import '../services/installer.dart';
import '../services/update_service.dart';
import '../widgets/glass.dart';
import '../widgets/screen.dart';

/// Check for updates, download the release APK, hand it to the system
/// installer. Every step says what it is doing; failures are shown verbatim.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({
    super.key,
    this.currentVersion = kAppVersion,
    this.service,
    this.installer,
    this.downloadDir,
  });

  final String currentVersion;
  final UpdateService? service;
  final Installer? installer;
  final String? downloadDir;

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

enum _Phase { idle, checking, upToDate, available, downloading, readyToInstall, error }

class _UpdatesScreenState extends State<UpdatesScreen> {
  late final Installer _installer = widget.installer ?? SystemInstaller();
  UpdateService? _service;
  _Phase _phase = _Phase.idle;
  ReleaseInfo? _release;
  String? _error;
  double? _progress;
  String? _apkPath;
  bool _canInstall = true;

  UpdateService _buildService(String dir) => widget.service ??
      UpdateService(client: http.Client(), currentVersion: widget.currentVersion, downloadDir: dir);

  Future<String> _resolveDownloadDir() async {
    if (widget.downloadDir != null) return widget.downloadDir!;
    final tmp = await getTemporaryDirectory();
    return '${tmp.path}${Platform.pathSeparator}updates';
  }

  Future<void> _check() async {
    setState(() {
      _phase = _Phase.checking;
      _error = null;
    });
    final dir = await _resolveDownloadDir();
    final service = _buildService(dir);
    _service = service;
    final check = await service.check();
    if (!mounted) return;
    setState(() {
      switch (check.status) {
        case UpdateStatus.available:
          _release = check.latest;
          _phase = _Phase.available;
        case UpdateStatus.upToDate:
          _release = check.latest;
          _phase = _Phase.upToDate;
        case UpdateStatus.unknown:
          _error = check.error ?? 'unknown error';
          _phase = _Phase.error;
      }
    });
  }

  Future<void> _download() async {
    final release = _release;
    if (release == null || _service == null) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = null;
      _error = null;
    });
    try {
      final file = await _service!.downloadApk(
        release,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? done / total : null;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _apkPath = file.path;
        _phase = _Phase.readyToInstall;
      });
      _refreshCanInstall();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _phase = _Phase.error;
      });
    }
  }

  Future<void> _refreshCanInstall() async {
    try {
      final can = await _installer.canInstall();
      if (!mounted) return;
      setState(() => _canInstall = can);
    } catch (_) {
      // Unknown state — the install attempt itself will tell the truth.
    }
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;
    if (!_canInstall) {
      await _installer.openPermissionSettings();
      return;
    }
    try {
      await _installer.installApk(path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'the system installer refused: $e';
        _phase = _Phase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Screen(
      title: 'Updates',
      body: ListView(
        children: [
          GlassContainer(
            radius: 28,
            opacity: 0.45,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Installed version',
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.currentVersion,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                _body(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.idle:
        return _blackPill(
          key: 'updates-check',
          label: 'Check for updates',
          onTap: _check,
        );
      case _Phase.checking:
        return const Padding(
          key: ValueKey('updates-checking'),
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Asking GitHub…', style: TextStyle(color: Colors.black54)),
            ],
          ),
        );
      case _Phase.upToDate:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          key: const ValueKey('updates-up-to-date'),
          children: [
            const Text(
              'You are on the latest release.',
              style: TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            _blackPill(key: 'updates-check', label: 'Check again', onTap: _check),
          ],
        );
      case _Phase.available:
        final release = _release!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          key: const ValueKey('updates-available'),
          children: [
            Text(
              '${release.tag} is available',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            if (release.prerelease)
              const Text(
                'pre-release — may be rough',
                style: TextStyle(fontSize: 13, color: Colors.black45),
              ),
            if (release.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                release.notes,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 12),
            _blackPill(
              key: 'updates-download',
              label: 'Download ${release.apkName}',
              onTap: _download,
            ),
          ],
        );
      case _Phase.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          key: const ValueKey('updates-downloading'),
          children: [
            Text(
              _progress == null
                  ? 'Downloading…'
                  : 'Downloading… ${(_progress! * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        );
      case _Phase.readyToInstall:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          key: const ValueKey('updates-ready'),
          children: [
            Text(
              'Downloaded. The system installer will open — Android may ask '
              'you to allow installs from gork first.',
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),
            if (!_canInstall) ...[
              const SizedBox(height: 8),
              const Text(
                'That permission is currently off.',
                style: TextStyle(fontSize: 14, color: Colors.black45),
              ),
            ],
            const SizedBox(height: 12),
            _blackPill(
              key: 'updates-install',
              label: _canInstall ? 'Install' : 'Open install settings',
              onTap: _install,
            ),
          ],
        );
      case _Phase.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          key: const ValueKey('updates-error'),
          children: [
            Text(
              _error ?? 'something went wrong',
              style: const TextStyle(fontSize: 15, color: Colors.redAccent),
            ),
            const SizedBox(height: 12),
            _blackPill(key: 'updates-retry', label: 'Try again', onTap: _check),
          ],
        );
    }
  }

  Widget _blackPill({
    required String key,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: ValueKey(key),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
