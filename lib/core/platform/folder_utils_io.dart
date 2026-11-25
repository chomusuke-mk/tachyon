import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:external_path/external_path.dart';
import 'package:tachyon/core/logging/app_logger.dart';
import 'package:win32_registry/win32_registry.dart';
import 'package:path/path.dart' as p;

typedef _GGetUserSpecialDirC = Pointer<Utf8> Function(Int32 directory);
typedef _GGetUserSpecialDirDart = Pointer<Utf8> Function(int directory);

/// Utilities for locating platform-specific media folders.
class FolderUtils {
  static const _log = ScopedLogger('FolderUtils');

  /// Resolves the user's standard music directory on the current platform.
  ///
  /// Returns `null` if the platform is unsupported or the directory cannot be
  /// resolved.
  static Future<Directory?> getMusicDirectory() async {
    if (Platform.isAndroid) {
      try {
        final path = await ExternalPath.getExternalStoragePublicDirectory(
          ExternalPath.DIRECTORY_MUSIC,
        );
        return Directory(path);
      } catch (e) {
        _log.w('Error getting music directory: $e');
      }
      return null;
    }
    if (Platform.isWindows) {
      try {
        final key = CURRENT_USER.open(
          r'Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
        );
        final path = key.getString('My Music');
        key.close();
        if (path != null && path.isNotEmpty) return Directory(path);
      } catch (e) {
        _log.w('Error getting music directory: $e');
      }
      return null;
    }

    if (Platform.isLinux) {
      try {
        final dylib = DynamicLibrary.process();
        final gGetUserSpecialDirPointer = dylib
            .lookupFunction<_GGetUserSpecialDirC, _GGetUserSpecialDirDart>(
              'g_get_user_special_dir',
            );
        final musicDirPointer = gGetUserSpecialDirPointer(
          3,
        ); // 3 corresponds to G_USER_DIRECTORY_MUSIC
        if (musicDirPointer != nullptr) {
          final musicDirPath = musicDirPointer.toDartString();
          if (musicDirPath.isNotEmpty) return Directory(musicDirPath);
        }
      } catch (e) {
        _log.w('Error getting music directory: $e');
      }
      return null;
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return Directory(p.join(home, 'Music'));
      }
    }

    return null;
  }

  /// Returns the path of the user's standard music directory, or `null` if
  /// unavailable.
  static Future<String?> getMusicDirectoryPath() async {
    final dir = await getMusicDirectory();
    return dir?.path;
  }
}
