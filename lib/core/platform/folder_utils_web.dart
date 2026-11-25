/// Web stub for locating platform-specific media folders.
class FolderUtils {
  /// Returns `null` because local filesystem directories are unavailable on web.
  static Future<String?> getMusicDirectoryPath() async => null;
}
