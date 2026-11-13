import 'package:flutter/services.dart';

/// Bridge to the native installer: hands a downloaded APK to the system
/// package installer and reads the per-app "Install unknown apps" state.
///
/// The app never flips settings itself — it can only open the system page
/// where the user grants the permission.
abstract class Installer {
  Future<bool> canInstall();
  Future<void> openPermissionSettings();
  Future<void> installApk(String path);
}

class SystemInstaller implements Installer {
  static const MethodChannel _channel = MethodChannel('gork/installer');

  @override
  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> openPermissionSettings() =>
      _channel.invokeMethod<void>('openPermissionSettings');

  @override
  Future<void> installApk(String path) =>
      _channel.invokeMethod<void>('installApk', {'path': path});
}
