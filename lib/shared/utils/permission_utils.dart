import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Runtime permissions Tachyon needs before it can work properly.
enum AppPermission { music }

/// Thin wrapper over `permission_handler` that resolves the right platform
/// permission for each [AppPermission]. Only Android requires runtime grants;
/// on every other platform all permissions are reported as granted.
class PermissionUtils {
  PermissionUtils._();

  static bool get isRuntimeRequired => !kIsWeb && Platform.isAndroid;

  static Future<Permission> _resolve(AppPermission permission) async {
    switch (permission) {
      case AppPermission.music:
        final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
        return sdkInt >= 33 ? Permission.audio : Permission.storage;
    }
  }

  static Future<bool> isGranted(AppPermission permission) async {
    if (!isRuntimeRequired) return true;
    return (await _resolve(permission)).isGranted;
  }

  static Future<bool> isPermanentlyDenied(AppPermission permission) async {
    if (!isRuntimeRequired) return false;
    return (await _resolve(permission)).isPermanentlyDenied;
  }

  static Future<bool> areAllGranted() async {
    for (final permission in AppPermission.values) {
      if (!await isGranted(permission)) return false;
    }
    return true;
  }

  /// Requests [permission] and returns whether it ended up granted.
  static Future<bool> request(AppPermission permission) async {
    if (!isRuntimeRequired) return true;
    return (await (await _resolve(permission)).request()).isGranted;
  }

  static Future<bool> openSettings() => openAppSettings();
}
